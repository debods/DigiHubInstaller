#!/usr/bin/env python3

#
# coordinates.py
# Get curent position fro GPS
#
# Version 1.0a
#
# Steve de Bode - KQ4ZCI - December 2025
#

try:
 import os 
 import serial
 import pynmea2
except ModuleNotFoundError:
 venv_dir = os.getenv("venv_dir")
 print("\nPython virtual environmnet required to execute:")
 print(f"\nsource {venv_dir}/bin/activate\n")
 exit(1)

PORT = "/dev/serial0"
BAUD = 9600

def main():
    ser = serial.Serial(PORT, BAUD, timeout=1)

    while True:
        line = ser.readline().decode('ascii', errors='ignore').strip()
        if not line:
            continue

        if line.startswith("$GNRMC") or line.startswith("$GPRMC"):
            try:
                msg = pynmea2.parse(line)
            except:
                continue

            if msg.status != "A":  # A = valid fix
                continue

            lat = msg.latitude
            lon = msg.longitude

            print(f"{lat:.6f},{lon:.6f}")
            break  # done — exit after one output

if __name__ == "__main__":
    main()
