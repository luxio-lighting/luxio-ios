import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { Device } from '../shared/device/src/device.js';
import { root } from '../shared/protocol/src/index.js';
mkdirSync('.sdk/swift-module-cache', { recursive: true });
execFileSync('swiftc', ['-module-cache-path', '.sdk/swift-module-cache', 'Luxio/Protocol.swift', 'Luxio/SimulatorDevice.swift', 'Luxio/Gradient.swift', 'tools/test-gradient.swift', '-o', '.sdk/test-gradient'], { stdio: 'inherit' });
const fixtures: { name: string; strip: string; bytes: string; stops: number[][] }[] = JSON.parse(execFileSync('.sdk/test-gradient', { encoding: 'utf8' }));
writeFileSync('.sdk/custom-gradients.json', JSON.stringify(fixtures));
console.log('PASS: wheel coordinates, RGB round-trip, white channels, metadata round-trip and invalid metadata rejection');
for (const fixture of fixtures) {
  for (const count of [1, 60, 1024]) {
    const device = new Device('swift-gradient'); device.state.config.ledCount = count; device.state.config.stripType = fixture.strip as 'WS2805'; device.state.brightness = 256;
    const type = root.lookupType('luxio.Gradient');
    const gradient = type.toObject(type.decode(Buffer.from(fixture.bytes, 'base64')), { defaults: true }) as any;
    const result = device.handle({ id: 1, operation: 17, gradient }); assert.equal(result.error, undefined);
    const pixels = device.output(); assert.equal(device.animation, undefined); assert.equal(device.gradients.length, 0);
    for (let i = 0; i < count; i++) {
      const position = i / Math.max(count - 1, 1) * (fixture.stops.length - 1);
      const segment = Math.max(0, Math.min(Math.floor(position), fixture.stops.length - 2));
      const t = position - segment;
      const a = fixture.stops[segment], b = fixture.stops[Math.min(segment + 1, fixture.stops.length - 1)];
      const expected = a.map((value, c) => Math.floor(value + (b[c] - value) * t + 0.5));
      assert.deepEqual(Object.values(pixels[i]), expected, `${fixture.name} ${fixture.strip} pixel ${i}`);
    }
    assert.deepEqual(device.output(), pixels, 'Custom gradient must remain stationary');

  }
  console.log(`PASS: ${fixture.name}, ${fixture.strip}, 1/60/1024 pixels`);
}
