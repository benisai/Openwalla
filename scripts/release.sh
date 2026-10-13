#!/usr/bin/env bash

# Creates an Openwalla release tag. GitHub Actions builds and publishes the APK/AAB.
# Usage: ./scripts/release.sh [major|minor|patch]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    printf '%b\n' "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    printf '%b\n' "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    printf '%b\n' "${RED}[ERROR]${NC} $1" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

if [ ! -f pubspec.yaml ] || [ ! -f .github/workflows/release.yml ]; then
    print_error "Release files are missing from $PROJECT_ROOT."
    exit 1
fi

if [ "$(git branch --show-current)" != "main" ]; then
    print_error "Releases must be created from the main branch."
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    print_error "Working directory is not clean. Commit or stash changes first."
    exit 1
fi

print_status "Checking origin/main and release tags..."
git fetch --quiet origin main --tags
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    print_error "Local main is not synchronized with origin/main. Pull or push changes first."
    exit 1
fi

CURRENT_VERSION="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
CURRENT_NAME="${CURRENT_VERSION%%+*}"
CURRENT_BUILD="${CURRENT_VERSION#*+}"

if [ -z "$CURRENT_VERSION" ] || [ "$CURRENT_NAME" = "$CURRENT_VERSION" ]; then
    print_error "pubspec.yaml must contain a version in name+build format."
    exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_NAME"
if ! [[ "$MAJOR" =~ ^[0-9]+$ && "$MINOR" =~ ^[0-9]+$ && "$PATCH" =~ ^[0-9]+$ && "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
    print_error "Unsupported version format: $CURRENT_VERSION"
    exit 1
fi

RELEASE_TYPE="${1:-patch}"
case "$RELEASE_TYPE" in
    major)
        NEW_NAME="$((MAJOR + 1)).0.0"
        ;;
    minor)
        NEW_NAME="$MAJOR.$((MINOR + 1)).0"
        ;;
    patch)
        NEW_NAME="$MAJOR.$MINOR.$((PATCH + 1))"
        ;;
    *)
        print_error "Invalid release type. Use major, minor, or patch."
        exit 1
        ;;
esac

NEW_BUILD=$((CURRENT_BUILD + 1))
NEW_VERSION="$NEW_NAME+$NEW_BUILD"
TAG_VERSION="v$NEW_NAME"

if git rev-parse "$TAG_VERSION" >/dev/null 2>&1; then
    print_error "Tag $TAG_VERSION already exists."
    exit 1
fi

print_status "Current app version: $CURRENT_VERSION"
print_status "Proposed app version: $NEW_VERSION"
print_status "Git tag: $TAG_VERSION"
printf '\n'
read -r -p "Create and publish $TAG_VERSION? (y/N): " REPLY
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    print_warning "Release cancelled."
    exit 0
fi

print_status "Updating pubspec.yaml..."
sed -i.bak "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
rm pubspec.yaml.bak

print_status "Committing version $NEW_VERSION..."
git add pubspec.yaml
git commit \
    -m "Release Openwalla $TAG_VERSION" \
    -m "uploaded from macbook"

print_status "Pushing main..."
git push origin main

print_status "Creating and pushing $TAG_VERSION..."
git tag -a "$TAG_VERSION" -m "Openwalla $TAG_VERSION (build $NEW_BUILD)"
git push origin "$TAG_VERSION"

print_status "$TAG_VERSION was dispatched. GitHub Actions will publish the signed APK and AAB."
print_status "Track it at https://github.com/benisai/Openwalla/actions/workflows/release.yml"
