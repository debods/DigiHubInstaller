#!/usr/bin/env python3

"""
gpstest.py
Test for installed and working GPS device

Version 1.0a

Steve de Bode - KQ4ZCI - December 2025

Input:	None (GPS Device)
Output: GPS port,GPS status

Exit codes:
  0 = working
  1 = nofix
  2 = nodata
  3 = nogps
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys
import time
from dataclasses import dataclass
from typing import Optional, Tuple

import serial
from serial.tools import list_ports

NMEA_RE = re.compile(r"^\$(?P<body>[^*]+)\*(?P<ck>[0-9A-Fa-f]{2})\s*$")

def nmea_checksum_ok(sentence: str) -> bool:
    m = NMEA_RE.match(sentence.strip())
    if not m:
        return False
    body = m.group("body")
    given = int(m.group("ck"), 16)
    calc = 0
    for ch in body:
        calc ^= ord(ch)
    return calc == given

def parse_fix(sentence: str) -> Optional[bool]:
    """
    Returns:
      True  = fix confirmed
      False = explicitly no-fix
      None  = unknown/not enough info
    """
    s = sentence.strip()
    if not s.startswith("$"):
        return None

    core = s[1:]
    if "*" in core:
        core = core.split("*", 1)[0]

    parts = core.split(",")
    if not parts or len(parts[0]) < 5:
        return None

    msg_type = parts[0][-3:]  # RMC, GGA, etc.

    if msg_type == "RMC" and len(parts) > 2:
        status = parts[2].strip().upper()
        if status == "A":
            return True
        if status == "V":
            return False
        return None

    if msg_type == "GGA" and len(parts) > 6:
        q = parts[6].strip()
        if q.isdigit():
            return int(q) > 0
        return None

    return None

def linux_ports() -> list[str]:
    """
    Linux-only realistic GPS-USB candidates.
    Uses pyserial enumeration + glob fallback; de-dupes preserving order.
    """
    ports: list[str] = []

    try:
        ports.extend([p.device for p in list_ports.comports() if p.device])
    except Exception:
        pass

    ports.extend(glob.glob("/dev/ttyACM*"))
    ports.extend(glob.glob("/dev/ttyUSB*"))

    seen = set()
    out: list[str] = []
    for dev in ports:
        if dev in seen:
            continue
        seen.add(dev)
        if os.path.exists(dev):
            out.append(dev)
    return out

@dataclass
class Result:
    port: str = ""
    status: str = "nogps"  # working|nofix|nodata|nogps

def sniff(port: str, baud: int, listen: float) -> Tuple[Result, bool]:
    """
    Returns (Result, nmea_ok)
    - nmea_ok=True means checksum-valid NMEA was seen at this baud (so caller should stop trying other bauds for this port)
    """
    start = time.time()
    nmea_ok = False

    try:
        with serial.Serial(port, baud, timeout=0.4) as ser:
            time.sleep(0.2)

            while time.time() - start < listen:
                line = ser.readline()
                if not line:
                    continue

                s = line.decode(errors="ignore").strip()
                if not s.startswith("$") or "*" not in s:
                    continue

                if not nmea_checksum_ok(s):
                    continue

                nmea_ok = True

                f = parse_fix(s)
                if f is True:
                    return Result(port, "working"), True
                # keep listening; if we never see a fix, we'll return "nofix" below

    except (serial.SerialException, OSError):
        # Keep attempted port in output; treat as no usable NMEA at this baud
        return Result(port, "nodata"), False

    if not nmea_ok:
        return Result(port, "nodata"), False

    return Result(port, "nofix"), True

def emit(r: Result) -> None:
    if r.status == "nogps":
        print("nogps,nogps")
    else:
        print(f"{r.port},{r.status}")

def score(r: Result) -> int:
    """
    Higher is better.
    Priority: working > nofix > nodata > nogps
    """
    return {"working": 3, "nofix": 2, "nodata": 1, "nogps": 0}.get(r.status, 0)

def main() -> int:
    if not sys.platform.startswith("linux"):
        emit(Result("", "nogps"))
        return 3

    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", type=float, default=6.0,
                    help="Seconds to listen per (port,baud) attempt")
    ap.add_argument("--bauds", default="4800,9600,19200,38400,57600,115200",
                    help="Comma-separated baud rates to try")
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()

    bauds = [int(x.strip()) for x in args.bauds.split(",") if x.strip()]
    ports = linux_ports()

    best = Result("", "nogps")

    for port in ports:
        for baud in bauds:
            if args.debug:
                print(f"Trying {port}@{baud}", file=sys.stderr)

            r, nmea_ok = sniff(port, baud, args.listen)

            if score(r) > score(best):
                best = r

            if r.status == "working":
                emit(r)
                return 0

            # Stop trying other bauds on THIS port once checksum-valid NMEA is seen
            if nmea_ok:
                break

    emit(best)
    return {"working": 0, "nofix": 1, "nodata": 2, "nogps": 3}.get(best.status, 3)

if __name__ == "__main__":
    raise SystemExit(main())