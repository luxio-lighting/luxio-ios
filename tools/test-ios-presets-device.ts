// Run test-ios-presets.ts first. Explicit opt-in: this briefly changes the strip.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { colorSchema, requestHttp, type State } from '../shared/protocol/src/index.js';
const address = process.env.DEVICE_ADDRESS;
if (!address) throw new Error('Set DEVICE_ADDRESS to the test strip');
const presets: { name: string; colors: number[][]; source: string; isGradient: boolean }[] = JSON.parse(readFileSync('.sdk/ios-presets.json', 'utf8'));
let id = 1;
const current = (await requestHttp(address, { id: id++, operation: 0 })).state!;
const initial = process.env.RESTORE_STATE_FILE ? JSON.parse(readFileSync(process.env.RESTORE_STATE_FILE, 'utf8')) : current;
assert.equal(current.deviceId, initial.deviceId);
assert.deepEqual(current.config, initial.config);
assert.ok(current.build >= 21);
try {
  await requestHttp(address, { id: id++, operation: 2, brightness: 16 });
  for (const preset of presets) {
    if (preset.isGradient) {
      const colors = preset.colors.map(c => colorSchema.parse({ red: c[0], green: c[1], blue: c[2] }));
      await requestHttp(address, { id: id++, operation: 17, gradient: { id: '', name: '', colors } });
    } else await requestHttp(address, { id: id++, operation: 31, script: { id: '', name: preset.name, source: preset.source, mode: 2 } });
    await new Promise(resolve => setTimeout(resolve, 1200));
    const playing: State = (await requestHttp(address, { id: id++, operation: 0 })).state!;
    assert.equal(playing.mode, preset.isGradient ? 1 : 2);
    assert.equal(playing.activeScriptId, ''); assert.equal(playing.activeGradientId, '');
    const dimmed = await requestHttp(address, { id: id++, operation: 2, brightness: 8 });
    assert.equal(dimmed.state!.mode, preset.isGradient ? 1 : 2);
    const stopped = await requestHttp(address, { id: id++, operation: preset.isGradient ? 24 : 11 });
    assert.equal(stopped.state!.mode, 0);
    await requestHttp(address, { id: id++, operation: 2, brightness: 16 });
    console.log(`PASS: ${preset.name} starts, survives Lua frames and brightness changes, and stops on 60-controller WS2805`);
  }
  await requestHttp(address, { id: id++, operation: 15, on: false });
  await new Promise(resolve => setTimeout(resolve, 600));
  assert.equal((await requestHttp(address, { id: id++, operation: 0 })).state!.on, false);
} finally {
  await requestHttp(address, { id: id++, operation: 1, color: initial.color });
  await requestHttp(address, { id: id++, operation: 2, brightness: initial.brightness });
  if (initial.mode === 1 && initial.gradient) await requestHttp(address, { id: id++, operation: initial.activeGradientId ? 23 : 17, gradientId: initial.activeGradientId, gradient: initial.gradient });
  if (initial.activeColorId) await requestHttp(address, { id: id++, operation: 30, colorId: initial.activeColorId });
  if (initial.activeScriptId) await requestHttp(address, { id: id++, operation: 10, scriptId: initial.activeScriptId });
  await requestHttp(address, { id: id++, operation: 15, on: initial.on });
  console.log('Restored the original color, brightness, and animation.');
}
