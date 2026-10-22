import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { Animation } from '../shared/device/src/lua.js';
mkdirSync('.sdk/swift-module-cache', { recursive: true });
execFileSync('swiftc', ['-module-cache-path', '.sdk/swift-module-cache', 'Luxio/Presets.swift', 'tools/export-ios-presets.swift', '-o', '.sdk/export-ios-presets'], { stdio: 'inherit' });
const presets: { name: string; colors: number[][]; isGradient: boolean; source: string }[] = JSON.parse(execFileSync('.sdk/export-ios-presets', { encoding: 'utf8' }));
writeFileSync('.sdk/ios-presets.json', JSON.stringify(presets));
for (const preset of presets) {
  for (const count of [1, 60, 1024]) {
    for (const strip of ['WS2805', 'WS2814', 'WS2812']) {
      const animation = new Animation(preset.source, count, strip);
      const first = structuredClone(animation.tick(0));
      const later = structuredClone(animation.tick(5000));
      for (const pixel of later) {
        assert.equal(pixel.white + pixel.warmWhite + pixel.coolWhite, 0, 'RGB presets must not mix white channels');
        for (const value of Object.values(pixel)) assert.ok(Number.isInteger(value) && value >= 0 && value <= 255);
      }
      if (preset.isGradient) {
        assert.deepEqual(first, later, `${preset.name} must remain stationary`);
        assert.deepEqual(Object.values(first[0]).slice(0, 3), preset.colors[0]);
        if (count > 1) assert.deepEqual(Object.values(first.at(-1)!).slice(0, 3), preset.colors.at(-1));
      } else if (preset.name === 'Rainbow') {
        assert.notDeepEqual(first, later, 'Rainbow must move');
        if (count > 1) assert.ok(new Set(first.map(p => JSON.stringify(p))).size >= Math.min(6, count), 'Rainbow must span different hues');
      } else if (preset.name === 'Colorloop') {
        assert.ok(first.every(p => JSON.stringify(p) === JSON.stringify(first[0])), 'Colorloop must be uniform');
        assert.ok(later.every(p => JSON.stringify(p) === JSON.stringify(later[0])));
        assert.notDeepEqual(first, later, 'Colorloop must cycle hues');
      }
      animation.close();
    }
  }
  console.log(`PASS: ${preset.name}, 1/60/1024 pixels, all strip types`);
}
