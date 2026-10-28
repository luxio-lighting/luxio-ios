import { createServer } from 'node:http';
import { Device } from '../../shared/device/src/device.js';
import { colorSchema, decodeRequest, encodeResponse } from '../../shared/protocol/src/index.js';
const devices = new Map<string, Device>();
for (const [i,name,palette,brightness,on] of [
 [0,'Living Room',['ff5c79','ffb56b'],190,true],
 [1,'Bedroom',['733cff','c45fff'],100,true],
 [2,'Kitchen',['ffe4a2','ffca69'],225,true],
 [3,'Studio',['00d2ff','4fff7f'],150,true],
 [4,'Hallway',['00d2ff','00d2ff'],100,false],
] as const) {
 const d = new Device('marketing-'+i); d.state.config.name=name;d.state.config.gpio=16;d.state.config.ledCount=60;d.state.build=34;d.state.lanIp='192.168.1.'+(40+i);
 d.handle({id:1,operation:17,gradient:{id:'',name:'',colors:palette.map(hex=>colorSchema.parse({red:parseInt(hex.slice(0,2),16),green:parseInt(hex.slice(2,4),16),blue:parseInt(hex.slice(4),16)}))}});
 d.state.brightness=brightness;d.state.on=on;devices.set('/'+i+'/api',d);
}
createServer(async(req,res)=>{
 const d=devices.get(req.url??'');if(!d){res.writeHead(404);res.end();return;}
 const chunks=[];for await(const chunk of req)chunks.push(chunk);
 const input=decodeRequest(Buffer.concat(chunks));
 const result=d.handle({...input,operation:input.operation===12?0:input.operation});
 result.networkStatus={connected:true,ssid:'Luxio Home',gateway:'192.168.1.1',dns:['1.1.1.1','8.8.8.8'],rssi:-42,channel:6};
 if(input.operation===12){result.pairingCode='34970112332';result.pairingQr='MT:MARKETING-DEMO-NOT-A-REAL-DEVICE';result.error='';}
 res.setHeader('Content-Type','application/x-protobuf');res.end(encodeResponse(result));
}).listen(8093,'127.0.0.1',()=>console.log('Marketing fixture on 8093'));
