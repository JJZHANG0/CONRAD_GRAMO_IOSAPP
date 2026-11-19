#!/usr/bin/env python3
"""Known NOMI01 JPEG benchmark (Mac BLE, not iPhone screen latency).
Use an isolated Python environment with bleak==0.22.3. Disconnect phone first.
Only reads capabilities and uses documented hello/capture/ping commands.
Never arms a meal, generates bites, writes flash or changes LED state.
"""
import argparse, asyncio, json, time, uuid, zlib
from pathlib import Path
from bleak import BleakClient, BleakScanner
BASE='-5b4a-4e3f-8d2c-1a0b9e8d7c6b'
SERVICE='6c2e0001'+BASE
CONTROL='6c2e0005'+BASE
INFO='6c2e0006'+BASE
IMAGE='6c2e0007'+BASE
async def run(args):
    assert not args.output.exists(), 'Choose a fresh output path'
    device=await BleakScanner.find_device_by_filter(lambda d,a: a.local_name=='NOMI01' and SERVICE in [s.lower() for s in a.service_uuids], timeout=15)
    if not device: raise RuntimeError('Verified NOMI01 advertisement not found')
    async with BleakClient(device) as client:
        info=json.loads(await client.read_gatt_char(INFO))
        assert info.get('v')==1 and info.get('protocol')=='nomi1' and info.get('device')=='50F7FAC13DE8'
        assert info.get('fw') in ('0.4.2-integration','0.4.3-integration') and info.get('camera') is True
        assert not args.preview or info['fw']=='0.4.3-integration'
        replies={}; current={}; results=[]; last_received=None
        def control(_,raw):
            try: value=json.loads(raw)
            except ValueError:return
            if value.get('v')!=1:return
            pending=replies.get(value.get('id'))
            if pending and not pending.done(): pending.set_result(value)
            if value.get('id')==current.get('id') and value.get('type')=='frame':
                size=value.get('size',0)
                if not 4<size<=200000:return
                current.update(meta=value, buffer=bytearray(size), present=bytearray(size), count=0, packets=0, packet_max=0)
        def image(_,raw):
            if len(raw)<=14 or raw[:2]!=b'\x01\x20' or 'meta' not in current:return
            frame=int.from_bytes(raw[2:6],'little'); offset=int.from_bytes(raw[6:10],'little'); total=int.from_bytes(raw[10:14],'little')
            if frame!=current['meta']['frame']:return
            data=raw[14:]
            if total!=len(current['buffer']) or offset+len(data)>total:return
            current['packets']+=1;current['packet_max']=max(current['packet_max'],len(raw))
            for i,b in enumerate(data,offset):
                if current['present'][i] and current['buffer'][i]!=b:
                    if not current['done'].done():current['done'].set_exception(ValueError('Conflicting repeated bytes'))
                    return
                if not current['present'][i]:current['buffer'][i]=b;current['present'][i]=1;current['count']+=1
            if current['count']==total and not current['done'].done():
                jpeg=bytes(current['buffer'])
                if zlib.crc32(jpeg)!=current['meta']['crc'] or not jpeg.startswith(b'\xff\xd8') or not jpeg.endswith(b'\xff\xd9'):
                    current['done'].set_exception(ValueError('JPEG/CRC invalid'))
                else:current['done'].set_result(jpeg)
        async def command(op, **extra):
            ident=str(uuid.uuid4()); future=asyncio.get_running_loop().create_future(); replies[ident]=future
            await client.write_gatt_char(CONTROL,json.dumps(dict(v=1,id=ident,op=op,**extra),separators=(',',':')).encode(),response=True)
            try:return await asyncio.wait_for(future,5)
            finally:replies.pop(ident,None)
        await client.start_notify(CONTROL,control);await client.start_notify(IMAGE,image)
        hello=await command('hello'); assert hello.get('fw')==info['fw'] and hello.get('type')=='hello'
        for index in range(args.frames):
            current.clear();current.update(id=str(uuid.uuid4()),done=asyncio.get_running_loop().create_future())
            start=time.perf_counter()
            msg=dict(v=1,id=current['id'],op='capture')
            if args.preview:msg['preview']=True
            await client.write_gatt_char(CONTROL,json.dumps(msg,separators=(',',':')).encode(),response=True)
            await asyncio.sleep(.05); ping_start=time.perf_counter(); ping=await command('ping'); ping_ms=(time.perf_counter()-ping_start)*1000
            assert ping.get('type')=='hello'
            jpeg=await asyncio.wait_for(current['done'],30)
            received=time.perf_counter()
            row=dict(index=index,bytes=len(jpeg),request_ms=(received-start)*1000,interval_ms=(received-last_received)*1000 if last_received else None,
                     ping_ms=ping_ms,packet_max=current['packet_max'],packets=current['packets'],width=current['meta']['w'],height=current['meta']['h'],sensor_age_ms=current['meta'].get('age_ms'))
            results.append(row);last_received=received;print(json.dumps(row),flush=True)
            args.output.parent.mkdir(parents=True,exist_ok=True)
            args.output.write_text(json.dumps(dict(client='macOS Bleak; not iPhone display latency',info=info,preview=args.preview,frames=results),indent=2))
            args.output.with_suffix('.jpg').write_bytes(jpeg)
            await asyncio.sleep(.1 if args.preview else max(0,2-(time.perf_counter()-start)))
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--frames',type=int,default=8);parser.add_argument('--preview',action='store_true')
    args=parser.parse_args();assert 1<=args.frames<=30
    asyncio.run(run(args))
