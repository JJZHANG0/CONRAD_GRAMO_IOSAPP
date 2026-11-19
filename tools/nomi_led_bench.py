#!/usr/bin/env python3
"""Send one documented Nomi LED command; opening USB can reset the board.
No other GPIO probes, Flash writes, credentials or synthetic bite events.
Requires pyserial==3.5. Stop BLE testing before using this bench command.
"""
import argparse, json, time, uuid
from pathlib import Path
import serial
from serial.tools import list_ports

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port',required=True)
    p.add_argument('--color',choices=['green','red','off'],required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    assert not a.output.exists(), 'Use a fresh evidence file'
    assert any(x.device==a.port and (x.vid,x.pid)==(0x303a,0x1001) for x in list_ports.comports()), 'Unexpected USB device'
    port=serial.Serial(None,115200,timeout=.2);port.dtr=False;port.rts=False;port.port=a.port
    port.open(); info=None; driver=[]; deadline=time.monotonic()+6
    try:
        while time.monotonic()<deadline:
            line=port.readline().decode('utf8','replace').strip()
            if line.startswith('[led]'):driver.append(line)
            try:v=json.loads(line)
            except ValueError:continue
            if v.get('v')==1 and v.get('protocol')=='nomi1' and v.get('fw') in ['0.4.0-integration','0.4.1-integration','0.4.2-integration','0.4.3-integration']:info=v;break
        assert info is not None, 'Verified Nomi capabilities not received; no command sent'
        assert info.get('led') is True, 'Device reports LED unavailable; no command sent'
        command={'v':1,'id':str(uuid.uuid4()),'op':'led','color':a.color}
        port.write((json.dumps(command,separators=(',',':'))+'\n').encode());port.flush()
        deadline=time.monotonic()+8;reply=None
        while time.monotonic()<deadline:
            line=port.readline().decode('utf8','replace').strip()
            try:v=json.loads(line)
            except ValueError:continue
            if v.get('id')==command['id']:reply=v;break
        evidence={'time':time.time(),'firmware':info['fw'],'driver_boot':driver,'command':command,'reply':reply,'optical_verified':False}
        a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(evidence,indent=2));print(json.dumps(evidence,indent=2))
        assert reply and reply.get('v')==1 and reply.get('type')=='led' and reply.get('color')==a.color and reply.get('applied') is True, 'No matching successful application ACK'
    finally:port.close()
if __name__=='__main__':main()
