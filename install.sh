#!/usr/bin/env bash

: <<'END'
install.sh
DigiHub installation and configuration script

Version 1.0a

Steve de Bode - KQ4ZCI - December 2025

Input: callsign|noFCC (optional)
Output: none - interactive
END

set -eEuo pipefail

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

# Captured / working values
callsign=""; class=""; expiry=""; grid=""; lat=""; lon=""; licstat=""
forename=""; initial=""; surname=""; suffix=""
street=""; town=""; state=""; zip=""; country=""
fullname=""; address=""

# Install-state flags
EXISTING_INSTALL=0
WANT_REINSTALL=0
DID_PURGE=0
READY_TO_PURGE=0

### FUNCTIONS ###

OnErr() {
 local line=${1:-?} rc=${2:-1}
 printf '\n%bFAILED%b rc=%s at line %s.\n' "$colr" "$ncol" "$rc" "$line" >&2
 exit "$rc"
}

trap 'OnErr "$LINENO" "$?"' ERR

# Optional values
PromptOpt() {
 local var_name=$1 prompt=$2 value=""
 read -rp "$prompt" value
 printf -v "$var_name" '%s' "$value"
}

# Set variables to "Unknown" if they are empty/whitespace
SetUnknownIfEmpty() {
 local v val
 for v in "$@"; do
  val="${!v-}"
  if [[ -z "${val//[[:space:]]/}" ]]; then
   printf -v "$v" '%s' "Unknown"
  fi
 done
}

# Editable prompt - Usage: PromptEdit var_name "Prompt: " required(0|1)
PromptEdit() {
 local var_name=$1 prompt=$2 required=${3:-0}
 local current value=""

 while :; do
  current="${!var_name-}"

  if [[ -n "$current" ]]; then
   read -rp "${prompt} [${current}]: " value
  else
   read -rp "${prompt}: " value
  fi

  if [[ -n "$value" ]]; then
   printf -v "$var_name" '%s' "$value"
   return 0
  fi

  if [[ -n "$current" ]]; then
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
  read -n1 -rp "$prompt" reply </dev/tty
  printf '\n'
  case $reply in
   [Yy]) return 0 ;;
   [Nn]|'') return 1 ;;
   *) printf 'Please select (y/N).\n' ;;
  esac
 done
}

# Normalize: trim leading/trailing whitespace + uppercase
normalize_cs() {
 local s="$1"
 s="${s#"${s%%[![:space:]]*}"}"
 s="${s%"${s##*[![:space:]]}"}"
 printf '%s' "${s^^}"
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

ResetDetailsKeepCallsign() {
 class=""; expiry=""; grid=""; lat=""; lon=""; licstat=""
 forename=""; initial=""; surname=""; suffix=""
 street=""; town=""; state=""; zip=""; country=""
 fullname=""; address=""
}

EnsureValidCoordsAndGrid() {
 local max_tries=5 tries=0 rc
 while true; do
  set +e
  python3 "$SrcPy/validcoords.py" "$lat" "$lon" >/dev/null 2>&1
  rc=$?
  set -e

  case "$rc" in
   0)
    grid="$(python3 "$SrcPy/hamgrid.py" "$lat" "$lon")"
    if [[ -z "${grid//[[:space:]]/}" ]]; then
     printf 'Error: hamgrid.py produced no output.\n' >&2
     exit 4
    fi
    return 0
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
}

# Fetch + populate from HamDB. Return 0 on success, 1 on not found/API fail.
FetchHamDB() {
 local cs="$1" qth=""
 cs="$(normalize_cs "$cs")"
 qth="$(curl -fsS "https://api.hamdb.org/v1/${cs}/csv/${cs}" 2>/dev/null || true)"
 [[ -n "${qth//[[:space:]]/}" ]] || return 1

 local t_callsign t_class t_expiry t_grid t_lat t_lon t_licstat
 local t_forename t_initial t_surname t_suffix t_street t_town t_state t_zip t_country

 IFS=',' read -r \
  t_callsign t_class t_expiry t_grid t_lat t_lon t_licstat \
  t_forename t_initial t_surname t_suffix t_street t_town t_state t_zip t_country \
  <<< "$qth" || return 1

 t_callsign="$(normalize_cs "$t_callsign")"
 [[ "$t_callsign" == "$cs" ]] || return 1

 # Overwrite everything from HamDB
 callsign="$t_callsign"
 class="$t_class"; expiry="$t_expiry"; grid="$t_grid"; lat="$t_lat"; lon="$t_lon"; licstat="$t_licstat"
 forename="$t_forename"; initial="$t_initial"; surname="$t_surname"; suffix="$t_suffix"
 street="$t_street"; town="$t_town"; state="$t_state"; zip="$t_zip"; country="$t_country"

 return 0
}

LoadExistingConfig() {
 if [[ -f "$HomePath/.dhinfo" ]]; then
  IFS=',' read -r \
   callsign class expiry grid lat lon licstat \
   forename initial surname suffix \
   street town state zip country \
   < "$HomePath/.dhinfo" || true
  callsign="$(normalize_cs "${callsign-}")"
  return 0
 fi

 # Fallback: env exports from .profile (best-effort)
 callsign="$(normalize_cs "${DigiHubcall-}")"
 lat="${DigiHubLat-}"; lon="${DigiHubLon-}"; grid="${DigiHubgrid-}"
 return 0
}

# Purge existing DigiHub install (best effort)
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
  local tmp
  tmp="$HomePath/.profile.tmp.$$"
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

AbortInstall() {
 local rc=${1:-1}
 printf '\nInstallation aborted.\n' >&2

 # If we have NOT purged an existing known-good install yet, do NOT purge now.
 if (( EXISTING_INSTALL == 1 && DID_PURGE == 0 )); then
  printf '%bWarning:%b Existing installation was NOT removed.\n' "$colr" "$ncol" >&2
  return "$rc"
 fi

 # Fresh install (or post-purge reinstall) -> clean up partials
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
 # Same safety rules as abort
 if (( EXISTING_INSTALL == 0 || DID_PURGE == 1 )); then
  PurgeExistingInstall
 fi
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
 sudo apt-get update >/dev/null 2>&1 || return 1
 sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade >/dev/null 2>&1 || return 1
 sudo apt-get -y autoremove >/dev/null 2>&1 || return 1
 printf '\nOS update complete.\n\n'
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

  read -r -p $'\nEnter a number to edit (1-16), or press Enter to accept: ' choice </dev/tty
  [[ -z "${choice//[[:space:]]/}" ]] && return 0

  case "$choice" in
   1)
     # Snapshot current state so we can revert if user changes their mind
     local old_callsign="$callsign" old_class="$class" old_expiry="$expiry" old_grid="$grid" old_lat="$lat" old_lon="$lon" old_licstat="$licstat"
     local old_forename="$forename" old_initial="$initial" old_surname="$surname" old_suffix="$suffix"
     local old_street="$street" old_town="$town" old_state="$state" old_zip="$zip" old_country="$country"

     PromptEdit callsign "Callsign" 1
     callsign="$(normalize_cs "$callsign")"

     if [[ "$callsign" == "$old_callsign" ]]; then
       :
     elif FetchHamDB "$callsign"; then
       printf '\nThe callsign "%b%s%b" was found. Details were refreshed from HamDB.\n' "$colb" "$callsign" "$ncol"

       if [[ -z "${lat//[[:space:]]/}" || -z "${lon//[[:space:]]/}" || -z "${grid//[[:space:]]/}" ]]; then
         lat="$old_lat"; lon="$old_lon"; grid="$old_grid"
         printf '%bWarning:%b HamDB did not return usable coordinates; keeping existing coordinates.\n' "$colr" "$ncol" >&2
       fi
     else
       printf '\nThe callsign "%b%s%b" was not found (or the API failed).\n' "$colb" "$callsign" "$ncol"
       printf 'Options:\n'
       printf '  (k) Keep existing coordinates/details and use this callsign\n'
       printf '  (m) Manually enter/replace coordinates and optional details for this callsign\n'
       printf '  (a) Abort this change and revert to "%s"\n' "$old_callsign"

       local resp=""
       while :; do
         read -r -n1 -p $'\nSelect k/m/a: ' resp </dev/tty
         printf '\n'
         case "$resp" in
           [Kk])
             if [[ -z "${old_lat//[[:space:]]/}" || -z "${old_lon//[[:space:]]/}" || -z "${old_grid//[[:space:]]/}" ]]; then
               printf '\nCoordinates are required. Please enter them:\n'
               PromptEdit lat "Latitude (-90..90)" 1
               PromptEdit lon "Longitude (-180..180)" 1
               EnsureValidCoordsAndGrid
             else
               lat="$old_lat"; lon="$old_lon"; grid="$old_grid"
               class="$old_class"; expiry="$old_expiry"; licstat="$old_licstat"
               forename="$old_forename"; initial="$old_initial"; surname="$old_surname"; suffix="$old_suffix"
               street="$old_street"; town="$old_town"; state="$old_state"; zip="$old_zip"; country="$old_country"
             fi
             break
             ;;
           [Mm])
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
             break
             ;;
           [Aa])
             callsign="$old_callsign"
             class="$old_class"; expiry="$old_expiry"; grid="$old_grid"; lat="$old_lat"; lon="$old_lon"; licstat="$old_licstat"
             forename="$old_forename"; initial="$old_initial"; surname="$old_surname"; suffix="$old_suffix"
             street="$old_street"; town="$old_town"; state="$old_state"; zip="$old_zip"; country="$old_country"
             printf '\nReverted callsign change.\n'
             break
             ;;
           *)
             printf 'Invalid choice. Select k/m/a.\n' >&2
             ;;
         esac
       done
     fi
     ;;
   2)
     PromptEdit lat "Latitude (-90..90)" 1
     PromptEdit lon "Longitude (-180..180)" 1
     EnsureValidCoordsAndGrid
     ;;
   3)
     PromptEdit lon "Longitude (-180..180)" 1
     PromptEdit lat "Latitude (-90..90)" 1
     EnsureValidCoordsAndGrid
     ;;
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
 done
}

### MAIN SCRIPT ###

# Check for Internet Connectivity
if ! ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
 printf '\nNo internet connectivity detected, which is required for installation. Aborting.\n\n' >&2
 exit 1
fi

# Existing install detection FIRST (before asking for callsign)
if [[ -f "$HomePath/.profile" ]] && grep -qF "DigiHub Installation" "$HomePath/.profile"; then
 EXISTING_INSTALL=1

 if [[ -z "${DigiHubcall-}" ]]; then
  printf '%bError:%b Existing installation detected, but a reboot is required before changes can be made.\n' "$colr" "$ncol" >&2
  exit 1
 fi

 printf '\n\n%bWarning!%b An existing DigiHub installation was detected for %b%s%b.\n' \
  "$colr" "$ncol" "$colb" "$DigiHubcall" "$ncol"
 printf 'You can reinstall/replace it, or quit now.\n\n'

 if YnCont "Reinstall/replace existing DigiHub (y/N)? "; then
  WANT_REINSTALL=1
  printf '\nProceeding with reinstall. Existing installation will be removed after you confirm your details.\n\n'
  LoadExistingConfig
 else
  exit 0
 fi
fi

# 0 or 1 arg allowed; 2+ is an error
if (( $# > 1 )); then
 printf '\nError: too many arguments.\n' >&2
 printf 'Usage: %s [callsign|noFCC]\n\n' "$0" >&2
 exit 1
fi

# Determine starting callsign mode (arg overrides existing config)
cs="$(normalize_cs "${1:-}")"
if [[ -n "${cs//[[:space:]]/}" ]]; then
 if [[ "$cs" == "NOFCC" ]]; then
  callsign="NOFCC"
 else
  callsign="$cs"
 fi
elif (( EXISTING_INSTALL == 0 )); then
 # No existing install and no arg -> prompt callsign (then try API, else manual)
 callsign="NOFCC"
fi

# If not already loaded from existing install, handle initial entry
if (( EXISTING_INSTALL == 0 || WANT_REINSTALL == 0 )); then
 :
fi

# If we still don't have a callsign (fresh run), prompt
if [[ -z "${callsign//[[:space:]]/}" || "$callsign" == "NOFCC" ]]; then
 if (( EXISTING_INSTALL == 0 )); then
  PromptEdit callsign "Callsign (or enter NOFCC)" 1
  callsign="$(normalize_cs "$callsign")"
 fi
fi

# If callsign is NOT NOFCC, try HamDB once; fallback to manual if it fails
API_OK=0
if [[ "$callsign" != "NOFCC" ]]; then
 if FetchHamDB "$callsign"; then
  API_OK=1
  printf '\nThe callsign "%b%s%b" was found. Please review the information below and edit as needed.\n' "$colb" "$callsign" "$ncol"
 else
  API_OK=0
  printf '\nThe callsign "%b%s%b" was not found (or the API failed). You can proceed with manual entry.\n' "$colb" "$callsign" "$ncol"
 fi
fi

# Manual entry if needed (fresh run OR API failed and missing coords)
if [[ "$callsign" == "NOFCC" || $API_OK -eq 0 ]]; then
 if [[ "$callsign" == "NOFCC" ]]; then
  printf '\nPlease enter the requested information. All fields are required unless stated otherwise.\n\n'
  PromptEdit callsign "Callsign" 1
  callsign="$(normalize_cs "$callsign")"
 else
  printf '\nManual entry is required for "%b%s%b".\n' "$colb" "$callsign" "$ncol"
 fi

 # Only force coords if missing; otherwise keep what we already have (important for reinstall/edit cases)
 if [[ -z "${lat//[[:space:]]/}" || -z "${lon//[[:space:]]/}" ]]; then
  PromptEdit lat "Latitude (-90..90)" 1
  PromptEdit lon "Longitude (-180..180)" 1
  EnsureValidCoordsAndGrid
 else
  # Make sure grid is consistent if missing
  if [[ -z "${grid//[[:space:]]/}" ]]; then
   EnsureValidCoordsAndGrid
  fi
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

# Normalize optional fields for display/review (except initial and suffix)
SetUnknownIfEmpty class expiry licstat forename surname street town state zip country
BuildFullName
BuildAddress

# Final review/edit of captured values (includes improved callsign-edit logic)
ReviewAndEdit
BuildFullName
BuildAddress

# Final “are we doing this?” checkpoint (and sets safe purge point)
if ! YnCont "Proceed with installation (y/N)? "; then
 printf '\nInstallation cancelled.\n'
 exit 0
fi

READY_TO_PURGE=1

# If reinstall was requested, purge ONLY NOW (after user confirmed details)
if (( WANT_REINSTALL == 1 && READY_TO_PURGE == 1 )); then
 DID_PURGE=1
 PurgeExistingInstall
fi

# Ensure base directory exists for THIS run
mkdir -p "$DigiHubHome"

# Create a fresh package list for THIS install run
: > "$DigiHubHome/.dhinstalled"

printf '\nThis may take some time...\n\n'

# Update OS (must not abort install)
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
 # shellcheck disable=SC1091
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
 # shellcheck disable=SC1091
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
   IFS= read -r -n1 -p $'\nUse GPS location or entered coordinates for installation (c/f)? ' response </dev/tty
   printf '\n'
   case "$response" in
    [Cc]) lat=$gpslat; lon=$gpslon; grid=$hamgrid; break ;;
    [Ff]) break ;;
    *) printf 'Invalid response. Select c/C for current or f/F for entered.\n' ;;
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
  printf 'Continuing with coordinates: Latitude: %s Longitude: %s Grid: %s\n' "$lat" "$lon" "$grid"
  YnCont "Continue (y/N)? "
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
 "$forename" "$initial" "$surname" "$suffix" \
 "$street" "$town" "$state" "$zip" "$country" \
 > "$HomePath/.dhinfo"

# Reboot post install
while true; do
 printf '\nDigiHub successfully installed.\nReboot now (Y/n)? '
 read -n1 -r response </dev/tty
 case $response in
  Y|y) sudo reboot; printf '\nRebooting...\n'; exit 0 ;;
  N|n) printf '\nPlease reboot before using DigiHub.\n\n'; exit 0 ;;
  *) printf '\nInvalid response. Select Y or n.\n' ;;
 esac
done