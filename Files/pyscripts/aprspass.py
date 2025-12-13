#!/usr/bin/env python3

"""
hamgrid.py
Calculate APRS Password from ham callsign

Version 1.0a

Steve de Bode - KQ4ZCI - December 2025

Input:	callsign
Output: (APRS password)
"""

import sys

def aprs_passcode(callsign: str) -> int:
    # APRS-IS passcode is based on the callsign only (SSID ignored)
    base = callsign.split("-", 1)[0].strip().upper()

    h = 0x73E2
    for i, ch in enumerate(base):
        if i & 1:
            h ^= ord(ch)
        else:
            h ^= ord(ch) << 8

    return h & 0x7FFF

def main() -> int:
    if len(sys.argv) != 2:
        return 2

    cs = sys.argv[1]
    if not cs.strip():
        return 2

    print(aprs_passcode(cs))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
