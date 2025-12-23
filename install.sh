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
PythonPath="$DigiHubHome/pyscripts"
venv_dir="$DigiHubHome/.digihub-venv"
InstallPath="$(pwd)"

# Source paths (before files are copied into place)
SrcPy="$InstallPath/Files/pyscripts"

# Captured info
callsign=""; class=""; expiry=""; grid=""; lat=""; lon=""; licstat=""
forename=""; initial=""; surname=""; suffix=""
street=""; town=""; state=""; zip=""; country=""
fullname=""; address=""

# State
DO_PURGE=0

# Ensure base install directory exists early (but DO NOT touch .dhinstalled here)
mkdir -p "$DigiHubHome"

### FUNCTIONS ###

# Normalize: trim leading/trailing whitespace + uppercase
normalize_cs() {
 local s="${1-}"
 s="${s#"${s%%[![:space:]]*}"}"
 s="${s%"${s##*[![:space:]]}"}"
 printf '%s' "${s^^}"
}

# Optional values
PromptOpt() {
 local var_name=$1 prompt=$2 value=""
 read -rp "$prompt" value
 printf -v "$var_name" '%s' "$value"
}

# Editable prompt - Usage: PromptEdit var_name "Prompt: " required(0|1)
PromptEdit() {
 local var_name=$1 prompt=$2 required=${3:-0}
 local current value=""

 while :; do
  current="${!var_name-}"

  if [[ -n $current ]]; then
   read -rp "${prompt} [${current}]: " value
  else
   read -rp "${prompt}: " value
  fi

  if [[ -n $value ]]; then
   printf -v "$var_name" '%s' "$value"
   return 0
  fi

  if [[ -n $current ]]; then
   return 0
  fi

  if (( required == 0 )); then
   printf -v "$var_name" '%s' ""
   return 0
  fi

  printf 'This field is required.\n' >&2
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

# Set variables to "Unknown" if they are empty/whitespace (safe under -u)
SetUnknownIfEmpty() {
 local v val
 for v in "$@"; do
  val="${!v-}"
  if [[ -z ${val//[[:space:]]/} ]]; then
   printf -v "$v" '%s' "Unknown"
  fi
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

# Reset all fields that come from HamDB/manual details (keep callsign as-is)
ResetDetailsKeepCallsign() {
 class=""; expiry=""; grid=""; lat=""; lon=""; licstat=""
 forename=""; initial=""; surname=""; suffix=""
 street=""; town=""; state=""; zip=""; country=""
 fullname=""; address=""
}

# Try HamDB lookup for callsign in $1. If found, populate globals and return 0.
# If not found (or API fails), do NOT abort; return 1 and leave existing details alone
# (caller decides whether to clear fields / go manual).
FetchHamDB() {
 local cs="$1" qth="" got=""
 qth="$(curl -fsS "https://api.hamdb.org/v1/${cs}/csv/${cs}" 2>/dev/null || true)"
 [[ -n "$qth" ]] || return 1

 # HamDB CSV: callsign,class,expiry,grid,lat,lon,licstat,forename,initial,surname,suffix,street,town,state,zip,country
 IFS=',' read -r got class expiry grid lat lon licstat forename initial surname suffix street town state zip country <<< "$qth"

 # Only accept if callsign matches exactly
 if [[ "$got" != "$cs" ]]; then
  return 1
 fi

 callsign="$got"
 return 0
}

# Validate lat/lon and compute grid (aborts on repeated invalid entry)
EnsureValidCoordsAndGrid() {
 local max_tries=5 tries=0 rc

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
    PromptEdit lat "Latitude (-90..90)" 1
    PromptEdit lon "Longitude (-180..180)" 1
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
}

# Manual data entry flow (used for NOFCC or non-US/unfound calls)
ManualEntryFlow() {
 printf '\nPlease enter the requested information. All fields are required unless stated otherwise.\n\n'

 PromptEdit callsign "Callsign" 1
 callsign="$(normalize_cs "$callsign")"

 PromptEdit lat "Latitude (-90..90)" 1
 PromptEdit lon "Longitude (-180..180)" 1
 EnsureValidCoordsAndGrid

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

 SetUnknownIfEmpty class expiry licstat forename surname street town state zip country
 BuildFullName
 BuildAddress
}

# Review & edit all captured values before installing
# - Enter: accept
# - q: abort (no purge)
# - If callsign is changed, ALWAYS refetch HamDB for the new callsign.
#   If found: overwrite all related fields.
#   If not found/API fails: clear details and require manual lat/lon, then optional name/license/address.
ReviewAndEdit() {
 local choice newcs

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

  read -r -p $'\nEnter a number to edit (1-16), press Enter to accept, or q to abort: ' choice
  [[ -z $choice ]] && return 0
  [[ $choice == [Qq] ]] && return 1

  case "$choice" in
   1)
     PromptEdit callsign "Callsign" 1
     newcs="$(normalize_cs "$callsign")"
     callsign="$newcs"

     # Always refresh the rest from HamDB if possible (works on 2nd/3rd/etc changes)
     if FetchHamDB "$callsign"; then
      printf '\nThe callsign "%b%s%b" was found. Details were refreshed from HamDB.\n' "$colb" "$callsign" "$ncol"
      # If HamDB returned coords, grid is already included, but we still ensure grid exists:
      if [[ -z "${grid//[[:space:]]/}" || -z "${lat//[[:space:]]/}" || -z "${lon//[[:space:]]/}" ]]; then
       # Unlikely, but handle gracefully: go manual for coords
       printf '%bWarning:%b HamDB did not return usable coordinates. Please enter them.\n' "$colr" "$ncol" >&2
       ResetDetailsKeepCallsign
       PromptEdit lat "Latitude (-90..90)" 1
       PromptEdit lon "Longitude (-180..180)" 1
       EnsureValidCoordsAndGrid
      fi
     else
      # Not found or API failed -> force manual details for this callsign
      printf '\nThe callsign "%b%s%b" was not found (or the API failed). Switching to manual entry for this callsign.\n' "$colb" "$callsign" "$ncol"
      ResetDetailsKeepCallsign
      PromptEdit lat "Latitude (-90..90)" 1
      PromptEdit lon "Longitude (-180..180)" 1
      EnsureValidCoordsAndGrid

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
     fi
     ;;
   2) PromptEdit lat "Latitude (-90..90)" 1; EnsureValidCoordsAndGrid ;;
   3) PromptEdit lon "Longitude (-180..180)" 1; EnsureValidCoordsAndGrid ;;
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

  # Normalize blanks for display consistency (except initial/suffix)
  SetUnknownIfEmpty class expiry licstat forename surname street town state zip country
  BuildFullName
  BuildAddress
 done
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
  local tmp="$HomePath/.profile.tmp.$$"
  set +e
  grep -vF -e "DigiHub" -e "sysinfo" "$HomePath/.profile" > "$tmp"
  set -e
  mv "$tmp" "$HomePath/.profile" >/dev/null 2>&1 || true
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

  rm -f "$DigiHubHome/.dhinstalled" >/dev/null 2>&1 || true
 else
  printf '%bWarning:%b %s\n' \
   "$colr" "$ncol" \
   "Package list not found — packages installed by DigiHub will NOT be removed." \
   >&2
 fi

 sudo rm -rf -- "$DigiHubHome" >/dev/null 2>&1 || true
}

# Abort handler (safe: DO NOT purge here; we may have an existing good installation)
AbortInstall() {
 local rc=${1:-1}
 printf '\nInstallation aborted.\n' >&2
 return "$rc"
}

# ERR trap: print line + command, do not purge here.
_on_err() {
 local rc=$?
 local line=${BASH_LINENO[0]:-?}
 local cmd=${BASH_COMMAND:-?}
 printf '\nFAILED rc=%s at line %s: %s\n' "$rc" "$line" "$cmd" >&2
 exit "$rc"
}

_on_exit() {
 local rc=$?
 # If rc != 0, AbortInstall already ran via ERR/exit; just propagate.
 return "$rc"
}

trap _on_err ERR
trap _on_exit EXIT

UpdateOS() {
 if ! YnCont "Run OS update now (y/N)? "; then
  printf 'Skipping OS update.\n\n'
  return 0
 fi
 sudo apt-get update >/dev/null 2>&1 || return 1
 sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade >/dev/null 2>&1 || return 1
 sudo apt-get -y autoremove >/dev/null 2>&1 || return 1
 printf '\nOS update complete.\n\n'
}

### MAIN SCRIPT ###

# Check for Internet Connectivity
if ! ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
 printf '\nNo internet connectivity detected, which is required for installation. Aborting.\n\n' >&2
 exit 1
fi

# 0 or 1 arg allowed; 2+ is an error
if (( $# > 1 )); then
 printf '\nError: too many arguments.\n' >&2
 printf 'Usage: %s [callsign|noFCC]\n\n' "$0" >&2
 exit 1
fi

# Detect existing install BEFORE prompting, and delay purge until after user confirms details
if [[ -f "$HomePath/.profile" ]] && grep -qF "DigiHub" "$HomePath/.profile"; then
 if [[ -z "${DigiHubcall-}" ]]; then
  printf '%bError:%b Existing installation detected, but a reboot is required before changes can be made.\n' "$colr" "$ncol" >&2
  exit 1
 fi

 printf '\n\n%bWarning!%b An existing DigiHub installation was detected for %b%s%b.\n' \
  "$colr" "$ncol" "$colb" "$DigiHubcall" "$ncol"
 printf 'You can reinstall/replace it, or quit now.\n\n'

 if YnCont "Reinstall/replace existing DigiHub (y/N)? "; then
  DO_PURGE=1
  printf '\nProceeding with reinstall. Existing installation will be removed after you confirm your details.\n\n'
 else
  exit 0
 fi
fi

# Determine initial callsign input
cs="$(normalize_cs "${1:-}")"

# If no argument given, prompt for callsign (and then attempt HamDB; if not found => manual)
if [[ -z "$cs" ]]; then
 PromptEdit cs "Callsign (or enter noFCC)" 1
 cs="$(normalize_cs "$cs")"
fi

# If prior install info exists and we're doing NOFCC/manual, offer to reuse it as defaults
if [[ "$cs" == "NOFCC" && -f "$HomePath/.dhinfo.last" ]]; then
 if YnCont "Previous install info found. Reuse it as defaults (y/N)? "; then
  IFS=',' read -r callsign class expiry grid lat lon licstat forename initial surname suffix street town state zip country < "$HomePath/.dhinfo.last" || true
 fi
fi

# Populate details:
# - If NOFCC => manual flow
# - Else try HamDB. If found => great.
# - If not found/API fail => treat as non-US/unlisted => manual coords + optional details.
if [[ "$cs" == "NOFCC" ]]; then
 callsign=""
 ManualEntryFlow
else
 callsign="$cs"
 if FetchHamDB "$callsign"; then
  printf '\nThe callsign "%b%s%b" was found. Please review the information below and edit as needed.\n' "$colb" "$callsign" "$ncol"
 else
  printf '\nThe callsign "%b%s%b" was not found (or the API failed). Continuing with manual entry for this callsign.\n' "$colb" "$callsign" "$ncol"
  ResetDetailsKeepCallsign
  PromptEdit lat "Latitude (-90..90)" 1
  PromptEdit lon "Longitude (-180..180)" 1
  EnsureValidCoordsAndGrid

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
 fi
fi

# Normalize optional fields for review display (except initial/suffix)
SetUnknownIfEmpty class expiry licstat forename surname street town state zip country
BuildFullName
BuildAddress

# Final review/edit of captured values (allow abort)
if ! ReviewAndEdit; then
 printf '\nNo changes were made.\n\n'
 exit 0
fi

# If we’re replacing an existing install, purge ONLY AFTER user confirmed details
if (( DO_PURGE == 1 )); then
 PurgeExistingInstall
 mkdir -p "$DigiHubHome"
fi

# Create a fresh package list for THIS install run
: > "$DigiHubHome/.dhinstalled"

printf '\nThis may take some time...\n\n'

# Update OS (non-fatal)
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
  YnCont "Continue (y/N)? "
  ;;
esac

# Generate aprspass and axnodepass
aprspass="$(python3 "$SrcPy/aprspass.py" "$callsign")"
axnodepass="$(openssl rand -base64 12 | tr -dc A-Za-z0-9 | head -c6)"

# Copy files/directories into place & set permissions
cp -R "$InstallPath/Files/"* "$DigiHubHome/"

chmod +x "$ScriptPath/"* "$PythonPath/"*

# Set Environment & PATH
perl -i.dh -0777 -pe 's{\s+\z}{}m' "$HomePath/.profile" >/dev/null 2>&1 || true
printf '\n' >> "$HomePath/.profile"

if [[ "${gpsport-}" == "nodata" ]]; then
 gpsport="nogps"
fi

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