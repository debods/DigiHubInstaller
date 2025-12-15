"""
validcoords.py
Calculate APRS Password from ham callsign

Version 1.0a

Steve de Bode - KQ4ZCI - December 2025

Input:	callsign
Output: (APRS password)
"""

def validate(latitude, longitude):
    if not isinstance(latitude, (int, float)):
        raise ValueError("Latitude must be a number")

    if not isinstance(longitude, (int, float)):
        raise ValueError("Longitude must be a number")

    if latitude < -90.0 or latitude > 90.0:
        raise ValueError("Latitude must be between -90 and 90 degrees")

    if longitude < -180.0 or longitude > 180.0:
        raise ValueError("Longitude must be between -180 and 180 degrees")

    return True
