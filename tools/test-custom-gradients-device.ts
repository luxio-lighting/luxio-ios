import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { requestHttp } from '../shared/protocol/src/index.js';
const address = process.env.DEVICE_ADDRESS;
if (!address) throw new Error('Set DEVICE_ADDRESS to opt into this physical test');
const fixtures: { name: string; strip: string; source: string }[] = JSON.parse(readFileSync('.sdk/custom-gradients.json', 'utf8'));
let id = 1, scriptId: string | undefined;
const initial = (await requestHttp(address, { id: id++, operation: 0 })).state!;
try {
  await requestHttp(address, { id: id++, operation: 2, brightness: 16 });
  for (const fixture of fixtures.filter(f => f.strip === initial.config.stripType)) {
    const saved = await requestHttp(address, { id: id++, operation: scriptId ? 8 : 7, script: { id: scriptId ?? '', name: 'Temporary custom gradient test', source: fixture.source, mode: 1 } });
    const previousId = scriptId; scriptId = saved.script!.id;
    if (previousId) assert.equal(scriptId, previousId, 'Editing must reuse one saved script');
    await requestHttp(address, { id: id++, operation: 10, scriptId });
    await new Promise(resolve => setTimeout(resolve, 800));
    assert.equal((await requestHttp(address, { id: id++, operation: 0 })).state!.activeScriptId, scriptId);
    const recovered = await requestHttp(address, { id: id++, operation: 6, scriptId });
    assert.equal(recovered.script!.source, fixture.source, 'Editable point metadata must survive storage');
    console.log(`PASS: ${fixture.name} gradient uploaded, ran, and restored with editable metadata`);
  }
  const solid = await requestHttp(address, { id: id++, operation: 1, color: { red: 255, green: 0, blue: 0, white: 0, warmWhite: 0, coolWhite: 0 } });
  assert.equal(solid.state!.activeScriptId, '', 'Returning to one point must stop the gradient');
} finally {
  if (scriptId) await requestHttp(address, { id: id++, operation: 9, scriptId });
  await requestHttp(address, { id: id++, operation: 1, color: initial.color });
  await requestHttp(address, { id: id++, operation: 2, brightness: initial.brightness });
  if (initial.activeScriptId) await requestHttp(address, { id: id++, operation: 10, scriptId: initial.activeScriptId });
  console.log('Original strip state restored.');
}
