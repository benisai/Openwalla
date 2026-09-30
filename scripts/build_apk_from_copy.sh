#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_DIR="${OPENWALLA_BUILD_DIR:-$PROJECT_ROOT/.openwalla-apk-build}"
BUILD_DIR_NAME="$(basename "$BUILD_DIR")"
OUTPUT_DIR="${OPENWALLA_APK_OUTPUT_DIR:-$PROJECT_ROOT/dist/apk}"
APK_TEST_DIR="${OPENWALLA_APK_TEST_DIR:-$PROJECT_ROOT/APK-TEST}"
APK_TEST_ABI="${OPENWALLA_APK_TEST_ABI:-arm64-v8a}"
APK_TEST_MAX_BYTES="${OPENWALLA_APK_TEST_MAX_BYTES:-99000000}"
BUILD_MODE="release"
UPLOAD_RELEASE=false
COPY_APK_TEST=false
SPLIT_PER_ABI=false
GIT_APK_TEST=false
PUBSPEC_VERSION="$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | awk '{print $2}')"
APP_VERSION="${PUBSPEC_VERSION%%+*}"
APK_TEST_VERSION="${OPENWALLA_APK_TEST_VERSION:-v$APP_VERSION}"
APK_TEST_COMMIT_MESSAGE="${OPENWALLA_APK_TEST_COMMIT_MESSAGE:-Update APK test build $APK_TEST_VERSION}"

usage() {
  echo "Usage: $0 [debug|profile|release] [--upload] [--apk-test] [--split-per-abi] [--apk-test-git] [--pixel-test]" >&2
  echo "  --upload  Build split APKs, copy target ABI into APK-TEST/, then git add/commit/push it." >&2
  echo "  --apk-test  Build split APKs and copy the configured test ABI into APK-TEST/." >&2
  echo "  --split-per-abi  Build smaller ABI-specific APKs." >&2
  echo "  --apk-test-git  After --apk-test, git add/commit/push copied APK test artifacts." >&2
  echo "  --pixel-test  Shortcut for: debug --split-per-abi --apk-test --apk-test-git." >&2
  echo "Set OPENWALLA_APK_TEST_ABI to choose which split APK goes into APK-TEST (default: arm64-v8a)." >&2
  echo "Set OPENWALLA_APK_TEST_VERSION to override the APK filename/commit suffix (default: v<pubspec version>)." >&2
  echo "Set OPENWALLA_APK_TEST_MAX_BYTES to override the git artifact size guard (default: 99000000)." >&2
  echo "Set OPENWALLA_APK_TEST_COMMIT_MESSAGE to override the APK test commit message." >&2
}

find_apksigner() {
  if command -v apksigner >/dev/null 2>&1; then
    command -v apksigner
    return 0
  fi

  local sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -z "$sdk_dir" && -d "$HOME/Library/Android/sdk" ]]; then
    sdk_dir="$HOME/Library/Android/sdk"
  fi

  if [[ -n "$sdk_dir" && -d "$sdk_dir/build-tools" ]]; then
    find "$sdk_dir/build-tools" -name apksigner -type f | sort | tail -n 1
    return 0
  fi

  return 1
}

for arg in "$@"; do
  case "$arg" in
    debug|profile|release)
      BUILD_MODE="$arg"
      ;;
    --upload)
      UPLOAD_RELEASE=true
      COPY_APK_TEST=true
      SPLIT_PER_ABI=true
      GIT_APK_TEST=true
      ;;
    --apk-test)
      COPY_APK_TEST=true
      SPLIT_PER_ABI=true
      ;;
    --split-per-abi)
      SPLIT_PER_ABI=true
      ;;
    --apk-test-git)
      GIT_APK_TEST=true
      COPY_APK_TEST=true
      SPLIT_PER_ABI=true
      ;;
    --pixel-test)
      BUILD_MODE="debug"
      SPLIT_PER_ABI=true
      COPY_APK_TEST=true
      GIT_APK_TEST=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case "$BUILD_MODE" in
  debug|profile|release)
    ;;
  *)
    usage
    exit 2
    ;;
esac

echo "Preparing clean build copy: $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude '.git/' \
    --exclude '.dart_tool/' \
    --exclude '.gradle/' \
    --exclude "$BUILD_DIR_NAME/" \
    --exclude '.flutter-plugins' \
    --exclude '.flutter-plugins-dependencies' \
    --exclude 'APK-TEST/' \
    --exclude 'android/.gradle/' \
    --exclude 'build/' \
    --exclude 'dist/' \
    "$PROJECT_ROOT/" "$BUILD_DIR/"
else
  tar -C "$PROJECT_ROOT" \
    --exclude './.git' \
    --exclude './.dart_tool' \
    --exclude './.gradle' \
    --exclude "./$BUILD_DIR_NAME" \
    --exclude './.flutter-plugins' \
    --exclude './.flutter-plugins-dependencies' \
    --exclude './APK-TEST' \
    --exclude './android/.gradle' \
    --exclude './build' \
    --exclude './dist' \
    -cf - . | tar -C "$BUILD_DIR" -xf -
fi

rm -rf "$BUILD_DIR/.gradle" "$BUILD_DIR/android/.gradle"

echo "Resolving dependencies"
flutter pub get --directory "$BUILD_DIR"

if [[ -f "$BUILD_DIR/android/gradle.properties" ]]; then
  {
    echo ""
    echo "# Openwalla temp-copy build isolation"
    echo "org.gradle.daemon=false"
    echo "org.gradle.caching=false"
  } >> "$BUILD_DIR/android/gradle.properties"
fi

echo "Building APK ($BUILD_MODE)"
(
  cd "$BUILD_DIR"
  build_args=(apk "--$BUILD_MODE")
  if [[ "$SPLIT_PER_ABI" == true ]]; then
    build_args+=(--split-per-abi)
  fi
  GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.daemon=false" \
    flutter build "${build_args[@]}"
)

APK_GLOB="$BUILD_DIR/build/app/outputs/flutter-apk/app-*-$BUILD_MODE.apk"
if [[ "$SPLIT_PER_ABI" != true ]]; then
  APK_GLOB="$BUILD_DIR/build/app/outputs/flutter-apk/app-$BUILD_MODE.apk"
fi
shopt -s nullglob
APK_PATHS=($APK_GLOB)
shopt -u nullglob
if [[ "${#APK_PATHS[@]}" -eq 0 ]]; then
  echo "Expected APK was not created: $APK_GLOB" >&2
  exit 1
fi

APKSIGNER="$(find_apksigner || true)"
if [[ -z "$APKSIGNER" ]]; then
  echo "Could not find apksigner; unable to verify whether the APK is installable." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_APKS=()
APK_TEST_PATHS=()
for apk_path in "${APK_PATHS[@]}"; do
  if ! "$APKSIGNER" verify --verbose "$apk_path" >/dev/null 2>&1; then
    echo "APK was built but is not signed, so Android will reject it during install: $apk_path" >&2
    echo "For local Pixel testing, run: $0 debug --split-per-abi" >&2
    echo "For release builds, create android/key.properties pointing to a release keystore, then rerun: $0 release" >&2
    exit 1
  fi

  apk_name="$(basename "$apk_path")"
  abi_name="${apk_name#app-}"
  abi_name="${abi_name%-$BUILD_MODE.apk}"
  if [[ "$SPLIT_PER_ABI" == true ]]; then
    output_apk="$OUTPUT_DIR/openwalla-$BUILD_MODE-$abi_name.apk"
  else
    output_apk="$OUTPUT_DIR/openwalla-$BUILD_MODE.apk"
  fi
  cp "$apk_path" "$output_apk"
  OUTPUT_APKS+=("$output_apk")
  echo "APK created: $output_apk"
done


if [[ "$COPY_APK_TEST" == true ]]; then
  mkdir -p "$APK_TEST_DIR"
  find "$APK_TEST_DIR" -maxdepth 1 -type f -name '*.apk' -delete
  for output_apk in "${OUTPUT_APKS[@]}"; do
    output_name="$(basename "$output_apk")"
    suffix="${output_name#openwalla-$BUILD_MODE}"
    suffix="${suffix%.apk}"
    if [[ "$SPLIT_PER_ABI" == true && "$suffix" != "-$APK_TEST_ABI" ]]; then
      continue
    fi
    if [[ -n "$suffix" ]]; then
      test_apk="$APK_TEST_DIR/openwalla-test-$APK_TEST_VERSION$suffix.apk"
    else
      test_apk="$APK_TEST_DIR/openwalla-test-$APK_TEST_VERSION.apk"
    fi
    cp "$output_apk" "$test_apk"
    APK_TEST_PATHS+=("$test_apk")
    echo "APK test copy created: $test_apk"
  done
fi

if [[ "$GIT_APK_TEST" == true ]]; then
  if [[ "$COPY_APK_TEST" != true ]]; then
    echo "--apk-test-git requires --apk-test." >&2
    exit 2
  fi
  if [[ "${#APK_TEST_PATHS[@]}" -eq 0 ]]; then
    echo "No APK test artifact was copied; nothing to commit." >&2
    exit 1
  fi

  for apk_test_path in "${APK_TEST_PATHS[@]}"; do
    apk_size="$(wc -c < "$apk_test_path" | tr -d ' ')"
    if [[ "$apk_size" -gt "$APK_TEST_MAX_BYTES" ]]; then
      echo "APK test artifact is too large for git/GitHub: $apk_test_path (${apk_size} bytes)." >&2
      echo "GitHub blocks files over 100 MB. Use --split-per-abi or set OPENWALLA_APK_TEST_ABI to a smaller target." >&2
      exit 1
    fi
  done

  echo "Staging APK test artifacts"
  git -C "$PROJECT_ROOT" add -u -- "$APK_TEST_DIR"
  git -C "$PROJECT_ROOT" add -- "${APK_TEST_PATHS[@]}"

  if git -C "$PROJECT_ROOT" diff --cached --quiet -- "$APK_TEST_DIR"; then
    echo "APK test artifacts are unchanged; skipping commit and push."
  else
    echo "Committing APK test artifacts"
    git -C "$PROJECT_ROOT" commit -m "$APK_TEST_COMMIT_MESSAGE"
    echo "Pushing APK test commit"
    git -C "$PROJECT_ROOT" push
  fi
fi

if [[ "$UPLOAD_RELEASE" == true ]]; then
  echo "--upload completed using git add, git commit, and git push for APK-TEST artifacts."
fi
