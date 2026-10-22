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

The gradient editor can save named copies to the device. My Gradients and My Animations show saved custom items, with search, play/stop and long-press deletion. Pull to refresh after uploads from another client. Large libraries are fetched in pages.

For the saved-library UI test, start `node --import tsx tools/test-library-server.ts`, then run the `Luxio` scheme tests on an iOS simulator. The fixture binds only localhost:8082 and the debug-only launch environment points the test at it; physical lights are not involved.
