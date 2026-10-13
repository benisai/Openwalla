# Releasing Openwalla

`scripts/release.sh` bumps the app version, commits it to `main`, and pushes an annotated version tag. The tag starts the GitHub Actions release workflow, which tests the project, builds signed Android artifacts, and publishes a GitHub Release containing:

- a versioned APK;
- a versioned Android App Bundle for Google Play; and
- SHA-256 checksums for both files.

The script does not build an APK on your computer.

## One-time GitHub setup

Create these repository Actions secrets under **Settings > Secrets and variables > Actions**:

- `ANDROID_KEYSTORE_BASE64`: the release keystore encoded as one base64 value.
- `ANDROID_KEY_PROPERTIES_BASE64`: the complete `android/key.properties` file encoded as one base64 value.

On macOS, encode each file and copy its value to the clipboard with:

```bash
base64 -i /path/to/openwalla-release.jks | pbcopy
base64 -i android/key.properties | pbcopy
```

Create or update one GitHub secret after running each command.

The decoded `key.properties` file must use the keystore filename created by the workflow:

```properties
storePassword=your-store-password
keyPassword=your-key-password
keyAlias=your-key-alias
storeFile=openwalla-release.jks
```

Never commit the keystore, passwords, `key.properties`, or their encoded values. Keep a separate backup of the signing key. Losing it can prevent future app updates.

## Publish a release

Start on a clean, synchronized `main` branch and run one of:

```bash
./scripts/release.sh patch
./scripts/release.sh minor
./scripts/release.sh major
```

After confirmation, follow the workflow at:

<https://github.com/benisai/Openwalla/actions/workflows/release.yml>

The completed release appears at:

<https://github.com/benisai/Openwalla/releases>
