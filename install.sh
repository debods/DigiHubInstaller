#!/usr/bin/env bash

: <<'END'
install.sh
DigiHub installation and configuration script

Version 1.0a

Steve de Bode - KQ4ZCI - December 2025

Input:	callsign
Output: none - interactive
END

### VARIABLES ###
colr='\e[31m'; colb='\033[34m'; ncol='\e[0m'
#WebPath="/var/www/html"
HomePath="/home/$USER"
DigiHubHome="$HomePath/DigiHub"
ScriptPath="$DigiHubHome/scripts"
venv_dir="$DigiHubHome/.digihub-venv"
PythonPath="$DigiHubHome/pyscripts"
InstallPath=$(pwd)

### FUNCTIONS ###

# Required values
PromptReq() {
 local var_name=$1 prompt=$2 value
 while [[ -z $value ]]; do
  read -rp "$prompt" value
 done
 printf -v "$var_name" '%s' "$value"
}

# Optional values
PromptOpt() {
 local var_name=$1 prompt=$2 value
 read -rp "$prompt" value
 printf -v "$var_name" '%s' "$value"
}

# Set variables to "Unknown" if they are empty/whitespace
SetUnknownIfEmpty() {
 local v
 for v in "$@"; do
  [[ -z ${!v//[[:space:]]/} ]] && printf -v "$v" '%s' "Unknown"
 done
}

# Editable prompt
# Usage: PromptEdit var_name "Prompt: " required(0|1)
PromptEdit() {
 local var_name=$1 prompt=$2 required=${3:-0}
 local current value

 while :; do
  current=${!var_name}

  if [[ -n $current ]]; then
   read -rp "${prompt} [${current}]: " value
  else
   read -rp "${prompt}: " value
  fi

  # Replace if user typed something
  if [[ -n $value ]]; then
   printf -v "$var_name" '%s' "$value"
   return 0
  fi

  # Keep existing if Enter and already set
  if [[ -n $current ]]; then
   return 0
  fi

  # Allow empty if not required
  if (( required == 0 )); then
   printf -v "$var_name" '%s' ""
   return 0
  fi

  printf 'This field is required.\n' >&2
 done
}

# Review & edit all captured values before installing
ReviewAndEdit() {
 local choice

 while true; do
  printf '\n================ REVIEW =================\n'
  printf ' 1) Callsign:   %s\n' "${callsign^^}"
  printf ' 2) Latitude:   %s\n' "$lat"
  printf ' 3) Longitude:  %s\n' "$lon"
  printf ' 4) Grid:       %s\n' "$grid"
  printf ' 5) Class:      %s\n' "$class"
  printf ' 6) Expiry:     %s\n' "$expiry"
  printf ' 7) Lic Status: %s\n' "$licstat"
  printf ' 8) Forename:   %s\n' "$forename"
  printf ' 9) Initial:    %s\n' "$initial"
  printf '10) Surname:    %s\n' "$surname"
  printf '11) Suffix:     %s\n' "$suffix"
  printf '12) Street:     %s\n' "$street"
  printf '13) Town/City:  %s\n' "$town"
  printf '14) State:      %s\n' "$state"
  printf '15) ZIP/Postal: %s\n' "$zip"
  printf '16) Country:    %s\n' "$country"
  printf '========================================\n'

  read -r -p $'\nEnter a number to edit (1-16), or press Enter to accept: ' choice
  [[ -z $choice ]] && return 0

  case "$choice" in
   1) PromptEdit callsign "Callsign" 1 ;;
   2) PromptEdit lat "Latitude (-90..90)" 1 ;;
   3) PromptEdit lon "Longitude (-180..180)" 1 ;;
   5) PromptEdit class "Class" 0 ;;
   6) PromptEdit expiry "Expiry" 0 ;;
   7) PromptEdit licstat "License Status" 0 ;;
   8) PromptEdit forename "Forename" 0 ;;
   9) PromptEdit initial "Initial" 0 ;;
  10) PromptEdit surname "Surname" 0 ;;
  11) PromptEdit suffix "Suffix" 0 ;;
  12) PromptEdit street "Street" 0 ;;
  13) PromptEdit town "Town/City" 0 ;;
  14) PromptEdit state "State/Province" 0 ;;
  15) PromptEdit zip "ZIP/Postal Code" 0 ;;
  16) PromptEdit country "Country" 0 ;;
   4)
    printf 'Grid is derived from Latitude/Longitude. Edit 2 or 3 to change it.\n' ;;
   *)
    printf 'Invalid selection.\n' >&2 ;;
  esac

  # If lat/lon changed (or user asked), validate and regenerate grid
  if [[ $choice == 2 || $choice == 3 ]]; then
   local max_tries=5 tries=0 rc
   while true; do
    python3 "$InstallPath"/Files/pyscripts/validcoords.py "$lat" "$lon"
    rc=$?
    case "$rc" in
     0)
      grid="$(python3 "$InstallPath"/Files/pyscripts/hamgrid.py "$lat" "$lon")"
      if [[ -z $grid ]]; then echo "Error: hamgrid.py produced no output."; exit 4; fi
      break
      ;;
     1)
      ((tries++))
      if (( tries >= max_tries )); then
       printf '\nToo many invalid attempts, aborting installation.\n'
       exit 1
      fi
      printf '\nInvalid latitude/longitude. Please try again:\n'
      PromptEdit lat "Latitude (-90..90)" 1
      PromptEdit lon "Longitude (-180..180)" 1
      ;;
     2) printf 'Error: validcoords.py usage or internal error.\n'; exit 2 ;;
     *) printf 'Error: validcoords.py returned unexpected exit code %s.\n' "$rc"; exit 3 ;;
    esac
   done
  fi
 done
}

# y/n; return 0 for yes.
YnCont() {
 local prompt=${1:-"Continue (y/N)? "} reply
 while :; do
  read -n1 -rp "$prompt" reply
  printf '\n'
  case $reply in
   [Yy]) return 0 ;;
   [Nn]) return 1 ;;
   *) printf '%s\n' 'Please select (y/N): ' ;;
  esac
 done
}

# Purge DigiHub if installation aborted
function CleanUp() {
 printf '\nInstallation aborted.\n'
 deactivate >/dev/null 2>&1 || true
 rm "$HomePath"/.dhinfo* >/dev/null 2>&1 
 mv "$HomePath"/.profile.dh "$HomePath"/.profile  >/dev/null 2>&1 
 for i in "DigiHub"  "sysinfo"; do
  if grep -qF "$i" "$HomePath"/.profile; then
   sed -i "/$i/d" "$HomePath"/.profile
  fi
 done
 perl -i.bak -0777 -pe 's{\s+\z}{}m' ~/.profile >/dev/null 2>&1
 printf '\n' >> "$HomePath"/.profile
 rm "$HomePath"/.profile.bak* >/dev/null 2>&1 
 sudo rm -rf -- "$DigiHubHome"
 # remove installed packages
 exit 0
}

_on_exit() {
  rc=$?
  # Only clean up on abnormal exit (non-zero)
  if [[ $rc -ne 0 ]]; then
    CleanUp
  fi
  return $rc
}

_on_signal() {
  sig="$1"
  CleanUp
  # Conventional exit codes for signals: 128 + signal number
  case "$sig" in
    INT)  exit 130 ;;
    TERM) exit 143 ;;
    *)    exit 1   ;;
  esac
}

trap _on_exit EXIT
trap '_on_signal INT' INT
trap '_on_signal TERM' TERM

BuildFullName() {
  local parts=()

  # Only include if non-empty AND not "Unknown"
  [[ -n "$forename" && "$forename" != "Unknown" ]] && parts+=("$forename")
  [[ -n "$initial"  && "$initial"  != "Unknown" ]] && parts+=("$initial")
  [[ -n "$surname"  && "$surname"  != "Unknown" ]] && parts+=("$surname")

  # Suffix is special: append to the end (no extra space issues)
  if [[ -n "$suffix" && "$suffix" != "Unknown" ]]; then
    parts+=("$suffix")
  fi

  if ((${#parts[@]} == 0)); then
    fullname="Unknown"
  else
    # Join with single spaces
    fullname="${parts[*]}"
  fi
}

BuildAddress() {
  local parts=()

  [[ -n "$street" && "$street" != "Unknown" ]] && parts+=("$street")
  [[ -n "$town"   && "$town"   != "Unknown" ]] && parts+=("$town")

  # Combine state + ZIP if either exists
  local statezip=""
  [[ -n "$state" && "$state" != "Unknown" ]] && statezip="$state"
  [[ -n "$zip"   && "$zip"   != "Unknown" ]] && statezip="${statezip:+$statezip }$zip"
  [[ -n "$statezip" ]] && parts+=("$statezip")

  [[ -n "$country" && "$country" != "Unknown" ]] && parts+=("$country")

  if ((${#parts[@]} == 0)); then
    address="Unknown"
  else
    address=$(IFS=', '; echo "${parts[*]}")
  fi
}

### MAIN SCRIPT ####

# Check Parameters
if [ "$#" -ne "1" ]; then
  printf '\nUsage: %s <callsign> or %s non-us\n\n' "$0" "$0" >&2
  exit 1
fi

# Check for Internet Connectivity
if ! ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
 printf '\nNo internet connectivity detected, which a requirement for installation - Aborting.\n\n'
 exit 1
fi

# Check for non-US install
if [ "${1^^}" != "NON-US" ]; then
 # Check Valid Callsign (full US information available as checkcall script)
 qth=$(curl -s "https://api.hamdb.org/v1/$1/csv/$1")
 IFS=',' read -r callsign class expiry grid lat lon licstat forename initial surname suffix street town state zip country <<< "$qth"
 if [ "$callsign" != "${1^^}" ]; then
  printf '%b' '\nThe Callsign "' "$colb" "${1^^}" "$ncol" '" is either not valid in the US or not found, please check and re-run the installer with the correct callsign (or non-us).\n\n'
  exit 1
 fi
fi

# non-US information entry
if [ "${1^^}" == "NON-US" ]; then
  
 # Required callsign, lat, lon
 printf '\nPlease enter the requested information. Note that some fields are required unless stated otherwise.\n\n'
 PromptEdit callsign "Callsign" 1
 PromptEdit lat "Latitude (-90..90)" 1
 PromptEdit lon "Longitude (-180..180)" 1

 # Validate lat lon and generate grid
 max_tries=5; tries=0
 while true; do
  python3 "$InstallPath"/Files/pyscripts/validcoords.py "$lat" "$lon"
  rc=$?

  case "$rc" in 0) break ;;
   1)
    ((tries++))
    if (( tries >= max_tries )); then
     printf '\nToo many invalid attempts, aborting installation.\n'
     exit 1
    fi
    printf '\n Invalid latitude/longitude. Please try again:\n'
    read -r -p " Enter latitude  (-90..90): " lat
    read -r -p " Enter longitude (-180..180): " lon ;;
   2) printf 'Error: validcoords.py usage or internal error.\n'; exit 2 ;;
   *) printf 'Error: validcoords.py returned unexpected exit code $rc.\n'; exit 3 ;;
  esac
 done

 grid="$(python3 $InstallPath/Files/pyscripts/hamgrid.py "$lat" "$lon")"
 if [[ -z "$grid" ]]; then echo "Error: hamgrid.py produced no output."; exit 4; fi

 # Optional forename, initial, surname, suffix
 printf '\n'
 if YnCont "Enter name details (All fields are Optional) - (y/N)? "; then
  printf '\n'
   PromptEdit forename "Forename" 0
   PromptEdit initial "Initial" 0
   PromptEdit surname "Surname" 0
   PromptEdit suffix "Suffix" 0
 fi
 
 # Optional class, expiry, licstat
 printf '\n'
 if YnCont "Enter license details? (All fields are Optional) - (y/N)? "; then
  printf '\n'
  PromptOpt class " License class: ";  PromptOpt expiry " Expiry date: "; PromptOpt licstat " License status: "
 fi

 # Optional street, town, state, zip, country
 printf '\n'
 if YnCont "Enter address details (All fields are Optional) - (y/N)? "; then
  printf '\n'
  PromptOpt street  " Street: "; PromptOpt town " Town/City: "; PromptOpt state " State/Province/County: "; PromptOpt zip " ZIP/Postal Code: "; PromptOpt country " Country: "
 fi
 printf '\n'

 # Check for correct Callsign
 printf '%b' '\nDigiHub will be installed for callsign "' "$colb" "${callsign^^}" "$ncol" '"\nUsing the following details:\n\n' 

 # Convert Empty Fields to Unknown
 for var in class expiry licstat fullname address; do
  [[ -z ${!var//[[:space:]]/} ]] && printf -v "$var" '%s' "Unknown"
 done

 printf 'License:\t%s - Expiry %s (%s)\nName:\t\t%s\nAddress:\t%s\nCoordinates:\tGrid: %s Latitude: %s Longitude %s\n\n' "$class" "$expiry" "$licstat" "$fullname" "$address" "$grid" "$lat" "$lon"
fi

# Ensure optional fields show as "Unknown" (instead of blank) before review/edit - except initial and suffix
SetUnknownIfEmpty class expiry licstat forename surname street town state zip country

# Final review/edit of captured values
ReviewAndEdit; BuildFullName; BuildAddress

# Check for exising installation and warn
if grep -qF "DigiHub" "$HomePath/.profile"; then
 printf '%b' "${colr}" 'Warning! ' "${ncol}" 'There appears to be an existing installation of DigiHub for ' "${colr}" "$DigiHubcall" "${ncol}" ' which will be replaced if you continue.\n'
 YnCont && CleanUp >/dev/null 2>&1
fi

printf '\nThis may take some time ...\n\n' 

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
  sudo "$venv_dir"/bin/pip3 install pynmea2 pyserial >/dev/null 2>&1; printf 'Complete\n\n'
fi

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
  printf 'found on port %s and ready.\nCurrent coordinates\t\tLatitude: %s Longitude: %s Grid: %s\nFCC/entered coordinates:\tLatitude: %s Longitude: %s Grid: %s\n' "$gpsport" "$gpslat" "$gpslon" "$hamgrid" "$lat" "$lon" "$grid"
while :; do IFS= read -r -n1 -p $'\nWould you like to use the GPS location or FCC/entered coordinates for the installation (c/f)? ' response </dev/tty; printf '\n'
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
  YnCont ;;
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
  printf '\nDigiHub successfully installed.\nReboot Now (Y/n)? '; read -n1 -r response; case $response in
    Y|y) sudo reboot; printf '\nRebooting\n'; exit 0 ;; N|n) deactivate >/dev/null 2>&1; printf '\nPlease reboot before attempting to access DigiHub features\n\n'; exit 0 ;; *) printf '\nInvalid response, please select Y/n' ;; esac
done
