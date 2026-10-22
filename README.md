# Luxio iOS

Native SwiftUI controls, color/gradient editor, animations, Matter pairing and manual firmware updates.

```sh
xcodegen generate --spec project.yml
xcodebuild -project Luxio.xcodeproj -scheme Luxio -sdk iphoneos -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedDataDevice \
  DEVELOPMENT_TEAM=YOUR_TEAM -allowProvisioningUpdates build
```

Firmware updates are in each light's settings. Checking does not install. Installation requires a separate tap, explains the offline period, and offers the recovery page if the download fails. There are no automatic installs.

## Local verification

The app and tests use only this checkout. Node dependencies are required only for the cross-language and preset checks:

```sh
npm ci
npm run check
npm test
```

Swift test caches and generated fixtures live in the ignored `.sdk/` directory. No shared SDK or neighboring Luxio repository is required.
