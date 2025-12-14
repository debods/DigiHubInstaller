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
  printf 'Continue (Y/n)? '; read -n1 -r response
  case $response in Y|y) printf '\n\n'; break ;; N|n) printf '\nInstallation aborted.\n'; deactivate >/dev/null 2>&1; exit 0 ;; *) printf '\nInvalid response, please select y (or Y) for yes or n (or N)) for no\n' ;; esac
 done
}

# Variables
colr='\e[31m'; colb='\033[34m'; ncol='\e[0m'
    
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
 printf '%b' '\nThe Callsign "' "$colb" "${1^^}" "$ncol" '" is either invalid or not found, please check and try again.\n\n'
 exit 1
fi

# Check for correct Callsign
printf '%b' '\nThis will install DigiHub for callsign "' "$colb" "${1^^}" "$ncol" '"\n\n'
YnContinue

# Check for exising installation and warn
if grep -qF "DigiHub" "$HomePath/.profile"; then
 printf '%b' "${colr}" 'Warning! ' "${ncol}" 'There appears to be an existing installation of DigiHub which will be replaced if you continue.\n'
 YnContinue
 # run uninstaller
fi

printf 'This may take some time ...\n\n' 

# Update OS
printf 'Updating Operating System ... '
source "$ScriptPath"/update >/dev/null 2>&1
printf 'Complete\n\n'

# Setup and activate Python
printf 'Configuring Python ... '
if [ ! -d "$venv_dir" ]; then
 python3 -m venv "$venv_dir" >/dev/null 2>&1
 source "$venv_dir/bin/activate"
 # Install Python Packages
  sudo apt -y install python3-pip >/dev/null 2>&1
  printf 'Installing required Python packages ... '
  sudo "$venv_dir"/bin/pip3 install pynmea2 pyserial >/dev/null 2>&1
 deactivate
fi
printf 'Complete\n\n'

# Check GPS device Installed
printf 'Checking for GPS device ... '
gps=$(python3 "$InstallPath"/Files/pyscripts/gpstest.py)
gpscode=$?
IFS=',' read -r gpsport gpsstatus <<< "$gps"

case "$gpscode" in
 0) # Option to use current location from GPS (available in editconfig script)
  export DigiHubGPSport="$gpsport"; source "$venv_dir/bin/activate"
  gpsposition=$(python3 "$InstallPath"/Files/pyscripts/gpsposition.py)
  IFS=',' read -r gpslat gpslon <<< "$gpsposition"
  hamgrid=$(python3 "$InstallPath"/Files/pyscripts/hamgrid.py "$gpslat" "$gpslon")
  printf 'found on port %s and ready.\nCurrent coordinates\tLatitude: %s Longitude: %s Grid: %s\nFCC coordinates:\tLatitude: %s Longitude: %s Grid: %s\n' "$gpsport" "$gpslat" "$gpslon" "$hamgrid" "$lat" "$lon" "$grid"
  while true; do
   printf '\nWould you like to use your current location or home QTH from the FCC for the installation (C/f)? '; read -n1 -r response
   case $response in
    C|c) printf '\n'; lat=$gpslat; lon=$gpslon; grid=$hamgrid; break ;; F|f) break ;; *) printf '\nInvalid response, please select c (or C) for Current location or f (or F) for FCC location' ;; esac
   done
  ;;
 1) printf 'but does not have a satellite fix.\n' ;;
 2) printf 'but no data is being received.\n' ;;
 3) printf 'not found!\n' ;;
 *) ;;
esac

case "$gpscode" in 
 1|2|3|*)
  printf '\nUsing information from your home QTH - Latitude: %s Longitude: %s Grid: %s\n' "$lat" "$lon" "$grid"
  YnContinue
  ;;
esac

# Generate aprspass and axnodepass
aprspass=$(python3 "$InstallPath"/Files/pyscripts/aprspass.py "$callsign")
axnodepass=$(openssl rand -base64 12 | tr -dc A-Za-z0-9 | head -c6)

# Copy files/directories into place & set permissions
cp -R "$InstallPath"/Files/* "$DigiHubHome"
# html files
chmod +x "$ScriptPath"/* "$PythonPath"/*

# Set Environment & PATH
 # Clean existing and backup .profile
 perl -i.dh -0777 -pe 's{\s+\z}{}m' $HomePath/.profile >/dev/null 2>&1
 printf '\n' >> "$HomePath"/.profile
for i in "# DigiHub Installation" "export DigiHub=$DigiHubHome" "export DigiHubPy=$PythonPath" "export DigiHubGPSport=$gpsport" "export DigiHubvenv=$venv_dir" "export DigiHubcall=$callsign" "export DigiHubaprs=$aprspass" "export DigiHubaxnode=$axnodepass" "export DigiHubLat=$lat" "export DigiHubLon=$lon" "export DigiHubgrid=$grid" "PATH=$ScriptPath:$PythonPath:\$PATH" "clear; sysinfo"; do
if ! grep -qF "$i" "$HomePath"/.profile; then
 printf '\n%s' "$i" >> "$HomePath"/.profile
fi
done
printf '\n' >> "$HomePath/.profile"

# Install Packages
sudo apt -y install lastlog2 >/dev/null 2>&1

# Web Server

# Reboot
while true; do
  printf '\nReboot Now (Y/n) '; read -n1 -r response; case $response in
    Y|y) sudo reboot; printf '\nRebooting' ;; N|n) deactivate >/dev/null 2>&1; printf '\nPlease reboot before attempting to access DigiHub features\n\n'; break ;; *) printf '\nInvalid response, please select Y/n' ;; esac
done