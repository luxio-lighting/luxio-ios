# Luxio 1.2.1 — App Store release

Bundle ID: `lighting.luxio`. Version: `1.2.1`. Build: `65`.
App Store Connect app: `6828093615`, owned by Emile B.V. (team `FY9967QY8V`).
Submitted on 25 November 2026; Apple reports **Waiting for Review**.
The release is configured for automatic distribution after Apple approval.

## Build and export

```sh
xcodebuild -project Luxio.xcodeproj -scheme Luxio -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath .sdk/ReleaseDerivedData \
  -archivePath .sdk/releases/Luxio-1.2.1-65.xcarchive \
  DEVELOPMENT_TEAM=FY9967QY8V -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath .sdk/releases/Luxio-1.2.1-65.xcarchive \
  -exportPath .sdk/releases/app-store-1.2.1-65 -exportOptionsPlist release/ExportOptions.plist \
  -allowProvisioningUpdates
```

App Store distribution export may require the existing team API key through
`-authenticationKeyPath`, `-authenticationKeyID` and `-authenticationKeyIssuerID`.
Credentials and private keys are kept only in the ignored `.sdk/app-store-connect/`
directory. Never commit them or print keys or access tokens.

`app-store-api.py` uses the configured local team key for App Store Connect API
requests. For example:

```sh
python3 release/app-store-api.py GET '/v1/apps?filter[bundleId]=lighting.luxio'
```

## Submission

`metadata.json`, `release-notes.txt` and `review-notes.txt` describe this release.
The approved iPhone screenshots are retained. Five new landscape iPad screenshots
show the sidebar layout with the same demonstration devices. Raw captures and
captioned PNGs are in `screenshots/ipad-13/`. `PrivacyInfo.xcprivacy` and the
app's encryption declaration are included in the archive. The app requires no
account, purchase or hardware to explore its Simulator.

Upload the signed IPA, wait for a VALID build, attach build 65 to version 1.2.1,
verify metadata and `releaseType=AFTER_APPROVAL`, add the version to a review
submission, and submit that review submission. `app-store-status.json` records
the verified remote state; `build-manifest.json` records the archive and IPA.

Version 1.2.1 adds the native iPad device sidebar, selection-specific controls,
portrait and landscape layouts, and a centered color/temperature selector. The
existing iPhone navigation remains unchanged. The iPad selection/rotation test
and three iPhone navigation tests passed. Build 63 (the same application changes,
versioned 1.2.0 for local testing) was installed and approved on Emile’s iPad Pro.
Build 65 uses version 1.2.1 because Apple has already released version 1.2.0.

The release also supports Apple-silicon Macs through Designed for iPad. The Mac
uses the sidebar layout and provides a refresh button and Command-R shortcut.
