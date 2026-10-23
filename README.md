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

Requires firmware build 13 for the independent libraries. The color and gradient editors save named copies to the device. Animation presets offer Save to device in their context menu. Colors, gradients and animations appear in grids within the main scroll view. My Colors, My Gradients and My Animations show saved items with search and long-press deletion. Colors and gradients apply on tap; only animations have play/stop controls. Pull to refresh after uploads from another client. Large libraries are fetched in pages. Wheel edits and built-in presets play directly from RAM without creating files.

For the saved-library UI test, start `node --import tsx tools/test-library-server.ts`, then run the `Luxio` scheme tests on an iOS simulator. The fixture binds only localhost:8082 and the debug-only launch environment points the test at it; physical lights are not involved.

Gradient controls are available only with more than one LED/controller. WS2805 exposes warm/cool white, WS2814 exposes one neutral white channel, and WS2812 exposes RGB only. Changes to the device configuration update these controls immediately.

Firmware build 14 reports active animation parameters. The selected animation card expands to reveal a sliders button, which opens its settings. Changes apply without restarting and are remembered locally on the phone, separately for each light and animation, then reapplied when selecting it again. **Reset to Defaults** restores the values declared in the Lua source. Live values on the light remain in RAM.

Firmware build 19 adds `-- @preview ff460c,d21400,ffc823` in leading Lua comments
(two to eight RGB hex stops). The app uses the supplied palette in active device
headers, home cards and saved-animation swatches. Native gradients use their
actual stops. Palette RGB values interpolate directly over 0.4 seconds, including changes in
stop count, without fading through the background. Missing animation previews
use a neutral background. Saved color and gradient swatches fetch their actual
channels as cards appear; listings only contain names and IDs. Built-in animations include previews.

## Live animation previews

The header and visible home tiles run the active animation locally using the
vendored Lua 5.4 runtime. Firmware 20 supplies the active source and live
parameters with GET_SCRIPT and an empty ID, including RAM-only Studio animations.
`animation_revision` identifies a new run even when its name/ID stays the same.
The app fetches source once per visible run and renders locally at about 30 fps;
it does not stream LED frames. Lua runs off the main thread with the firmware's
128 KiB memory and 100,000-instruction limits, a time budget, and no filesystem,
network, OS, package, or debug libraries. Only the required Lua libraries are built.

Previews stop off-screen, while backgrounded, when power is off, or with Reduce
Motion. Failures fall back to the `@preview` palette. The simulation starts locally
and is illustrative: randomness and accumulated state are not frame-synchronized
with the physical strip. Swatches retain the app's full-brightness presentation.
`npm run test:animation` checks output, parameters, sandboxing, and resource limits.

Animation presets include preview palettes and live parameters. `Slider` and `Checkbox` declarations require firmware build 21 or newer; `Number` selects a numeric input. Older firmware parameter metadata continues to display numeric values as sliders. `Boolean` remains a legacy alias for `Checkbox`.
