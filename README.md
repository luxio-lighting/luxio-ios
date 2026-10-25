# Luxio iOS

Native SwiftUI controls, color/gradient editor, animations, Matter pairing and manual firmware updates.

```sh
xcodegen generate --spec project.yml
xcodebuild -project Luxio.xcodeproj -scheme Luxio -sdk iphoneos -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedDataDevice \
  DEVELOPMENT_TEAM=YOUR_TEAM -allowProvisioningUpdates build
```

The home-screen plus button opens Add Luxio, with a link to the build guide at https://luxio.lighting/, manual IP/hostname connection with inline errors, and a subtle virtual-device link. Successful connections and virtual devices open directly in the controls.

Firmware updates are in each light's settings. An available update opens a sheet with an Install button, matching Wi-Fi setup. The same sheet shows download progress, waits for the device to reconnect on the expected build before confirming success, and offers recovery when installation fails. Checking does not install; there are no automatic installs.

Discovery starts with local mDNS (`_luxio._tcp`). If startup mDNS finds no reachable Luxio, discovery falls back to the cloud device list. Manually pulling down the home list also queries the cloud; background polling stays local. Candidates must answer a local state request before appearing; background local checks remove unreachable devices and bring them back when they recover. Opening a card uses its cached address and state immediately. Startup placeholders use the last discovered device count, and both pull-to-refresh controls remain active for at least 500 ms.

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

## Virtual device

The empty home screen offers **Try the Simulator**, which opens a 60-LED RGBCCT
Luxio Simulator. It supports the normal color/white editor, gradients, animations,
parameters, power, brightness and saved libraries. Its local device API uses no
HTTP; state and saved items persist on the phone. Animated headers and tiles use
the same native Lua preview runtime. Settings allow renaming, changing LED count,
and removing the simulator; hardware-only firmware and Matter controls are hidden.
`npm run test:simulator` checks these local controls, library persistence and that
no network requests are sent.

## Bluetooth and Wi-Fi setup (firmware build 24)

The iOS app discovers the Luxio GATT service alongside Bonjour. Allow Bluetooth
access when prompted and keep Luxio nearby. A successful state request supplies
the fingerprint, so Wi-Fi and Bluetooth discoveries share one light and client.
Colors, power, brightness, saved resources, animation uploads and Matter pairing
codes use the same Protobuf operations over either transport. Requests over BLE
are queued, framed and fragmented at the negotiated write size; timeouts,
cancellation and disconnects reset the connection before another request.

Open a light's settings → Wi-Fi to scan networks, enter credentials and connect.
A hidden network can be entered manually; open networks do not need a password.
Credentials are sent to the light and are not saved in the app. Firmware 24
requires an encrypted BLE link and uses OS pairing for the displayless device.
The Matter QR/manual code remains under settings → Matter → Show Pairing Code.
Matter commissioning uses the light's Wi-Fi connection; Bluetooth is Luxio's
setup/control transport.

Known network addresses remain usable when Bluetooth becomes unavailable, and
BLE can take over when LAN requests fail. While using BLE, state refreshes probe
Wi-Fi at most once every ten seconds and switch back after a valid response from
the same light. A LAN address reported over BLE can be used before Bonjour
resolves. The device list shows the active transport icon before the name.
Only read-only state requests are
retried automatically across transports: an ambiguous mutation is never replayed.
Bluetooth scanning/connections pause in the background and resume in foreground.
Manual refresh restarts discovery, including after a rejected pairing attempt.

`npm run test:bluetooth` tests framing boundaries, malformed/oversized frames,
transport routing, Wi-Fi signal decoding, cancellation and mutation replay
protection. `testWifiSetupAndMatterCode` exercises the setup and QR screens using
the local UI fixture. Simulator tests cannot qualify the physical BLE radio.

Firmware build 27 adds optional relay control in Settings: Relay, Relay GPIO and
Invert Relay. It defaults to disabled; GPIO0 is a valid relay pin. The relay GPIO
must differ from Data Pin. GL-C-016WL-D revisions use GPIO12 without inversion
(older manual) or GPIO18 with inversion (current manufacturer manual); data stays
on GPIO16. Check the controller revision. Older firmware shows the setting
disabled until updated.

The physically tested GL-C-016WL-D unit requires Relay GPIO18 with inversion off,
with data on GPIO16. Verify polarity on the actual unit: app On must supply strip
power. The model name alone does not determine the relay revision or polarity.

Build 28 hides Matter settings when the firmware reports `matter_disabled`. Older
firmware without that capability flag keeps its existing Matter controls.

Firmware build 34 adds Enable Wi-Fi and Enable Matter as the first switches in their settings sections. Saving either change restarts the controller. Disabling the app’s current Wi-Fi transport requires confirmation; Bluetooth changes do not. Both switches default enabled, and availability remains separate from the Matter preference. SK6812 exposes a single white channel and is also available in the local simulator.
