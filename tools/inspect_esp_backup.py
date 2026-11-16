#!/usr/bin/env python3
"""Inspect an ESP full-flash backup without printing NVS, keys or arbitrary strings.

Finds aligned ESP-IDF partition tables, validates their MD5 record, and reports
app descriptors. This tool never opens a serial device or writes firmware.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def text(data):
    return data.split(b"\0", 1)[0].decode("utf-8", "replace")


def inspect(data):
    tables = []
    for start in range(0, len(data) - 0x1000 + 1, 0x1000):
        if data[start:start + 2] != b"\xaa\x50":
            continue
        entries = []
        valid_digest = False
        for index in range(96):
            pos = start + index * 32
            record = data[pos:pos + 32]
            if len(record) != 32:
                break
            if record[:2] == b"\xeb\xeb":
                valid_digest = hashlib.md5(data[start:pos]).digest() == record[16:32]
                break
            magic, kind, subtype, offset, size, label, flags = struct.unpack("<HBBII16sI", record)
            if magic != 0x50AA or size == 0 or offset + size > len(data):
                break
            entry = {"label": text(label), "type": kind, "subtype": subtype,
                     "offset": hex(offset), "size": size, "flags": flags}
            # esp_app_desc_t follows the image header and first segment header.
            desc = data[offset + 32:offset + 288]
            if kind == 0 and data[offset] == 0xE9 and len(desc) == 256 and desc[:4] == b"\x32\x54\xcd\xab":
                entry["app"] = {"version": text(desc[16:48]), "project": text(desc[48:80]),
                                "build_time": text(desc[80:96]), "build_date": text(desc[96:112]),
                                "idf": text(desc[112:144]), "elf_sha256": desc[144:176].hex()}
            entries.append(entry)
        if entries and valid_digest:
            tables.append({"offset": hex(start), "md5_valid": True, "partitions": entries})
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "partition_tables": tables}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backup", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("output exists")
    result = inspect(args.backup.read_bytes())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
