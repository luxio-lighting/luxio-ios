# Luxio 1.1.0 — App Store release

Bundle ID: `lighting.luxio`. Version: `1.1.0`. Build: `59`.
App Store Connect app: `6828093615`, owned by Emile B.V. (team `FY9967QY8V`).
The release is configured for automatic distribution after Apple approval.

## Build and export

```sh
xcodebuild -project Luxio.xcodeproj -scheme Luxio -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath .sdk/ReleaseDerivedData \
  -archivePath .sdk/releases/Luxio-1.1.0.xcarchive \
  DEVELOPMENT_TEAM=FY9967QY8V -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath .sdk/releases/Luxio-1.1.0.xcarchive \
  -exportPath .sdk/releases/app-store-1.1.0 -exportOptionsPlist release/ExportOptions.plist \
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
The existing approved screenshots are retained. `PrivacyInfo.xcprivacy` and the
app's encryption declaration are included in the archive. The app requires no
account, purchase or hardware to explore its Simulator.

Upload the signed IPA, wait for a VALID build, attach build 59 to version 1.1.0,
verify metadata and `releaseType=AFTER_APPROVAL`, add the version to a review
submission, and submit that review submission. `app-store-status.json` records
the verified remote state; `build-manifest.json` records the archive and IPA.

The user authorized committing, uploading, submitting for review and automatic
release after approval for this version. Android publishing remains separate
and requires approval of its preview images first.
