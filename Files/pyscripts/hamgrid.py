#!/usr/bin/env python

import math

def latlon_to_grid(latitude, longitude):
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

latitude = 37.6872  # Example latitude
longitude = -97.3301 # Example longitude

grid_square = latlon_to_grid(latitude, longitude)
prefix = grid_square[:-2]
suffix = grid_square[-2:].lower()
grid_square = prefix+suffix

print(f"{grid_square}")
