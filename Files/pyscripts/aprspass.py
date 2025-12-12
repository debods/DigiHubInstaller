#!/usr/bin/env python3

"""
hamgrid.py
Calculate APRS Password from ham callsign

Version 1.0a

Steve de Bode - KQ4ZCI - December 2025

Output: APRS password
"""

def aprs_passcode(callsign: str) -> int:
 callsign = callsign.upper().split('-')[0]  # Remove SSID if present
 hash = 0x73E2

 for i, char in enumerate(callsign):
  if i % 2 == 0:
   hash ^= ord(char) << 8
  else:
   hash ^= ord(char)
  return hash & 0x7FFF  # 15-bit mask

def main():
 import argparse

 parser = argparse.ArgumentParser(description="Generate APRS-IS passcode for a callsign.")
 parser.add_argument("callsign", help="Your amateur radio callsign (e.g., KQ4ZCI, KQ4ZCI-2)")
 args = parser.parse_args()

 passcode = aprs_passcode(args.callsign)
 print(f"{passcode}")

if __name__ == "__main__":
 main()
