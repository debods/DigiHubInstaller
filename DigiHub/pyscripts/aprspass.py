#!/usr/bin/env python3

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
    parser.add_argument("callsign", help="Your amateur radio callsign (e.g., 9M2PJU, 9M2PJU-5)")
    args = parser.parse_args()

    passcode = aprs_passcode(args.callsign)
    print(f"Callsign: {args.callsign.upper()}")
    print(f"Passcode: {passcode}")

if __name__ == "__main__":
    main()
