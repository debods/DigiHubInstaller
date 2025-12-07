#! /bin/bash

#
# DigiHub Build Script
#
# Version 1.0a
#
# Steve de Bode - KQ4ZCI - December 2025
#

# Functions

function YnContinue {
 while true; do
 printf 'Do you wish to continue (Y/n) '; read -n1 -r response
 case $response in Y|y) printf '\n'; break ;; N|n) printf '\nInstallation aborted.\n'; exit 0 ;; *) printf '\nInvalid response, please select (Y/n)\n' ;; esac
done
}

# Variables
RED='\e[31m'
NC='\e[0m'  
    
# Script Directories
HomePath="/home/$USER"
DigiHubHome="$HomePath/DigiHub"
ScriptPath="$DigiHubHome/scripts"
venv_dir="$DigiHubHome/.digihub-venv"
PythonPath="$DigiHubHome/pyscripts"

# Check Parameters
if [ "$#" -ne "1" ]; then
  printf '\nUsage: %s <callsign>\n\n' "$0" >&2
  exit 1
fi

# Check for Internet Connectivity
ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1
if [ $? -ne 0 ]; then
 printf '\nNo internet connectivity detected, which is required for initial installation - Aborting.\n\n'
 exit 1
fi

# Get Home QTH & Check Valid ( availble as checkcall script)
qth=$(curl -s "https://api.hamdb.org/v1/$1/csv/$1")
IFS=',' read -r callsign licenseclass licenseexpiry grid lat lon status forename initial surname suffix street town state zipcode country <<< "$qth"

if [ "$callsign" != "${1^^}" ]; then
 printf '\nThe Callsign \"%s\" is either invalid or not found, please check and try again.\n\n' "$1"
 exit 1
fi

fullname="$forename $initial $surname"; fullname=$(echo "$fullname" | xargs)
address="$street, $town, $state $zipcode $country"

# Convert License Class
case "$licenseclass" in "T") licenseclass="Technician" ;; "G") licenseclass="General" ;; "E") licenseclass="Extra" ;; "N") licesnseclass="Novice" ;; "A") licenseclass "Advanced" ;; *) licenseclass="Station Callsign" ;; esac

# Convert License Status
case "$status" in "A") status="Active" ;; "E") status="Expired" ;; "P") status="Pending" ;; *) status="Unknown" ;; esac

# Check for correct installation information
printf '\nInstalling DigiHub in %s, with current information held by the FCC (can be edited later):\n\n' "$DigiHubHome"
printf 'Callsign\t%s\nLicense:\t%s expires %s (%s)\nName:\t\t%s\nAddress:\t%s\nCoordinates:\tGrid: %s Latitude: %s Longitude %s\n\n' "$callsign" "$licenseclass" "$licenseexpiry" "$status" "$fullname" "$address" "$grid" "$lat" "$lon"
YnContinue

# Need to think about this, changing one will change all!

# $grid
# $latitude
# $longitude

# Overwrite existing Installation Warning
printf '%b' "${RED}" 'Warning! ' "${NC}" 'continuing will overwrite an existing installation of DigiHub\n'
YnContinue

printf '\nThis may take some time ...\n\n' 

exit 0

# Clone from GitHub and move into place

# Create Directories
cd $HomePath
if [ ! -d "$ScriptPath" ]; then
    mkdir -p "$ScriptPath" "$PythonPath"
fi

# Set Environment & PATH
if ! grep -qF "# DigiHub Installation" "$HomePath/.profile"; then
 echo -e "\n# DigiHub Installation" >> "$HomePath/.profile"
fi

if ! grep -qF "export DigiHub=$DigiHubHome" "$HomePath/.profile"; then
 echo -e "export DigiHub=$DigiHubHome" >> "$HomePath/.profile"
fi

if ! grep -qF "$ScriptPath" "$HomePath/.profile"; then
 echo -e "PATH=\"$ScriptPath:\$PATH\"" >> "$HomePath/.profile"
fi

# Shell Script Creation
printf 'Creating Scripts ... '
printf '#! /bin/bash\n\nsudo reboot\n' | tee $ScriptPath/reboot >/dev/null 2>&1
printf '#! /bin/bash\n\nsudo shutdown -HP now\n' | tee $ScriptPath/shutdown >/dev/null 2>&1
printf '#! /bin/bash\n\nsudo apt update\nsudo apt -y full-upgrade\nsudo apt -y autoremove\n' | tee  $ScriptPath/update >/dev/null 2>&1
printf '#! /bin/bash\n\naprspw=$(python3 %s/aprspass.py $callsign)\nBash' "$PythonPath" | tee  $ScriptPath/aprspass >/dev/null 2>&1

# Python Script Creation
printf '#!/usr/bin/env python\n\nimport sys\n\ndef getPass(callsign):\n\n basecall = callsign.upper().split('-')[0] + '\\\\0'\n result = 0x73e2\n\n c = 0\n while (c+1 < len(basecall)):\n  result ^= ord(basecall[c]) << 8\n  result ^= ord(basecall[c+1])\n  c += 2\n\n result &= 0x7fff\n return result\n\ndef main():\n print (getPass(sys.argv[1]))\n\nif __name__ == "__main__":\n main()\n' | tee  $PythonPath/aprspass.py >/dev/null 2>&1

# Set Script Permissions
chmod +x $ScriptPath/* $PythonPath/*
printf 'Complete\n\n'

# Update OS
printf 'Updating Operating System ... '
source $ScriptPath/update >/dev/null 2>&1
printf 'Complete\n\n'

# Setup Python Virtual Environment
printf 'Configuring Python ... '
if [ ! -d "$venv_dir" ]; then
 python3 -m venv "$venv_dir" >/dev/null 2>&1
 source "$venv_dir/bin/activate"
# Install Python Packages
 sudo apt -y install python3-pip >/dev/null 2>&1
 sudo $venv_dir/bin/pip3 install callsign-regex >/dev/null 2>&1
fi
printf 'Complete\n\n'

# Install Packages

# WWW Page Creation
