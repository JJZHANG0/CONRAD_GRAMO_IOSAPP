#!/usr/bin/env python3
"""Read known NOMI01 button diagnostics, without generating bites or arming meals.
Opening USB may reset the board: start this BEFORE connecting the App. Keep it
open while pressing the physical button. No firmware or NVS writes by this tool.
"""
import argparse, json, time, uuid
from pathlib import Path
import serial
from serial.tools import list_ports

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--port', required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--seconds', type=int, default=180)
a = p.parse_args()
assert 1 <= a.seconds <= 900
assert not a.output.exists(), 'Choose a new evidence file'
assert any(x.device == a.port and (x.vid,x.pid) == (0x303a,0x1001) for x in list_ports.comports())
a.output.parent.mkdir(parents=True, exist_ok=True)
port = serial.Serial(None, 115200, timeout=.1)
port.dtr = False; port.rts = False; port.port = a.port
with a.output.open('x') as log:
    a.output.chmod(0o600)
    try:
        port.open(); end = time.monotonic() + a.seconds; verified = False; next_status = 0
        while time.monotonic() < end:
            line = port.readline().decode('utf8','replace').strip()
            if line:
                log.write(json.dumps({'received':time.time(),'line':line}) + '\n'); log.flush()
                try: data = json.loads(line)
                except ValueError: data = {}
                if data.get('fw') == '0.4.2-integration' and data.get('protocol') == 'nomi1': verified = True
                if data.get('type') == 'button_status' or line.startswith('[button]'): print(line, flush=True)
            if verified and time.monotonic() >= next_status:
                msg = {'v':1,'id':str(uuid.uuid4()),'op':'button_status'}
                port.write((json.dumps(msg,separators=(',',':'))+'\n').encode())
                next_status = time.monotonic() + 10
    finally:
        port.close()
