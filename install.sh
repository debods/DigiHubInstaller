#!/usr/bin/env bash

: <<'END'
install.sh
DigiHub installation and configuration script

Version 1.0a

Steve de Bode - KQ4ZCI - December 2025

Input: callsign
Output: none - interactive
END

set -euo pipefail

### VARIABLES ###
colr='\e[31m'; colb='\033[34m'; ncol='\e[0m'
HomePath="$HOME"
DigiHubHome="$HomePath/DigiHub"
ScriptPath="$DigiHubHome/scripts"
venv_dir="$DigiHubHome/.digihub-venv"
PythonPath="$DigiHubHome/pyscripts"
InstallPath=$(pwd)

callsign=""; class=""; expiry=""; grid=""; lat=""; lon=""; licstat=""; forename=""; initial=""; surname=""; suffix=""; street=""; town=""; state=""; zip=""; country=""; fullname=""; address=""

# Source paths (before files are copied into place)
SrcPy="$InstallPath/Files/pyscripts"

# Ensure base install directory exists early (but DO NOT touch .dhinstalled here)
mkdir -p "$DigiHubHome"

# Track whether we detected an existing install AND user agreed to replace it
existing_install=0

### FUNCTIONS ###

# Optional values
PromptOpt() {
 local var_name=$1 prompt=$2 value=""
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

# Editable prompt - Usage: PromptEdit var_name "Prompt: " required(0|1)
PromptEdit() {
 local var_name=$1 prompt=$2 required=${3:-0}
 local current value=""

 while :; do
  current=${!var_name-}

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
   4) printf 'Grid is derived from Latitude/Longitude. Edit 2 or 3 to change it.\n' ;;
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
   *) printf 'Invalid selection.\n' >&2 ;;
  esac

  # If lat/lon changed, validate and regenerate grid
  if [[ $choice == 2 || $choice == 3 ]]; then
   local max_tries=5 tries=0 rc
   while true; do
    set +e
    python3 "$SrcPy/validcoords.py" "$lat" "$lon"
    rc=$?
    set -e
    case "$rc" in
     0)
      grid="$(python3 "$SrcPy/hamgrid.py" "$lat" "$lon")"
      if [[ -z $grid ]]; then
       printf 'Error: hamgrid.py produced no output.\n' >&2
       exit 4
      fi
      break
      ;;
     1)
      ((tries++))
      if (( tries >= max_tries )); then
       printf '\nToo many invalid attempts, aborting installation.\n' >&2
       exit 1
      fi
      printf '\nInvalid latitude/longitude. Please try again:\n'
      PromptEdit lat "Latitude (-90..90)" 1
      PromptEdit lon "Longitude (-180..180)" 1
      ;;
     2) printf 'Error: validcoords.py usage or internal error.\n' >&2; exit 2 ;;
     *) printf 'Error: validcoords.py returned unexpected exit code %s.\n' "$rc" >&2; exit 3 ;;
    esac
   done
  fi
 done
}

# y/n; return 0 for yes.
YnCont() {
 local prompt=${1:-"Continue (y/N)? "} reply=""
 while :; do
  read -n1 -rp "$prompt" reply
  printf '\n'
  case $reply in
   [Yy]) return 0 ;;
   [Nn]|'') return 1 ;;
   *) printf 'Please select (y/N).\n' ;;
  esac
 done
}

# Build full name (ignores Unknown)
BuildFullName() {
 local parts=()
 [[ -n "$forename" && "$forename" != "Unknown" ]] && parts+=("$forename")
 [[ -n "$initial"  && "$initial"  != "Unknown" ]] && parts+=("$initial")
 [[ -n "$surname"  && "$surname"  != "Unknown" ]] && parts+=("$surname")
 [[ -n "$suffix"   && "$suffix"   != "Unknown" ]] && parts+=("$suffix")

 if ((${#parts[@]} == 0)); then
  fullname="Unknown"
 else
  fullname="${parts[*]}"
 fi
}

# Build address (ignores Unknown)
BuildAddress() {
 local parts=()
 [[ -n "$street" && "$street" != "Unknown" ]] && parts+=("$street")
 [[ -n "$town"   && "$town"   != "Unknown" ]] && parts+=("$town")

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

# Normalize: trim leading/trailing whitespace + uppercase
normalize_cs() {
 local s="$1"
 s="${s#"${s%%[![:space:]]*}"}"
 s="${s%"${s##*[![:space:]]}"}"
 printf '%s' "${s^^}"
}

DetectExistingInstall() {
 [[ -d "$DigiHubHome" && -n "$(ls -A "$DigiHubHome" 2>/dev/null || true)" ]] && return 0
 [[ -f "$HomePath/.dhinfo" ]] && return 0
 [[ -f "$HomePath/.profile" ]] && grep -qF "export DigiHub=" "$HomePath/.profile" && return 0
 return 1
}

PromptExistingInstallAction() {
 printf '%bWarning!%b An existing DigiHub installation was detected.\n' "$colr" "$ncol"
 printf 'You can reinstall/replace it, or quit now.\n\n'
 YnCont "Reinstall/replace existing DigiHub (y/N)? "
}

# Purge existing DigiHub install but DO NOT exit
PurgeExistingInstall() {
 deactivate >/dev/null 2>&1 || true

 # Preserve last install info for next reinstall (best-effort)
 if [[ -f "$HomePath/.dhinfo" ]]; then
  cp -f "$HomePath/.dhinfo" "$HomePath/.dhinfo.last" >/dev/null 2>&1 || true
 fi
 rm -f "$HomePath/.dhinfo" >/dev/null 2>&1 || true

 # Restore .profile backup if present
 if [[ -f "$HomePath/.profile.dh" ]]; then
  mv "$HomePath/.profile.dh" "$HomePath/.profile" >/dev/null 2>&1 || true
 fi

 if [[ -f "$HomePath/.profile" ]]; then
  tmp="$HomePath/.profile.tmp.$$"
  set +e; grep -vF -e "DigiHub" -e "sysinfo" "$HomePath/.profile" > "$tmp"; set -e
  mv "$tmp" "$HomePath/.profile"
 fi

 perl -i.bak -0777 -pe 's{\s+\z}{}m' "$HomePath/.profile" >/dev/null 2>&1 || true
 printf '\n' >> "$HomePath/.profile" 2>/dev/null || true
 rm -f "$HomePath/.profile.bak"* >/dev/null 2>&1 || true

 # Remove installed packages recorded during install
 if [[ -f "$DigiHubHome/.dhinstalled" ]]; then
  while IFS= read -r pkg; do
   [[ -n "${pkg//[[:space:]]/}" ]] || continue
   if dpkg -s "$pkg" >/dev/null 2>&1; then
    sudo apt-get -y purge "$pkg" >/dev/null 2>&1 || true
   fi
  done < "$DigiHubHome/.dhinstalled"

  # Package list no longer needed after purge
  rm -f "$DigiHubHome/.dhinstalled" >/dev/null 2>&1 || true
 else
  printf '%bWarning:%b %s\n' \
   "$colr" "$ncol" \
   "Package list not found — packages installed by DigiHub will NOT be removed." \
   >&2
 fi

 sudo rm -rf -- "$DigiHubHome" >/dev/null 2>&1 || true
}

# Abort handler (prints and exits with original code)
AbortInstall() {
 local rc=${1:-1}
 printf '\nInstallation aborted.\n'
 PurgeExistingInstall
 return "$rc"
}

_on_exit() {
 local rc=$?
 if [[ $rc -ne 0 ]]; then
  AbortInstall "$rc"
 fi
 return "$rc"
}

_on_signal() {
 local sig="$1"
 PurgeExistingInstall
 case "$sig" in
  INT) exit 130 ;;
  TERM) exit 143 ;;
  *) exit 1 ;;
 esac
}

trap _on_exit EXIT
trap '_on_signal INT' INT
trap '_on_signal TERM' TERM

UpdateOS() {
 if ! YnCont "Run OS update now (y/N)? "; then
  printf 'Skipping OS update.\n\n'
  return 0
 fi
 sudo apt-get update || return 1
 sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade || return 1
 sudo apt-get -y autoremove || return 1
 printf '\nOS update complete.\n\n'
}

### MAIN SCRIPT ###

# Check for Internet Connectivity
if ! ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
 printf '\nNo internet connectivity detected, which is a requirement for installation. Aborting.\n\n' >&2
 exit 1
fi

# 0 or 1 arg allowed; 2+ is an error
if (( $# > 1 )); then
 printf '\nError: too many arguments.\n' >&2
 printf 'Usage: %s [callsign|noFCC]\n\n' "$0" >&2
 exit 1
fi

# EARLY check for existing installation BEFORE prompting for callsign
if DetectExistingInstall; then
 if PromptExistingInstallAction; then
  existing_install=1
  printf '\nProceeding with reinstall. Existing installation will be removed after you confirm your details.\n\n'
 else
  printf 'Exiting without changes.\n'
  exit 0
 fi
fi

# Default to NOFCC when no arg (but we treat it as "callsign prompt" flow below)
cs="$(normalize_cs "${1:-NOFCC}")"

# If no parameter was provided, prompt for callsign (then try API; if API fails, fall back to manual).
if (( $# == 0 )); then
 read -r -p "Enter callsign (or noFCC): " cs
 cs="$(normalize_cs "${cs:-NOFCC}")"
fi

# Try hamdb lookup unless NOFCC
api_ok=0
if [[ "$cs" != "NOFCC" ]]; then
 qth="$(curl -fsS "https://api.hamdb.org/v1/${cs}/csv/${cs}" 2>/dev/null || true)"
 if [[ -n "$qth" ]]; then
  IFS=',' read -r callsign class expiry grid lat lon licstat forename initial surname suffix street town state zip country <<< "$qth"
  if [[ "${callsign^^}" == "${cs^^}" ]]; then
   api_ok=1
   printf '\nThe callsign "%b%s%b" was found. Please review the information below and edit as needed.\n' "$colb" "$cs" "$ncol"
  fi
 fi
fi

# If API lookup failed (or NOFCC), fall back to manual flow, but keep the callsign the user entered.
if [[ "$cs" == "NOFCC" || $api_ok -ne 1 ]]; then
 callsign="$cs"
 if [[ "$cs" != "NOFCC" ]]; then
  printf '\nThe callsign "%b%s%b" was not found (or lookup failed). Continuing with manual entry.\n' "$colb" "$cs" "$ncol"
 fi

 # If prior install info exists, offer to reuse as defaults
 if [[ -f "$HomePath/.dhinfo.last" ]]; then
  if YnCont "Previous install info found. Reuse it as defaults (y/N)? "; then
   IFS=',' read -r callsign class expiry grid lat lon licstat forename initial surname suffix street town state zip country < "$HomePath/.dhinfo.last" || true
  fi
 fi

 printf '\nPlease enter the requested information. All fields are required unless stated otherwise.\n\n'
 PromptEdit callsign "Callsign" 1
 PromptEdit lat "Latitude (-90..90)" 1
 PromptEdit lon "Longitude (-180..180)" 1

 # Validate lat/lon and generate grid
 max_tries=5; tries=0
 while true; do
  set +e
  python3 "$SrcPy/validcoords.py" "$lat" "$lon"
  rc=$?
  set -e
  case "$rc" in
   0) break ;;
   1)
    ((tries++))
    if (( tries >= max_tries )); then
     printf '\nToo many invalid attempts, aborting installation.\n' >&2
     exit 1
    fi
    printf '\nInvalid latitude/longitude. Please try again:\n'
    read -r -p " Enter latitude  (-90..90): " lat
    read -r -p " Enter longitude (-180..180): " lon
    ;;
   2) printf 'Error: validcoords.py usage or internal error.\n' >&2; exit 2 ;;
   *) printf 'Error: validcoords.py returned unexpected exit code %s.\n' "$rc" >&2; exit 3 ;;
  esac
 done

 grid="$(python3 "$SrcPy/hamgrid.py" "$lat" "$lon")"
 if [[ -z "$grid" ]]; then
  printf 'Error: hamgrid.py produced no output.\n' >&2
  exit 4
 fi

 printf '\n'
 if YnCont "Enter name details (all fields optional) (y/N)? "; then
  printf '\n'
  PromptEdit forename "Forename" 0
  PromptEdit initial "Initial" 0
  PromptEdit surname "Surname" 0
  PromptEdit suffix "Suffix" 0
 fi

 printf '\n'
 if YnCont "Enter license details (all fields optional) (y/N)? "; then
  printf '\n'
  PromptOpt class " License class: "
  PromptOpt expiry " Expiry date: "
  PromptOpt licstat " License status: "
 fi

 printf '\n'
 if YnCont "Enter address details (all fields optional) (y/N)? "; then
  printf '\n'
  PromptOpt street " Street: "
  PromptOpt town " Town/City: "
  PromptOpt state " State/Province/County: "
  PromptOpt zip " ZIP/Postal Code: "
  PromptOpt country " Country: "
 fi
 printf '\n'
fi

# Ensure optional fields show as Unknown (instead of blank) before review/edit - except initial and suffix
SetUnknownIfEmpty class expiry licstat forename surname street town state zip country

# Final review/edit of captured values
ReviewAndEdit
BuildFullName
BuildAddress

printf '\nDigiHub will be installed for callsign "%b%s%b" using the following details:\n\n' "$colb" "${callsign^^}" "$ncol"
printf 'License:\t%s - Expiry %s (%s)\nName:\t\t%s\nAddress:\t%s\nCoordinates:\tGrid: %s Latitude: %s Longitude: %s\n\n' \
 "$class" "$expiry" "$licstat" "$fullname" "$address" "$grid" "$lat" "$lon"

# NOW purge, but only if we detected an existing install and user agreed earlier
if (( existing_install == 1 )); then
 PurgeExistingInstall
 mkdir -p "$DigiHubHome"
fi

# Create a fresh package list for THIS install run
: > "$DigiHubHome/.dhinstalled"

printf '\nThis may take some time...\n\n'

# Update OS
UpdateOS || printf '%bWarning:%b OS update failed; continuing installation.\n\n' "$colr" "$ncol" >&2

printf 'Installing required packages... '

for pkg in python3 wget curl lastlog2 bc; do
 if dpkg -s "$pkg" >/dev/null 2>&1; then
  continue
 fi

 sudo apt -y install "$pkg" >/dev/null 2>&1 || true

 if dpkg -s "$pkg" >/dev/null 2>&1; then
  grep -Fxq "$pkg" "$DigiHubHome/.dhinstalled" || printf '%s\n' "$pkg" >> "$DigiHubHome/.dhinstalled"
 fi
done

printf 'Complete\n\n'

# Setup and activate Python
printf 'Configuring Python... '
if [[ ! -d "$venv_dir" ]]; then
 python3 -m venv "$venv_dir" >/dev/null 2>&1
 source "$venv_dir/bin/activate"

 if ! dpkg -s python3-pip >/dev/null 2>&1; then
  sudo apt -y install python3-pip >/dev/null 2>&1 || true
  if dpkg -s python3-pip >/dev/null 2>&1; then
   grep -Fxq "python3-pip" "$DigiHubHome/.dhinstalled" || printf '%s\n' "python3-pip" >> "$DigiHubHome/.dhinstalled"
  fi
 fi

 printf 'Installing required Python packages... '
 sudo "$venv_dir/bin/pip3" install pynmea2 pyserial >/dev/null 2>&1
 printf 'Complete\n\n'
else
 source "$venv_dir/bin/activate"
 printf 'Complete\n\n'
fi

# Check GPS device Installed
printf 'Checking for GPS device... '
set +e
gps="$(python3 "$SrcPy/gpstest.py")"
gpscode=$?
set -e
IFS=',' read -r gpsport gpsstatus <<< "$gps"

# Catch an error from gpstest.py even though gpscode can only ever be 0, 1, 2 or 3
case "$gpscode" in
 0|1|2|3) : ;;
 *) printf 'FATAL: gpscode invariant violated (value=%q)\n' "$gpscode" >&2; exit 1 ;;
esac

case "$gpscode" in
 0)
  export DigiHubGPSport="$gpsport"
  gpsposition="$(python3 "$SrcPy/gpsposition.py")"
  IFS=',' read -r gpslat gpslon <<< "$gpsposition"
  hamgrid="$(python3 "$SrcPy/hamgrid.py" "$gpslat" "$gpslon")"
  printf 'found on port %s and ready.\nCurrent coordinates\t\tLatitude: %s Longitude: %s Grid: %s\nFCC/entered coordinates:\tLatitude: %s Longitude: %s Grid: %s\n' \
   "$gpsport" "$gpslat" "$gpslon" "$hamgrid" "$lat" "$lon" "$grid"

  while :; do
   IFS= read -r -n1 -p $'\nUse GPS location or FCC/entered coordinates for installation (c/f)? ' response </dev/tty
   printf '\n'
   case "$response" in
    [Cc]) lat=$gpslat; lon=$gpslon; grid=$hamgrid; break ;;
    [Ff]) break ;;
    *) printf 'Invalid response. Select c/C for current or f/F for FCC/entered.\n' ;;
   esac
  done
  ;;
 1) printf 'found on port %s but no satellite fix.\n' "$gpsport" ;;
 2) printf 'found on port %s but no data is being received.\n' "$gpsport" ;;
 3) printf 'not found.\n' ;;
esac

case "$gpscode" in
 1|2)
  printf '\nNote: If the port is reported as no data, there may be artifacts from a previously attached GPS.\n'
  printf 'Raw GPS report: Port: %s Status: %s\n' "$gpsport" "$gpsstatus"
  printf 'Continuing with QTH coordinates: Latitude: %s Longitude: %s Grid: %s\n' "$lat" "$lon" "$grid"
  YnCont "Continue (y/N)? " || true
  ;;
esac

# Generate aprspass and axnodepass
aprspass="$(python3 "$SrcPy/aprspass.py" "$callsign")"
axnodepass="$(openssl rand -base64 12 | tr -dc A-Za-z0-9 | head -c6)"

# Copy files/directories into place & set permissions
cp -R "$InstallPath/Files/"* "$DigiHubHome/"

# Set execute bits (after copy)
chmod +x "$ScriptPath/"* "$PythonPath/"*

# Set Environment & PATH
perl -i.dh -0777 -pe 's{\s+\z}{}m' "$HomePath/.profile" >/dev/null 2>&1 || true
printf '\n' >> "$HomePath/.profile"

if [[ "$gpsport" == "nodata" ]]; then
 gpsport="nogps"
fi

# Append each line only once, each on its own line
for line in \
 "# DigiHub Installation" \
 "export DigiHub=$DigiHubHome" \
 "export DigiHubPy=$PythonPath" \
 "export DigiHubGPSport=$gpsport" \
 "export DigiHubvenv=$venv_dir" \
 "export DigiHubcall=$callsign" \
 "export DigiHubaprs=$aprspass" \
 "export DigiHubaxnode=$axnodepass" \
 "export DigiHubLat=$lat" \
 "export DigiHubLon=$lon" \
 "export DigiHubgrid=$grid" \
 "export PATH=$ScriptPath:$PythonPath:\$PATH" \
 "sysinfo"
do
 if ! grep -qF "$line" "$HomePath/.profile"; then
  printf '%s\n' "$line" >> "$HomePath/.profile"
 fi
done

printf '\n' >> "$HomePath/.profile"

# Write .dhinfo
printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
 "$callsign" "$class" "$expiry" "$grid" "$lat" "$lon" "$licstat" \
 "$forename" "$initial" "$surname" "$suffix" "$street" "$town" "$state" "$zip" "$country" \
 > "$HomePath/.dhinfo"

# Web Server (placeholder)

# Reboot post install
while true; do
 printf '\nDigiHub successfully installed.\nReboot now (Y/n)? '
 read -n1 -r response
 case $response in
  Y|y) sudo reboot; printf '\nRebooting...\n'; exit 0 ;;
  N|n) printf '\nPlease reboot before using DigiHub.\n\n'; exit 0 ;;
  *) printf '\nInvalid response. Select Y or n.\n' ;;
 esac
done