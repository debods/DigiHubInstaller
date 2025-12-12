#! /bin/bash

#
# install.sh
# DigiHub installation and configuration script
#
# Version 1.0a
#
# Steve de Bode - KQ4ZCI - December 2025
#

# Check Parameters
if [ "$#" -ne "1" ]; then
  printf '\nUsage: %s <callsign>\n\n' "$0" >&2
  exit 1
fi

# Functions

function YnContinue {
 while true; do
  printf 'Proceed (Y/n)? '; read -n1 -r response
  case $response in Y|y) printf '\n'; break ;; N|n) printf '\nInstallation aborted.\n'; exit 0 ;; *) printf '\nInvalid response, please select (Y/n)\n' ;; esac
 done
}

# Variables
RED='\e[31m'
NC='\e[0m'  
    
# Script Directory Variables
WebPath="/var/www/html"
HomePath="/home/$USER"
DigiHubHome="$HomePath/DigiHub"
ScriptPath="$DigiHubHome/scripts"
venv_dir="$DigiHubHome/.digihub-venv"
PythonPath="$DigiHubHome/pyscripts"
InstallPath=$(pwd)

# Check for Internet Connectivity
if ! ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
 printf '\nNo internet connectivity detected, which a requirement for installation - Aborting.\n\n'
 exit 1
fi

# Check Valid Callsign (full information available as checkcall script)
qth=$(curl -s "https://api.hamdb.org/v1/$1/csv/$1")
IFS=',' read -r callsign licenseclass licenseexpiry grid lat lon status forename initial surname suffix street town state zip country <<< "$qth"

if [ "$callsign" != "${1^^}" ]; then
 printf '\nThe Callsign \"%s\" is either invalid or not found, please check and try again.\n\n' "$1"
 exit 1
fi

# Check for correct Callsign


# Check for exising installation and warn
if grep -qF "DigiHub" "$HomePath/.profile"; then
 printf '%b' "${RED}" 'Warning! ' "${NC}" 'There appears to be an existing installation of DigiHub which will be replaced if you continue.\n'
 YnContinue
 # run uninstaller
fi

printf '\nThis may take some time ...\n\n' 

# Update OS
printf 'Updating Operating System ... '
source $ScriptPath/update >/dev/null 2>&1
printf 'Complete\n\n'

# Setup and activate Python venv
printf 'Configuring Python ... '
if [ ! -d "$venv_dir" ]; then
 python3 -m venv "$venv_dir" >/dev/null 2>&1
 source "$venv_dir/bin/activate"
 # Install Python Packages
  sudo apt -y install python3-pip >/dev/null 2>&1
  printf 'Installing required Python packages ... '
  sudo $venv_dir/bin/pip3 install pyserial >/dev/null 2>&1
fi
printf 'Complete\n\n'

# Copy files/directories into place & set permissions
cp -R $InstallPath/Files/* $DigiHubHome
# html files
chmod +x $ScriptPath/* $PythonPath/*

# Check GPS device Installed
printf 'Checking for GPS device ... '
gps=$($PythonPath/gpstest.py)
IFS=',' read -r gpsport gpsstatus <<< $gps

echo ""$gpsport $gpsstatus"
exit 0

if [[ "$gpsport" == *"dev"* ]]; then
 if [[ "$gpsstatus" == "nodata" ]]; then printf '\nGPS device found but no data is being received. '; fi
 if [[ "$gpsstatus" == "nofix" ]]; then printf '\nGPS device found but does not have a satellite fix. '; fi
fi
if [[ "$gpsstatus" == "nodata" || ""$gpsstatus" == "nofix" ]]; then printf 'Using information from your home QTH - Latitude: %s Longitude: %s Grid: %s\n' "$lat" "$lon" "$grid"; YnContinue; fi
if [[ "$gpsport" == "nogps" ]]; then printf 'Not found!'

# Option to use current location from GPS (available as changelocale script)
if [[ $gpsstatus" == "working" ]]; then
 gpsposition=$($PythonPath/gpsposition.py)
 IFS=',' read -r gpslat gpslon <<< $gpsposition
 hamgrid=$(python3 $DigiHubPy/hamgrid.py "$gpslat" "$gpslon")
 printf '\nGPS device found and working - Current Latitude: %s Longitude: %s Grid: %s\n' "$gpslat" "$gpslon" "$hamgrid"
 while true; do
  printf '\nWould you like to use your current location or home QTH for the installation (C/q)? '; read -n1 -r response
  case $response in
    C|c) lat=gpslat; lon=gpslon; grid=hamgrid ;; Q|q) break ;; *) printf '\nInvalid response, please select Y/n' ;; esac
 done
fi

# Generate aprspass and axnodepass
aprspass=$($PythonPath/aprspass.py "$callsign")
axnodepass=$(openssl rand -base64 12 | tr -dc A-Za-z0-9 | head -c6)

# Set Environment & PATH
for i in "# DigiHub Installation" "export DigiHub=$DigiHubHome" "export DigiHubPy=$PythonPath" "export DigiHubGPSport=$gpsport" "export DigiHubvenv=$venv_dir" "export DigiHubcall=$callsign" "export DigiHubaprs=$aprspass" "export DigiHubaxnode=$axnodepass" "export DigiHubLat=$lat" "export DigiHubLon=$lon" "export DigiHubgrid=$grid" "PATH=$ScriptPath:$PythonPath:\$PATH" "clear; sysinfo"; do
if ! grep -qF "$i" "$HomePath/.profile"; then
 printf '\n%s' "$i" >> "$HomePath/.profile"
fi
done
printf '\n' >> "$HomePath/.profile"

# Install Packages
sudo apt -y install lastlog2 >/dev/null 2>&1

# Web Server

# Reboot
while true; do
  printf '\nReboot Now (Y/n) '; read -n1 -r response
  case $response in
    Y|y) deactivate; sudo reboot ;; N|n) deactivate; printf '\nPlease reboot before attempting to access DigiHub features\n\n'; break ;; *) printf '\nInvalid response, please select Y/n' ;; esac
done