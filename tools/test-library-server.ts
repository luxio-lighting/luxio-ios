// Local-only UI fixture. Does not connect to a physical light.
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { decodeRequest, encodeResponse, colorSchema, type Script, type State } from '../shared/protocol/src/index.js';
const scripts: Script[] = Array.from({ length: 130 }, (_, i) => ({ id: randomUUID(), name: `Ocean ${i + 1}`, mode: 1, source: 'function setup() end function loop() end' }));
const state: State = { deviceId: 'ui-fixture', build: 11, config: { name: 'Library test', stripType: 'WS2805', ledCount: 60, gpio: 16, channel: 100 }, brightness: 16, on: true, color: colorSchema.parse({ blue: 255 }), activeScriptId: '', lanIp: '127.0.0.1', mode: 1 };
createServer(async (request, response) => {
  const chunks: Buffer[] = []; for await (const chunk of request) chunks.push(Buffer.from(chunk));
  const message = decodeRequest(Buffer.concat(chunks));
  let result: any = { id: message.id, state };
  switch (message.operation) {
    case 15: state.on = message.on ?? false; break;
    case 2: state.brightness = message.brightness!; break;
    case 5: {
      const offset = message.scriptOffset ?? 0;
      result.scripts = scripts.slice(offset, offset + 64).map(script => ({ ...script, source: '' }));
      result.nextScriptOffset = offset + 64 < scripts.length ? offset + 64 : 0; break;
    }
    case 6: result.script = scripts.find(script => script.id === message.scriptId); break;
    case 7: {
      const script = { ...message.script!, id: randomUUID() }; scripts.push(script); result.script = script; break;
    }
    case 8: {
      const index = scripts.findIndex(script => script.id === message.script!.id);
      scripts[index] = message.script!; result.script = message.script; break;
    }
    case 9: {
      const index = scripts.findIndex(script => script.id === message.scriptId); if (index >= 0) scripts.splice(index, 1);
      if (state.activeScriptId === message.scriptId) { state.activeScriptId = ''; state.mode = 0; }
      break;
    }
    case 10: state.activeScriptId = message.scriptId!; state.mode = scripts.find(script => script.id === message.scriptId)!.mode; break;
    case 11: state.activeScriptId = ''; state.mode = 0; break;
    case 1: state.color = message.color!; state.activeScriptId = ''; state.mode = 0; break;
    case 2: state.brightness = message.brightness!; break;
  }
  response.setHeader('Content-Type', 'application/x-protobuf'); response.end(encodeResponse(result));
}).listen(8082, '127.0.0.1', () => console.log('Library UI fixture: 127.0.0.1:8082'));
