// Local-only UI fixture. Does not connect to a physical light.
import { createServer } from 'node:http';
import { isDeepStrictEqual } from 'node:util';
import { Device } from '../shared/device/src/device.js';
import { decodeRequest, encodeResponse, colorSchema } from '../shared/protocol/src/index.js';
const device = new Device('ui-fixture'); device.state.config.name = 'Library test'; device.state.brightness = 16;
const colors = [colorSchema.parse({ blue: 255 }), colorSchema.parse({ green: 255 })];
for (let i = 0; i < 130; i++) device.handle({ id: i, operation: 20, gradient: { id: '', name: `Ocean ${i + 1}`, colors } });
device.handle({ id: 131, operation: 17, gradient: { id: '', name: '', colors } });
const fixtures = new Map<string, Device>();
for (const [path, strip, count] of [['/rgb-single/api', 'WS2812', 1], ['/rgbw-single/api', 'WS2814', 1], ['/rgbcct-two/api', 'WS2805', 2]] as const) {
  const fixture = new Device(path); fixture.state.config.name = 'Library test'; fixture.state.config.stripType = strip; fixture.state.config.ledCount = count;
  fixtures.set(path, fixture);
}
const parameterDevice = new Device('parameter-fixture-' + crypto.randomUUID()); parameterDevice.state.config.name = 'Library test';
const parameterAnimation = parameterDevice.handle({ id: 200, operation: 7, script: { id: '', name: 'Parameterized', source: '-- @parameter Flicker,Checkbox,true\n-- @parameter Speed,Slider,50,0,100\n-- @parameter Spacing,Number,8,1,64\nfunction loop() end' } }).script!;
parameterDevice.handle({ id: 201, operation: 10, scriptId: parameterAnimation.id });
fixtures.set('/parameters/api', parameterDevice);
const oldDevice = new Device('old-animation-fixture'); oldDevice.state.build = 20; oldDevice.state.config.name = 'Library test';
oldDevice.handle({ id: 202, operation: 31, script: { id: '', name: 'Luxio · Ember', source: 'function loop() end' } });
fixtures.set('/old-animation/api', oldDevice);
const staleDevice = new Device('stale-animation-fixture'); staleDevice.state.config.name = 'Library test';
staleDevice.handle({ id: 203, operation: 31, script: { id: '', name: 'Luxio · Ember', source: 'function loop() end' } });
fixtures.set('/stale-animation/api', staleDevice);
const optionsDevice = new Device('options-fixture-' + crypto.randomUUID()); optionsDevice.state.config.name = 'Library test';
fixtures.set('/options/api', optionsDevice);
const slowDevice = new Device('slow-fixture'); slowDevice.state.config.name = 'Library test';
for (let i = 1; i <= 2; i++) {
  slowDevice.handle({ id: 300 + i, operation: 27, savedColor: { id: '', name: `Saved color ${i}`, color: colors[i - 1] } });
  slowDevice.handle({ id: 310 + i, operation: 20, gradient: { id: '', name: `Saved gradient ${i}`, colors } });
  slowDevice.handle({ id: 320 + i, operation: 7, script: { id: '', name: `Saved animation ${i}`, source: '-- @preview ff0000,0000ff\nfunction loop() end' } });
}
fixtures.set('/slow/api', slowDevice);
const animationDevice = new Device('animation-fixture'); animationDevice.state.config.name = 'Library test';
animationDevice.handle({ id: 350, operation: 7, script: { id: '', name: 'Saved animation', source: '-- @preview ff0000,0000ff\nfunction loop() end' } });
fixtures.set('/animations/api', animationDevice);
const liveDevice = new Device('live-fixture'); liveDevice.state.config.name = 'Library test';
liveDevice.handle({ id: 400, operation: 31, script: { id: '', name: 'Live rainbow', source: `-- @preview ff0000,0000ff
function loop()
 for i=0,luxio_get_pixel_count()-1 do
  local t=luxio_millis()/400+i/10
  luxio_set_pixel_color(i,math.floor(127+127*math.sin(t)),math.floor(127+127*math.sin(t+2)),math.floor(127+127*math.sin(t+4)))
 end
end` } });
fixtures.set('/live/api', liveDevice);
const settingsDevice = new Device('settings-fixture'); settingsDevice.state.config.name = 'Library test'; settingsDevice.state.build = 34;
fixtures.set('/settings/api', settingsDevice);
const relayDevice = new Device('relay-fixture'); relayDevice.state.config.name = 'Library test'; relayDevice.state.build = 27; relayDevice.state.config.gpio = 16;
fixtures.set('/relay/api', relayDevice);
const saveDevice = new Device('save-tiles-fixture'); saveDevice.state.config.name = 'Library test';
fixtures.set('/save-tiles/api', saveDevice);
const whiteDevice = new Device('white-drag-fixture'); whiteDevice.state.config.name = 'Library test';
whiteDevice.handle({ id: 500, operation: 1, color: colorSchema.parse({ warmWhite: 128, coolWhite: 127 }) });
fixtures.set('/white-drag/api', whiteDevice);
const pointDevice = new Device('point-selection-fixture'); pointDevice.state.config.name = 'Library test';
fixtures.set('/point-selection/api', pointDevice);
const renameDevice = new Device('rename-fixture'); renameDevice.state.config.name = 'Library test';
const renameColor = renameDevice.handle({ id: 600, operation: 27, savedColor: { id: '', name: 'Saved color', color: colorSchema.parse({ red: 23, green: 45, blue: 67, warmWhite: 89, coolWhite: 12 }) } }).savedColor!;
const renameGradient = renameDevice.handle({ id: 601, operation: 20, gradient: { id: '', name: 'Saved gradient', colors, editorMetadata: '{"custom":"preserve these editor coordinates"}' } }).gradient!;
const renameAnimation = renameDevice.handle({ id: 602, operation: 7, script: { id: '', name: 'Saved animation', source: '-- @preview ff0000,0000ff\n-- @parameter Speed,Number,50,0,100\nfunction loop() end', parameters: [{ name: 'Speed', boolean: false, value: 73, defaultValue: 50, minimum: 0, maximum: 100 }] } }).script!;
fixtures.set('/rename/api', renameDevice);
const wifiDevice = new Device('wifi-fixture'); wifiDevice.state.config.name = 'Library test'; wifiDevice.state.lanIp = '';
let wifiConnected = false;
let updateCheckUntil = 0;
const updateDevices = new Map<string, { device: Device; started: number }>();
for (const path of ['/update-install', '/update-error']) {
  const device = new Device(path); device.state.config.name = 'Library test'; device.state.build = 34;
  device.state.lanIp = `127.0.0.1:${process.env.LUXIO_UI_TEST_PORT ?? 8082}${path}`;
  updateDevices.set(path, { device, started: 0 });
}
createServer(async (request, response) => {
  const updatePath = request.url?.replace(/\/(api|status)$/, '');
  const update = updateDevices.get(updatePath ?? '');
  if (update && request.url?.endsWith('/status')) {
    response.setHeader('Content-Type', 'application/json');
    response.end(JSON.stringify({ build: 35, received: Date.now() - update.started < 8000 ? 25 : 100, size: 100,
      error: updatePath === '/update-error' ? 'Firmware signature verification failed' : '' })); return;
  }
  const chunks: Buffer[] = []; for await (const chunk of request) chunks.push(Buffer.from(chunk));
  const input = decodeRequest(Buffer.concat(chunks));
  if (update) {
    if (input.operation === 13) { update.started = 0; update.device.state.build = 34; }
    if (input.operation === 14) {
      if (update.started) { response.end(encodeResponse({ id: input.id, error: 'Duplicate installation request' })); return; }
      update.started = Date.now();
    }
    if (update.started && Date.now() - update.started >= 20000 && updatePath !== '/update-error') update.device.state.build = 35;
    response.setHeader('Content-Type', 'application/x-protobuf');
    response.end(encodeResponse({ ...update.device.handle({ id: input.id, operation: 0 }), availableBuild: 35 })); return;
  }
  if (request.url === '/updates/api') {
    if (input.operation === 13) updateCheckUntil = Date.now() + 6000;
    response.setHeader('Content-Type', 'application/x-protobuf');
    response.end(encodeResponse({ ...settingsDevice.handle({ id: input.id, operation: 0 }), availableBuild: 0, updateChecking: Date.now() < updateCheckUntil })); return;
  }
  if (request.url === '/wifi/api' || request.url === '/wifi-slow/api') {
    if (request.url === '/wifi-slow/api' && input.operation === 16) await new Promise(resolve => setTimeout(resolve, 8000));
    if (input.operation === 4) {
      if (!((['Test Network', 'Hidden Network'].includes(input.wifi?.ssid ?? '') && input.wifi?.password === 'test-password') || (input.wifi?.ssid === 'Open Network' && input.wifi.password === ''))) {
        response.end(encodeResponse({ id: input.id, error: 'Incorrect fixture credentials' })); return;
      }
      wifiConnected = true; wifiDevice.state.lanIp = '192.0.2.10';
    }
    const result = [4, 16].includes(input.operation) ? wifiDevice.handle({ id: input.id, operation: 0 }) : wifiDevice.handle(input);
    if (input.operation === 16) result.wifiNetworks = [{ ssid: 'Test Network', rssi: -42, passwordRequired: true }, { ssid: 'Open Network', rssi: -65, passwordRequired: false }];
    if (input.operation === 12) { result.error = ''; result.pairingCode = '34970112332'; result.pairingQr = 'MT:WIFI-UI-FIXTURE'; }
    response.setHeader('Content-Type', 'application/x-protobuf');
    response.end(encodeResponse({ ...result, networkStatus: { connected: wifiConnected, ssid: wifiConnected ? 'Test Network' : '', gateway: wifiConnected ? '192.0.2.1' : '', dns: wifiConnected ? ['192.0.2.1'] : [] } })); return;
  }
  if (request.url === '/action-errors/api') {
    response.setHeader('Content-Type', 'application/x-protobuf');
    response.end(encodeResponse(input.operation === 0 ? settingsDevice.handle(input) : {
      id: input.id, error: [5, 18, 25].includes(input.operation) ? 'Background library timeout' : 'Test connection timed out'
    })); return;
  }
  if (request.url === '/unreachable/api') {
    await new Promise(resolve => setTimeout(resolve, 2500));
    response.writeHead(503); response.end(); return;
  }
  if (request.url === '/cached/api' && input.operation === 0) await new Promise(resolve => setTimeout(resolve, 2500));
  if (['/parameters/api', '/options/api'].includes(request.url ?? '') && [7, 8].includes(input.operation)) { response.end(encodeResponse({ id: input.id, error: 'Settings must stay local to the phone' })); return; }
  if (request.url === '/rename/api' && [28, 21, 8].includes(input.operation)) {
    const original = input.operation === 28 ? renameColor : input.operation === 21 ? renameGradient : renameAnimation;
    const updated = input.operation === 28 ? input.savedColor : input.operation === 21 ? input.gradient : input.script;
    // A rename must preserve every other field, including IDs and customized parameters.
    if (!updated || Object.keys(original).some(key => key !== 'name' && !isDeepStrictEqual(original[key as keyof typeof original], updated[key as keyof typeof updated]))) {
      response.end(encodeResponse({ id: input.id, error: 'Rename changed saved content' })); return;
    }
  }
  if (request.url === '/slow/api' && [1, 10, 11, 17, 23, 30, 31].includes(input.operation)) await new Promise(resolve => setTimeout(resolve, 6000));
  response.setHeader('Content-Type', 'application/x-protobuf');
  const result = request.url === '/settings/api' && input.operation === 12
    ? { id: input.id, error: '', scripts: [], pairingCode: '34970112332', pairingQr: 'MT:SETTINGS-UI-FIXTURE', availableBuild: 0 }
    : (fixtures.get(request.url ?? "") ?? device).handle(input);
  if (request.url === '/settings/api') result.networkStatus = { connected: true, ssid: 'Home Wi-Fi', gateway: '192.0.2.1', dns: ['192.0.2.1', '1.1.1.1'] };
  response.end(encodeResponse(result));
}).listen(Number(process.env.LUXIO_UI_TEST_PORT ?? 8082), '127.0.0.1', () => console.log('Library UI fixture: 127.0.0.1:8082'));
