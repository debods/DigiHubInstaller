#!/usr/bin/env python3

try:
 import os
 import serial
 import pynmea2
except ModuleNotFoundError:
 print("\nPython virtual environmnet required to execute:")
 print(f"\nsource {venv_dir}/bin/activate\n")
 exit(1)

PORT = os.getenv("DigiHubGPSport")

def main():
    ser = serial.Serial(PORT, 9600, timeout=1)

    while True:
        line = ser.readline().decode('ascii', errors='ignore').strip()
        if not line:
            continue

        msg = None

        if line.startswith("$GNRMC") or line.startswith("$GPRMC"):
            try:
                msg = pynmea2.parse(line)
            except pynmea2.ParseError:
                continue
        else:
            continue

        if msg.status != "A":
            continue

        lat = msg.latitude
        lon = msg.longitude

        print(f"{lat:.6f},{lon:.6f}")
        break

if __name__ == "__main__":
    main()