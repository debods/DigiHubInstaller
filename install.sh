#!/usr/bin/env bash

: <<'END'
install.sh
DigiHub installation and configuration script

Version 1.0a
Steve de Bode - KQ4ZCI - December 2025

Input: callsign (optional)
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

# Captured/derived values
callsign=""; class=""; expiry=""; grid=""; lat=""; lon=""; licstat=""
forename=""; initial=""; surname=""; suffix=""
street=""; town=""; state=""; zip=""; country=""
fullname=""; address=""

# Reinstall / purge control
EXISTING_INSTALL=0
REINSTALL_CHOSEN=0
PURGED=0

### FUNCTIONS ###

die() {
 local rc=${1:-1}; shift || true
 printf '%bError:%b %s\n' "$colr" "$ncol" "${*:-Unknown error}" >&2
 exit "$rc"
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

  if [[ -n "$current" ]]; then
   read -rp "${prompt} [${current}]: " value
  else
   read -rp "${prompt}: " value
  fi

  # Replace if user typed something
  if [[ -n "$value" ]]; then
   printf -v "$var_name" '%s' "$value"
   return 0
  fi

  # Keep existing if Enter and already set
  if [[ -n "$current" ]]; then
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

# Set variables to "Unknown" if empty/whitespace (safe under set -u)
SetUnknownIfEmpty() {
 local name val
 for name in "$@"; do
  val="${!name-}"
  if [[ -z "${val//[[:space:]]/}" ]]; then
   printf -v "$name" '%s' "Unknown"
  fi
 done
}

# y/n; return 0 for yes.
YnCont() {
 local prompt=${1:-"Continue (y/N)? "} reply=""
 while :; do
  read -n1 -rp "$prompt" reply
  printf '\n'
  case "$reply" in
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

# Validate lat/lon and generate grid
ValidateAndGrid() {
 local max_tries=5 tries=0 rc
 while true; do
  set +e
  python3 "$SrcPy/validcoords.py" "$lat" "$lon"
  rc=$?
  set -e
  case "$rc" in
   0)
    grid="$(python3 "$SrcPy/hamgrid.py" "$lat" "$lon")"
    if [[ -z "$grid" ]]; then
     printf 'Error: hamgrid.py produced no output.\n' >&2
     return 4
    fi
    return 0
    ;;
   1)
    ((tries++))
    if (( tries >= max_tries )); then
     printf '\nToo many invalid attempts. Aborting.\n' >&2
     return 1
    fi
    printf '\nInvalid latitude/longitude. Please try again:\n'
    PromptEdit lat "Latitude (-90..90)" 1
    PromptEdit lon "Longitude (-180..180)" 1
    ;;
   2) printf 'Error: validcoords.py usage or internal error.\n' >&2; return 2 ;;
   *) printf 'Error: validcoords.py returned unexpected exit code %s.\n' "$rc" >&2; return 3 ;;
  esac
 done
}

# Try HamDB lookup; on success populate fields and return 0; on failure return 1
LookupHamDB() {
 local cs="$1" qth=""
 qth="$(curl -fsS "https://api.hamdb.org/v1/${cs}/csv/${cs}" 2>/dev/null || true)"
 [[ -z "$qth" ]] && return 1

 # HamDB CSV payload is: callsign,class,expiry,grid,lat,lon,licstat,forename,initial,surname,suffix,street,town,state,zip,country
 IFS=',' read -r callsign class expiry grid lat lon licstat forename initial surname suffix street town state zip country <<< "$qth" || return 1

 [[ "${callsign^^}" != "${cs^^}" ]] && return 1
 return 0
}

# When callsign changes during review: repopulate from HamDB if found, else clear the dependent fields.
RefreshFromHamDBOrClear() {
 local newcs="$1"
 if LookupHamDB "$newcs"; then
  printf '\nHamDB data loaded for "%b%s%b".\n' "$colb" "$newcs" "$ncol"
  return 0
 fi

 # Not found / API failed: clear fields that depend on callsign
 printf '\n%bWarning:%b Callsign "%s" not found (or lookup failed). Clearing dependent fields for manual entry.\n' \
  "$colr" "$ncol" "$newcs" >&2

 class=""; expiry=""; grid=""; lat=""; lon=""; licstat=""
 forename=""; initial=""; surname=""; suffix=""
 street=""; town=""; state=""; zip=""; country=""
 return 1
}

# Manual capture (used for NOFCC OR when API lookup fails)
ManualCapture() {
 printf '\nPlease enter the requested information. All fields are required unless stated otherwise.\n\n'

 # Callsign is already known (or prompted) – but allow edit
 PromptEdit callsign "Callsign" 1
 callsign="$(normalize_cs "$callsign")"

 PromptEdit lat "Latitude (-90..90)" 1
 PromptEdit lon "Longitude (-180..180)" 1

 ValidateAndGrid || exit $?

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
  PromptOpt class  " License class: "
  PromptOpt expiry " Expiry date: "
  PromptOpt licstat " License status: "
 fi

 printf '\n'
 if YnCont "Enter address details (all fields optional) (y/N)? "; then
  printf '\n'
  PromptOpt street " Street: "
  PromptOpt town   " Town/City: "
  PromptOpt state  " State/Province/County: "
  PromptOpt zip    " ZIP/Postal Code: "
  PromptOpt country " Country: "
 fi
 printf '\n'
}

# Review & edit all captured values before installing
# Returns:
#  0 = accept
# 99 = user aborted
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

  read -r -p $'\nEnter a number to edit (1-16), press Enter to accept, or type A to abort: ' choice
  [[ -z "$choice" ]] && return 0

  case "$choice" in
   A|a|Q|q)
    return 99
    ;;
   1)
    PromptEdit callsign "Callsign" 1
    callsign="$(normalize_cs "$callsign")"

    # Callsign change behavior:
    # - If found, repopulate all related fields from HamDB.
    # - If not found, clear dependent fields, then require lat/lon (and generate grid).
    if RefreshFromHamDBOrClear "$callsign"; then
     # If HamDB gave coords, ensure grid is present; otherwise force regen
     if [[ -n "${lat-}" && -n "${lon-}" && -z "${grid//[[:space:]]/}" ]]; then
      ValidateAndGrid || exit $?
     fi
    else
     printf '\nPlease enter coordinates for "%s".\n' "$callsign"
     PromptEdit lat "Latitude (-90..90)" 1
     PromptEdit lon "Longitude (-180..180)" 1
     ValidateAndGrid || exit $?
    fi
    ;;
   2)
    PromptEdit lat "Latitude (-90..90)" 1
    ValidateAndGrid || exit $?
    ;;
   3)
    PromptEdit lon "Longitude (-180..180)" 1
    ValidateAndGrid || exit $?
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

# Purge existing DigiHub install (used ONLY after user confirmation)
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

 # Remove DigiHub-related lines from .profile in a single pass
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

 # Remove installed packages recorded during *the last successful* DigiHub run
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

# Abort handler: only purge if we already purged (i.e., we’re cleaning a partial install)
AbortInstall() {
 local rc=${1:-1}
 printf '\nInstallation aborted.\n' >&2

 if (( PURGED == 1 )); then
  # We already removed the prior install; best-effort cleanup of partial state.
  PurgeExistingInstall || true
 fi

 exit "$rc"
}

_on_err() {
 local rc=$?
 local lineno=${1:-"?"}
 local cmd=${2:-"?"}
 printf '\n%bFAILED%b rc=%s at line %s: %s\n' "$colr" "$ncol" "$rc" "$lineno" "$cmd" >&2
 return "$rc"
}

_on_exit() {
 local rc=$?
 if [[ $rc -ne 0 ]]; then
  AbortInstall "$rc"
 fi
 return 0
}

_on_signal() {
 local sig="$1"
 printf '\nInterrupted (%s).\n' "$sig" >&2
 # Same safety rule: only purge if we already purged.
 if (( PURGED == 1 )); then
  PurgeExistingInstall || true
 fi
 case "$sig" in
  INT) exit 130 ;;
  TERM) exit 143 ;;
  *) exit 1 ;;
 esac
}

trap '_on_err "$LINENO" "$BASH_COMMAND"' ERR
trap _on_exit EXIT
trap '_on_signal INT' INT
trap '_on_signal TERM' TERM

### MAIN SCRIPT ###

# Check for Internet Connectivity (still required, even if we fall back to manual)
if ! ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
 die 1 "No internet connectivity detected, which is a requirement for installation."
fi

# 0 or 1 arg allowed; 2+ is an error
if (( $# > 1 )); then
 printf '\nError: too many arguments.\n' >&2
 printf 'Usage: %s [callsign|noFCC]\n\n' "$0" >&2
 exit 1
fi

# Ensure base directory exists (safe; no clobbering)
mkdir -p "$DigiHubHome"

# Detect existing installation BEFORE asking for callsign
if [[ -f "$HomePath/.profile" ]] && grep -qF "DigiHub" "$HomePath/.profile"; then
 EXISTING_INSTALL=1

 # Your explicit rule:
 if [[ -z "${DigiHubcall-}" ]]; then
  printf '%bError:%b Existing installation detected, but a reboot is required before changes can be made.\n' \
   "$colr" "$ncol" >&2
  exit 1
 fi

 printf '\n\n%bWarning!%b An existing DigiHub installation was detected for %b%s%b.\n' \
  "$colr" "$ncol" "$colb" "$DigiHubcall" "$ncol"
 printf 'You can reinstall/replace it, or quit now.\n\n'

 if YnCont "Reinstall/replace existing DigiHub (y/N)? "; then
  REINSTALL_CHOSEN=1
  printf '\nProceeding with reinstall. Existing installation will be removed after you confirm your details.\n\n'
 else
  exit 0
 fi

 # Load existing install details as defaults (so the user sees the existing info)
 if [[ -f "$HomePath/.dhinfo" ]]; then
  IFS=',' read -r callsign class expiry grid lat lon licstat forename initial surname suffix street town state zip country < "$HomePath/.dhinfo" || true
 fi
fi

# Determine initial callsign mode
arg_cs="$(normalize_cs "${1:-}")"

# If no parameter and reinstall chosen, default to existing DigiHubcall
if [[ -z "$arg_cs" && $REINSTALL_CHOSEN -eq 1 ]]; then
 arg_cs="$(normalize_cs "${DigiHubcall}")"
fi

# If still no parameter and we didn't load callsign from dhinfo, prompt for callsign
if [[ -z "$arg_cs" ]]; then
 if [[ -z "${callsign//[[:space:]]/}" ]]; then
  PromptEdit callsign "Callsign (or NOFCC)" 1
 fi
 arg_cs="$(normalize_cs "$callsign")"
else
 callsign="$arg_cs"
fi

# If an existing install is being reinstalled AND user changes callsign later,
# ReviewAndEdit will repopulate from HamDB (or clear for manual) automatically.

# NOFCC explicitly forces manual entry
if [[ "$arg_cs" == "NOFCC" ]]; then
 callsign="NOFCC"
 ManualCapture
else
 # If we already have populated defaults from .dhinfo (existing install) and we are running with no args,
 # we will still offer HamDB refresh later if they change callsign. But if lat/lon/grid are missing now,
 # try HamDB immediately.
 if [[ -z "${lat//[[:space:]]/}" || -z "${lon//[[:space:]]/}" || -z "${grid//[[:space:]]/}" ]]; then
  if LookupHamDB "$arg_cs"; then
   printf '\nThe callsign "%b%s%b" was found. Please review the information below and edit as needed.\n' \
    "$colb" "$arg_cs" "$ncol"
  else
   printf '\n%bWarning:%b Callsign lookup failed (or not found). Continuing with manual entry.\n\n' \
    "$colr" "$ncol" >&2
   callsign="$arg_cs"
   ManualCapture
  fi
 else
  # We have complete defaults (existing install). If the user wants a fresh fetch, they can edit callsign in review.
  callsign="$arg_cs"
 fi
fi

# Ensure grid exists if we have coords
if [[ -n "${lat-}" && -n "${lon-}" && -z "${grid//[[:space:]]/}" ]]; then
 ValidateAndGrid || exit $?
fi

# Ensure optional fields show as Unknown for review/summary (except initial/suffix)
SetUnknownIfEmpty class expiry licstat forename surname street town state zip country
BuildFullName
BuildAddress

# Final review/edit (with abort option)
if ! ReviewAndEdit; then
 rc=$?
 if [[ $rc -eq 99 ]]; then
  printf '\nNo changes were made.\n'
  exit 0
 fi
 exit "$rc"
fi

BuildFullName
BuildAddress

# If reinstall was chosen, do purge NOW (after confirmation/review), not earlier
if (( REINSTALL_CHOSEN == 1 )); then
 if ! YnCont "Proceed with reinstall and remove the existing DigiHub installation (y/N)? "; then
  printf '\nNo changes were made.\n'
  exit 0
 fi

 PurgeExistingInstall
 PURGED=1
 mkdir -p "$DigiHubHome"
fi

# Create a fresh package list for THIS install run (do not clobber earlier runs prematurely)
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
 # shellcheck disable=SC1090
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
 # shellcheck disable=SC1090
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
 *) die 1 "FATAL: gpscode invariant violated (value=$gpscode)" ;;
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
  YnCont "Continue (y/N)? " || exit 0
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

if [[ "${gpsport:-}" == "nodata" ]]; then
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

# Web Server (placeholder)

# Reboot post install
while true; do
 printf '\nDigiHub successfully installed.\nReboot now (Y/n)? '
 read -n1 -r response
 case "$response" in
  Y|y) sudo reboot; printf '\nRebooting...\n'; exit 0 ;;
  N|n) printf '\nPlease reboot before using DigiHub.\n\n'; exit 0 ;;
  *) printf '\nInvalid response. Select Y or n.\n' ;;
 esac
done