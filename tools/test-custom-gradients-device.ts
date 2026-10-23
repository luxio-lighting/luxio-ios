import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { root, requestHttp, type Gradient } from '../shared/protocol/src/index.js';
const address = process.env.DEVICE_ADDRESS;
if (!address) throw new Error('Set DEVICE_ADDRESS to opt into this physical test');
const fixtures: { name: string; strip: string; bytes: string }[] = JSON.parse(readFileSync('.sdk/custom-gradients.json', 'utf8'));
let id = 1, gradientId: string | undefined;
const initial = (await requestHttp(address, { id: id++, operation: 0 })).state!;
try {
  await requestHttp(address, { id: id++, operation: 2, brightness: 16 });
  for (const fixture of fixtures.filter(f => f.strip === initial.config.stripType)) {
    const type = root.lookupType('luxio.Gradient');
    const gradient = type.toObject(type.decode(Buffer.from(fixture.bytes, 'base64')), { defaults: true }) as Gradient;
    const saved = await requestHttp(address, { id: id++, operation: gradientId ? 21 : 20, gradient: { ...gradient, id: gradientId ?? '', name: 'Temporary gradient test' } });
    const previousId = gradientId; gradientId = saved.gradient!.id;
    if (previousId) assert.equal(gradientId, previousId);
    await requestHttp(address, { id: id++, operation: 23, gradientId });
    await new Promise(resolve => setTimeout(resolve, 600));
    assert.equal((await requestHttp(address, { id: id++, operation: 0 })).state!.activeGradientId, gradientId);
    const recovered: Gradient = (await requestHttp(address, { id: id++, operation: 19, gradientId })).gradient!;
    assert.deepEqual(recovered.colors, gradient.colors); assert.equal(recovered.editorMetadata, gradient.editorMetadata);
    console.log(`PASS: ${fixture.name} saved and restored as native gradient data`);
  }
  const solid = await requestHttp(address, { id: id++, operation: 1, color: { red: 255, green: 0, blue: 0, white: 0, warmWhite: 0, coolWhite: 0 } });
  assert.equal(solid.state!.activeScriptId, '', 'Returning to one point must stop the gradient');
} finally {
  if (gradientId) await requestHttp(address, { id: id++, operation: 22, gradientId });
  await requestHttp(address, { id: id++, operation: 1, color: initial.color });
  await requestHttp(address, { id: id++, operation: 2, brightness: initial.brightness });
  if (initial.mode === 1 && initial.gradient) await requestHttp(address, { id: id++, operation: initial.activeGradientId ? 23 : 17, gradientId: initial.activeGradientId, gradient: initial.gradient });
  if (initial.activeColorId) await requestHttp(address, { id: id++, operation: 30, colorId: initial.activeColorId });
  if (initial.activeScriptId) await requestHttp(address, { id: id++, operation: 10, scriptId: initial.activeScriptId });
  await requestHttp(address, { id: id++, operation: 15, on: initial.on });
  console.log('Original strip state restored.');
}
