#! /bin/bash

: <<'END'
install.sh
DigiHub installation and configuration script

Version 1.0a

Steve de Bode - KQ4ZCI - December 2025

Input:	callsign
Output: none - interactive
END

# Check Parameters
if [ "$#" -ne "1" ]; then
  printf '\nUsage: %s <callsign> or %s non-us\n\n' "$0" "$0" >&2
  exit 1
fi

# Functions
function YnContinue {
 while true; do
  printf '\nContinue (Y/n)? '; read -n1 -r response
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

# Check for non-us install
if [ "${1^^}" != "NON-US" ]; then
 # Check Valid Callsign (full US information available as checkcall script)
 qth=$(curl -s "https://api.hamdb.org/v1/$1/csv/$1")
 IFS=',' read -r callsign class expiry grid lat lon licstat forename initial surname suffix street town state zip country <<< "$qth"
 if [ "$callsign" != "${1^^}" ]; then
  printf '%b' '\nThe Callsign "' "$colb" "${1^^}" "$ncol" '" is either not valid in the US or not found, please check and re-run the installer with the correct callsign (or non-us).\n\n'
  exit 1
 fi
fi

# non-us information entry
if [ "${1^^}" == "NON-US" ]; then
  
  # Required callsign, lat, lon
  while [ -z "${callsign:-}" ]; do printf 'Enter callsign (required): '; read -r callsign; done
   if [ -z "${lat:-}" ] || [ -z "${lon:-}" ]; then lat=''; lon=''
    while [ -z "${lat:-}" ]; do printf 'Enter latitude (required): '; read -r lat; done
    while [ -z "${lon:-}" ]; do printf 'Enter longitude (required): '; read -r lon; done
   fi

 # Optional forename, initial, surname, suffix
 if [ -z "${forename:-}" ] && [ -z "${surname:-}" ]; then
  printf 'Enter name details? (y/N): '; read -r ans
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
   while [ -z "${forename:-}" ]; do printf 'Forename (required): '; read -r forename; done
   printf 'Initial (optional): '; read -r initial
   while [ -z "${surname:-}" ]; do printf 'Surname (required): '; read -r surname; done
   printf 'Suffix (optional): '; read -r suffix
  fi
 fi

 # Optional class, expiry, licstat
 if [ -z "${class:-}" ] && [ -z "${expiry:-}" ] && [ -z "${licstat:-}" ]; then
  printf 'Enter license details? (y/N): '; read -r ans
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
   printf 'License class: '; read -r class
   printf 'Expiry date: '; read -r expiry
   printf 'License status: '; read -r licstat
  fi
 fi

 # Optional street, town, state, zip, country
 if [ -z "${street:-}" ] && [ -z "${town:-}" ] && [ -z "${state:-}" ] && [ -z "${zip:-}" ] && [ -z "${country:-}" ]; then
  printf 'Enter address details? (y/N): '; read -r ans
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
   printf 'Street: '; read -r street
   printf 'Town/City: '; read -r town
   printf 'State/Province/County: '; read -r state
   printf 'ZIP/Postal Code: '; read -r zip
   printf 'Country: '; read -r country
  fi
 fi

fi

# Check for correct Callsign
printf '%b' '\nDigiHub will be installed for callsign "' "$colb" "${1^^}" "$ncol" '"\nIf this is incorrect select n (or N) and re-run the installer with the correct callsign.\n'
YnContinue

# Check for exising installation and warn
if grep -qF "DigiHub" "$HomePath/.profile"; then
 printf '%b' "${colr}" 'Warning! ' "${ncol}" 'There appears to be an existing installation of DigiHub for ' "${colr}" "$DigiHubcall" "${ncol}" ' which will be replaced if you continue.\n'
 YnContinue
 "$ScriptPath"/uninstall "ni" >/dev/null 2>&1
fi

printf 'This may take some time ...\n\n' 

# Update OS
printf 'Updating Operating System ... '
source "$ScriptPath"/update >/dev/null 2>&1
printf 'Complete\n\n'

# Check for Python3/wget/curl - Install if not found
for i in python3 wget curl; do
 command -v "$i" >/dev/null 2>&1 || sudo apt -y install "$i" >/dev/null 2>&1
done

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
gpscode=$?; IFS=',' read -r gpsport gpsstatus <<< "$gps"

# Catch an error from gpstest.py even though gpscode can only ever be 0, 1, 2 or 3
case "$gpscode" in
 0|1|2|3) : ;;
 *) printf 'FATAL: gpscode invariant violated (value=%q)\n' "$gpscode"; exit 1 ;;
esac

case "$gpscode" in
 # Option to use current location from GPS (available in editconfig script)
 0) 
  export DigiHubGPSport="$gpsport"; source "$venv_dir"/bin/activate
  gpsposition=$(python3 "$InstallPath"/Files/pyscripts/gpsposition.py)
  IFS=',' read -r gpslat gpslon <<< "$gpsposition"
  hamgrid=$(python3 "$InstallPath"/Files/pyscripts/hamgrid.py "$gpslat" "$gpslon")
  printf 'found on port %s and ready.\nCurrent coordinates\tLatitude: %s Longitude: %s Grid: %s\nFCC coordinates:\tLatitude: %s Longitude: %s Grid: %s\n' "$gpsport" "$gpslat" "$gpslon" "$hamgrid" "$lat" "$lon" "$grid"
while :; do IFS= read -r -n1 -p $'\nWould you like to use your current location or home QTH from the FCC for the installation (c/f)? ' response </dev/tty; printf '\n'
  case "$response" in [Cc]) lat=$gpslat; lon=$gpslon; grid=$hamgrid; break ;; [Ff]) break ;; *)    printf 'Invalid response, please select c/C for Current or f/F for FCC\n' ;; esac
done ;;
 1) printf 'found on port %s no satellite fix.\n' "$gpsport" ;;
 2) printf 'found on port %s no data is being received.\n' "$gpsport" ;;
 3) printf 'not found!\n' ;;
esac

case "$gpscode" in
 1|2)
  printf '\nPlease note: If the port is reported as nodata, there may be artefacts causing inconssitent results.\n'
  printf 'This is usually caused by a GPS device being attached and then removed, no GPS appears to be connected.\n'
  printf '\nThe raw report from your GPS is Port: %s Status: %s\n'  "$gpsport" "$gpsstatus"
  printf '\nContinue with information from your home QTH - Latitude: %s Longitude: %s Grid: %s\n' "$lat" "$lon" "$grid"
  YnContinue ;;
  # If no, need to delete ~/Digi
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
 perl -i.dh -0777 -pe 's{\s+\z}{}m' "$HomePath"/.profile >/dev/null 2>&1
 printf '\n' >> "$HomePath"/.profile
if [ "$gpsport" == "nodata" ]; then gpsport="nogps"; fi
for i in "# DigiHub Installation" "export DigiHub=$DigiHubHome" "export DigiHubPy=$PythonPath" "export DigiHubGPSport=$gpsport" "export DigiHubvenv=$venv_dir" "export DigiHubcall=$callsign" "export DigiHubaprs=$aprspass" "export DigiHubaxnode=$axnodepass" "export DigiHubLat=$lat" "export DigiHubLon=$lon" "export DigiHubgrid=$grid" "PATH=$ScriptPath:$PythonPath:\$PATH" "clear; sysinfo"; do
if ! grep -qF "$i" "$HomePath"/.profile; then
 printf '\n%s' "$i" >> "$HomePath"/.profile
fi
done
printf '\n' >> "$HomePath/.profile"

# Write .dhinfo
printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s' "$callsign" "$class" "$expiry" "$grid" "$lat" "$lon" "$licstat" "$forename" "$initial" "$surname" "$suffix" "$street" "$town" "$state" "$zip" "$country" > "$HomePath/.dhinfo"
printf '\n'

# Install Packages
sudo apt -y install lastlog2 >/dev/null 2>&1

# Web Server

# Reboot post install
while true; do
  printf '\nDigiHub successfully installed.\nReboot Now \(Y/n\)? '; read -n1 -r response; case $response in
    Y|y) sudo reboot; printf '\nRebooting\n'; break ;; N|n) deactivate >/dev/null 2>&1; printf '\nPlease reboot before attempting to access DigiHub features\n\n'; break ;; *) printf '\nInvalid response, please select Y/n' ;; esac
done
