#!/usr/bin/env python3

"""
gpstest.py
Test for installed and working GPS device

Version 1.0a

Steve de Bode - KQ4ZCI - December 2025

Input:  None (GPS Device)
Output: GPS port,GPS status

Exit codes:
  0 = working
  1 = nofix
  2 = nodata
  3 = nogps
"""

try:
 from __future__ import annotations
 import argparse
 import glob
 import os
 import re
 import stat
 import sys
 import time
 from dataclasses import dataclass
 from typing import Optional, Tuple
 import serial
 from serial.tools import list_ports
except ModuleNotFoundError:
        print(f"\nPython virtual environmnet required to execute,\n")
        sys.exit(0)



# Strict NMEA shape: $BODY*HH
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
        status_field = parts[2].strip().upper()
        if status_field == "A":
            return True
        if status_field == "V":
            return False
        return None

    if msg_type == "GGA" and len(parts) > 6:
        q = parts[6].strip()
        if q.isdigit():
            return int(q) > 0
        return None

    return None


def is_char_device(path: str) -> bool:
    try:
        st = os.stat(path)
        return stat.S_ISCHR(st.st_mode)
    except OSError:
        return False


def linux_ports() -> list[str]:
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
        if os.path.exists(dev) and is_char_device(dev):
            out.append(dev)
    return out


@dataclass
class Result:
    port: str = ""
    status: str = "nogps"  # working|nofix|nodata|nogps


def sniff(port: str, baud: int, listen: float) -> Tuple[Result, bool, bool]:
    """
    Returns (Result, nmea_ok, opened_ok)
    """
    start = time.time()
    nmea_ok = False

    try:
        with serial.Serial(port, baud, timeout=0.25) as ser:
            opened_ok = True
            time.sleep(0.05)

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

                if parse_fix(s) is True:
                    return Result(port, "working"), True, opened_ok

            if nmea_ok:
                return Result(port, "nofix"), True, opened_ok

            return Result("", "nodata"), False, opened_ok

    except (serial.SerialException, OSError):
        return Result("", "nogps"), False, False


def emit(r: Result) -> None:
    if r.status == "nogps":
        print("nogps,nogps")
    elif r.status == "nodata":
        print("nodata,nodata")
    else:
        print(f"{r.port},{r.status}")


def main() -> int:
    if not sys.platform.startswith("linux"):
        emit(Result("", "nogps"))
        return 3

    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", type=float, default=2.0)
    ap.add_argument("--bauds", default="9600,4800,115200,38400,19200,57600")
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()

    bauds = [int(x.strip()) for x in args.bauds.split(",") if x.strip()]
    ports = linux_ports()

    opened_any = False

    for port in ports:
        for baud in bauds:
            if args.debug:
                print(f"Trying {port}@{baud}", file=sys.stderr)

            r, nmea_ok, opened_ok = sniff(port, baud, args.listen)
            opened_any |= opened_ok

            if r.status in ("working", "nofix"):
                emit(r)
                return 0 if r.status == "working" else 1

            if nmea_ok:
                break

    if opened_any:
        emit(Result("", "nodata"))
        return 2

    emit(Result("", "nogps"))
    return 3


if __name__ == "__main__":
    raise SystemExit(main())
