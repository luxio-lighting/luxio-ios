# Privacy disclosure review

Source audit supporting the store privacy declarations submitted on 28 October 2026.

- No account, advertising SDK, analytics SDK or cross-app tracking was found in the apps.
- Local app preferences, the virtual device and animation parameters remain in app storage.
- Wi-Fi credentials are sent to the selected controller. They are not sent to the discovery API by the apps.
- Discovery requests reach api.luxio.lighting, which receives the public source IP. The server matches it against device announcements.
- The controller announcement service stores public IP, LAN IP, device identifier (public-key fingerprint), public key, device name, firmware build/channel and timestamps. A device name can contain user-entered information.
- Android's legacy location permission is restricted to Android 11 and earlier for BLE discovery. No location API use was found; Bluetooth scan uses neverForLocation on newer Android versions.

On 28 October 2026, the owner confirmed that the production API/proxy does not retain request logs. Controller records have no automatic expiry; the one-hour discovery filter does not delete them. Verification challenges expire after two minutes. Complete Apple’s App Privacy and Google’s Data safety forms consistently with the controller discovery behavior; do not infer “no data collected” solely from absent analytics or request logs.

The website policy at https://luxio.lighting/privacy.html was updated in website commit 0ec2434 to describe discovery metadata, retention, local communication, and info@luxio.lighting for privacy questions/deletion requests. The store privacy forms were completed after the owner unlocked the Mac.

Store guidance consulted: https://developer.apple.com/app-store/app-privacy-details/ and https://support.google.com/googleplay/android-developer/answer/10787469. Apple’s definition depends on retention beyond a real-time request; Google’s includes off-device transmission. Consider data sent to the controller and later announced to the discovery API, not just direct mobile-to-cloud calls. See the completed declaration below.

## Submitted iOS declaration — 28 October 2026

Published with the owner’s explicit confirmation: Device ID, Other User Content (controller names), and Other Data (network/firmware metadata). All are used for App Functionality, linked through the controller identifier, and not used for tracking. Apple accepted version 1.0.0 build 58 for review; state WAITING_FOR_REVIEW.
