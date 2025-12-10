#!/usr/bin/env python

#
# hamgrid.py
# Convert latitude and longitude into Maidenhead Grid
#
# Version 1.0a
#
# Steve de Bode - KQ4ZCI - December 2025
#

import math, argparse

def grid_conversion(latitude, longitude):
 field_lon = int((longitude + 180) / 20)
 field_lat = int((latitude + 90) / 10)
 grid = chr(ord('A') + field_lon) + chr(ord('A') + field_lat)

 square_lon = int(((longitude + 180) % 20) / 2)
 square_lat = int(((latitude + 90) % 10) / 1)
 grid += str(square_lon) + str(square_lat)

 subsquare_lon = int((((longitude + 180) % 20) % 2) / (2/24))
 subsquare_lat = int((((latitude + 90) % 10) % 1) / (1/24))
 grid += chr(ord('A') + subsquare_lon) + chr(ord('A') + subsquare_lat)

 return grid

parser = argparse.ArgumentParser(description="Calculate Maidenhead Grid from Latitude and Longitude.")
parser.add_argument('latitude', type=float, help="Latitude (e.g., 41.714649)")
parser.add_argument('longitude', type=float, help="Longitude (e.g., -72.728485)")
args = parser.parse_args()

maidenhead = grid_conversion(args.latitude, args.longitude)
prefix = maidenhead[:-2]
suffix = maidenhead[-2:].lower()
maidenhead = prefix+suffix

print(f"{maidenhead}")
