import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { Animation } from '../shared/device/src/lua.js';
mkdirSync('.sdk/swift-module-cache', { recursive: true });
execFileSync('swiftc', ['-module-cache-path', '.sdk/swift-module-cache', 'Luxio/Gradient.swift', 'tools/test-gradient.swift', '-o', '.sdk/test-gradient'], { stdio: 'inherit' });
const fixtures: { name: string; strip: string; source: string; stops: number[][] }[] = JSON.parse(execFileSync('.sdk/test-gradient', { encoding: 'utf8' }));
writeFileSync('.sdk/custom-gradients.json', JSON.stringify(fixtures));
console.log('PASS: wheel coordinates, RGB round-trip, white channels, metadata round-trip and invalid metadata rejection');
for (const fixture of fixtures) {
  for (const count of [1, 60, 1024]) {
    const animation = new Animation(fixture.source, count, fixture.strip);
    const pixels = structuredClone(animation.pixels);
    for (let i = 0; i < count; i++) {
      const position = i / Math.max(count - 1, 1) * (fixture.stops.length - 1);
      const segment = Math.max(0, Math.min(Math.floor(position), fixture.stops.length - 2));
      const t = position - segment;
      const a = fixture.stops[segment], b = fixture.stops[Math.min(segment + 1, fixture.stops.length - 1)];
      const expected = a.map((value, c) => Math.floor(value + (b[c] - value) * t + 0.5));
      assert.deepEqual(Object.values(pixels[i]), expected, `${fixture.name} ${fixture.strip} pixel ${i}`);
    }
    assert.deepEqual(animation.tick(5000), pixels, 'Custom gradient must remain stationary');
    animation.close();
  }
  console.log(`PASS: ${fixture.name}, ${fixture.strip}, 1/60/1024 pixels`);
}
