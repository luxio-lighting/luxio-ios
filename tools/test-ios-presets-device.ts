// Run test-ios-presets.ts first. Explicit opt-in: this briefly changes the strip.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { requestHttp } from '../shared/protocol/src/index.js';
const address = process.env.DEVICE_ADDRESS;
if (!address) throw new Error('Set DEVICE_ADDRESS to the test strip');
const presets: { name: string; source: string; isGradient: boolean }[] = JSON.parse(readFileSync('.sdk/ios-presets.json', 'utf8'));
let id = 1;
const current = (await requestHttp(address, { id: id++, operation: 0 })).state!;
const initial = process.env.RESTORE_STATE_FILE ? JSON.parse(readFileSync(process.env.RESTORE_STATE_FILE, 'utf8')) : current;
assert.equal(current.deviceId, initial.deviceId);
assert.deepEqual(current.config, initial.config);
assert.ok(current.build >= 5);
let scriptId: string | undefined;
try {
  await requestHttp(address, { id: id++, operation: 2, brightness: 16 });
  for (const preset of presets) {
    const saved = await requestHttp(address, { id: id++, operation: scriptId ? 8 : 7, script: { id: scriptId ?? '', name: 'Temporary iOS preset test', source: preset.source, mode: preset.isGradient ? 1 : 2 } });
    scriptId = saved.script!.id;
    await requestHttp(address, { id: id++, operation: 10, scriptId });
    await new Promise(resolve => setTimeout(resolve, 1200));
    assert.equal((await requestHttp(address, { id: id++, operation: 0 })).state!.activeScriptId, scriptId, `${preset.name} must keep running on firmware`);
    const dimmed = await requestHttp(address, { id: id++, operation: 2, brightness: 8 });
    assert.equal(dimmed.state!.activeScriptId, scriptId);
    assert.equal(dimmed.state!.mode, preset.isGradient ? 1 : 2);
    const stopped = await requestHttp(address, { id: id++, operation: 11 });
    assert.equal(stopped.state!.activeScriptId, '');
    await requestHttp(address, { id: id++, operation: 2, brightness: 16 });
    console.log(`PASS: ${preset.name} starts, survives Lua frames and brightness changes, and stops on 60-controller WS2805`);
  }
  await requestHttp(address, { id: id++, operation: 15, on: false });
  await new Promise(resolve => setTimeout(resolve, 600));
  assert.equal((await requestHttp(address, { id: id++, operation: 0 })).state!.on, false);
} finally {
  if (scriptId) await requestHttp(address, { id: id++, operation: 9, scriptId });
  await requestHttp(address, { id: id++, operation: 1, color: initial.color });
  await requestHttp(address, { id: id++, operation: 2, brightness: initial.brightness });
  if (initial.activeScriptId) await requestHttp(address, { id: id++, operation: 10, scriptId: initial.activeScriptId });
  await requestHttp(address, { id: id++, operation: 15, on: initial.on });
  console.log('Restored the original color, brightness, and animation.');
}
