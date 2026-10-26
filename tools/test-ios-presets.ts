import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { Device } from '../shared/device/src/device.js';
import { colorSchema } from '../shared/protocol/src/index.js';
import { parseParameters } from '../shared/protocol/src/parameters.js';
import { parsePreview } from '../shared/protocol/src/preview.js';
import { Animation } from '../shared/device/src/lua.js';
mkdirSync('.sdk/swift-module-cache', { recursive: true });
execFileSync('swiftc', ['-module-cache-path', '.sdk/swift-module-cache', 'Luxio/Presets.swift', 'tools/export-ios-presets.swift', '-o', '.sdk/export-ios-presets'], { stdio: 'inherit' });
const presets: { name: string; colors: number[][]; previewColors: number[][]; isGradient: boolean; source: string }[] = JSON.parse(execFileSync('.sdk/export-ios-presets', { encoding: 'utf8' }));
writeFileSync('.sdk/ios-presets.json', JSON.stringify(presets));
for (const preset of presets) {
  if (!preset.isGradient) {
    assert.deepEqual(parsePreview(preset.source).map(c => [c.red,c.green,c.blue]), preset.previewColors);
    const automatic = ['Christmas', 'Knight Rider', 'Fireplace', 'Candle', 'Cyberpunk'].includes(preset.name);
    assert.deepEqual(parseParameters(preset.source).map(p => [p.boolean, p.numberInput]), automatic ? [] : [[false, false], [false, true], [true, false]]);
    for (const parameter of parseParameters(preset.source)) {
      const animation = new Animation(preset.source, 60, 'WS2812');
      const before = structuredClone(animation.tick(1000));
      animation.update([{ ...parameter, value: parameter.boolean ? 1 - parameter.value : parameter.minimum }]);
      assert.notDeepEqual(animation.tick(0), before, `${preset.name}: ${parameter.name} must affect output`);
      animation.close();
    }
  }
  for (const count of [1, 60, 1024]) {
    for (const strip of ['WS2805', 'WS2814', 'WS2812', 'SK6812']) {
      const device = new Device('preset'); device.state.config.ledCount = count; device.state.config.stripType = strip as 'WS2805'; device.state.brightness = 256;
      let animation: Animation | undefined;
      if (preset.isGradient) {
        assert.equal(preset.source, '');
        const colors = preset.colors.map(c => colorSchema.parse({ red: c[0], green: c[1], blue: c[2] }));
        assert.equal(device.handle({ id: 1, operation: 17, gradient: { id: '', name: '', colors } }).error, undefined);
      } else animation = new Animation(preset.source, count, strip);
      const first = structuredClone(animation?.tick(0) ?? device.output());
      const later = structuredClone(animation?.tick(5000) ?? device.output());
      for (const pixel of later) {
        if (preset.name === 'Candle' && strip === 'WS2805') {
          assert.ok(pixel.warmWhite > 0, 'Candle must use warm white on RGBCCT');
          assert.equal(pixel.red + pixel.green + pixel.blue + pixel.white + pixel.coolWhite, 0);
        } else if (preset.name === 'Candle' && ['WS2814', 'SK6812'].includes(strip)) {
          assert.ok(pixel.white > 0 && pixel.red > pixel.green && pixel.green > 0, 'RGBW candle must mix dedicated white with an amber tint');
          assert.equal(pixel.blue + pixel.warmWhite + pixel.coolWhite, 0);
        } else assert.equal(pixel.white + pixel.warmWhite + pixel.coolWhite, 0, 'RGB presets must not mix white channels');
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
      } else if (['Christmas', 'Knight Rider', 'Fireplace', 'Candle', 'Cyberpunk'].includes(preset.name)) {
        const frames = new Set([JSON.stringify(first), JSON.stringify(later)]);
        for (let frame = 0; frame < 30; frame++) {
          const pixels = animation!.tick(173);
          frames.add(JSON.stringify(pixels));
          for (const p of pixels) {
            assert.ok(Object.values(p).every(v => Number.isInteger(v) && v >= 0 && v <= 255));
            if (preset.name === 'Knight Rider') assert.equal(p.green + p.blue, 0);
            if (['Christmas', 'Fireplace'].includes(preset.name) || (preset.name === 'Candle' && strip !== 'WS2805')) assert.ok(p.red > p.green && p.green >= p.blue);
            if (preset.name === 'Candle' && strip === 'WS2805') assert.ok(p.warmWhite > 0 && p.coolWhite === 0 && p.red + p.green + p.blue + p.white === 0);
            if (preset.name === 'Candle' && ['WS2814', 'SK6812'].includes(strip)) assert.ok(p.white > 0 && p.warmWhite + p.coolWhite === 0);
          }
          if (preset.name === 'Christmas' && count > 1) assert.ok(new Set(pixels.map(p => p.red)).size > 1, 'Twinkles must vary independently across the strip');
          if (preset.name === 'Candle') {
            const intensity = pixels.map(p => p.red + p.white + p.warmWhite);
            assert.ok(Math.max(...intensity) - Math.min(...intensity) <= 12, 'A candle should flicker gently as one flame');
          }
        }
        assert.ok(frames.size > 1, `${preset.name} must animate, even with one pixel`);
      }
      animation?.close();
    }
  }
  console.log(`PASS: ${preset.name}, 1/60/1024 pixels, all strip types`);
}


const reference = JSON.parse(readFileSync(new URL('./fixtures/animation-presets-reference.json', import.meta.url), 'utf8'));
for (const preset of presets.filter(p => !p.isGradient)) {
  assert.ok(!/(?:if|and) luxio_(?:fill|render_waves)|luxio_get_color_type and/.test(preset.source), 'Current presets must require the new API directly');
  const original = reference.find((p: {name: string}) => p.name === preset.name).source;
  for (const count of [1, 100, 1024]) for (const strip of ['WS2812','WS2814','WS2805','SK6812']) {
    const current = new Animation(preset.source, count, strip);
    const expected = new Animation(original, count, strip);
    for (const milliseconds of [0, 33, 1000, 10000]) {
      const a = current.tick(milliseconds), b = expected.tick(milliseconds);
      for (let i=0;i<count;i++) for (const c of ['red','green','blue','white','warmWhite','coolWhite'] as const)
        assert.equal(a[i][c],b[i][c], `${preset.name}: removing compatibility changed output`);
    }
    current.close(); expected.close();
  }
}
console.log('PASS: current presets match the measured optimized paths on all strip types');
