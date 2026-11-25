# iPad App Store screenshots

`ipad-13/` contains the five current landscape marketing screenshots for Luxio 1.2.1, at 2752 × 2064. The matching native simulator captures are in `ipad-13/raw/`. These replace the old portrait set. The approved iPhone set is in [`../marketing-v2/`](../marketing-v2/).

The iPad set shows the new device sidebar alongside color, gradient and animation controls, plus Settings and Matter. It uses the same demonstration devices as the phone: Living Room, Bedroom, Kitchen, Studio (Bluetooth), and Hallway (off, last). Cyberpunk is the animation example. The Matter QR payload is deliberately nonfunctional.

Run `./release/screenshots/render-ipad.sh` from the repository to regenerate the captioned PNGs with Google Chrome. `render-ipad.py` reads the approved phone captions and fonts. Both the raw captures and rendered images are landscape.

To recapture, use an isolated checkout of the app. Apply `capture-only.patch`, copy `IPadMarketingScreenshots.swift` into `UITests/`, and regenerate the project using XcodeGen. Set `LUXIO_SCREENSHOT_SIMULATOR` to a booted 13-inch iPad simulator UUID and run `node --import tsx release/screenshots/fixture.ts`. Run only `LuxioUITests/IPadMarketingScreenshots/testCapture` on that simulator. The fixture saves each screenshot through `simctl`, avoiding XCTest's rotation cropping. Restart the fixture before each run to reset the demo devices. The capture patch and demo fixture are not included in the shipping app.
