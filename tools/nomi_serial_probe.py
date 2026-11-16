#!/usr/bin/env python3
"""Capture the observed Nomi v0.2 console. No flash writes, credentials or cloud commands.

Install pyserial==3.5 in an isolated environment. USB opening can reset this board;
do not run concurrently with esptool, another monitor, or an active meal.
Raw captures are private local artifacts and may contain saved network names.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time

import serial
from serial.tools import list_ports


COMMANDS = {"listen": None, "camera-status": b"c\n", "camera-frame": b"C\n", "network-status": b"/net\n"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--command", choices=COMMANDS, default="listen")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seconds", type=float, default=20)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 60:
        parser.error("seconds must be between 1 and 60")
    ports = [p for p in list_ports.comports() if p.device == args.port]
    if len(ports) != 1 or (ports[0].vid, ports[0].pid) != (0x303A, 0x1001):
        parser.error("port does not match the observed Espressif USB VID/PID")
    if args.output.exists():
        parser.error("output already exists; choose a new evidence path")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    capture = bytearray()
    port = serial.Serial(port=None, baudrate=115200, timeout=0.1)
    port.dtr = False
    port.rts = False
    port.port = args.port
    try:
        port.open()
        # Preserve startup output; never transmit undocumented probing bytes.
        until = time.monotonic() + 3
        while time.monotonic() < until:
            capture.extend(port.read(4096))
        if COMMANDS[args.command] is not None:
            port.write(COMMANDS[args.command])
            port.flush()
        until = time.monotonic() + args.seconds
        while time.monotonic() < until:
            capture.extend(port.read(4096))
            if len(capture) > 8 * 1024 * 1024:
                raise RuntimeError("capture exceeded 8 MiB safety bound")
    finally:
        port.close()
        with args.output.open("xb") as f:
            args.output.chmod(0o600)
            f.write(capture)
    print(json.dumps({"command": args.command, "bytes": len(capture),
                      "sha256": hashlib.sha256(capture).hexdigest(),
                      "raw_capture": str(args.output.resolve()),
                      "firmware_written": False}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
