#!/usr/bin/env bash

: <<'END'
install.sh
DigiHub installation and configuration script

Version 1.0a

Steve de Bode - KQ4ZCI - December 2025

Input: callsign
Output: none - interactive
END

set -eEuo pipefail

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

# Abort/purge safety
existing_install_detected=0
purge_on_abort=0

# IMPORTANT: show the real failure (line + command) instead of silent "Installation aborted."
trap '_rc=$?; printf "\n%bERROR:%b command failed (rc=%s) at line %s:\n  %s\n\n" "$colr" "$ncol" "$_rc" "$LINENO" "$BASH_COMMAND" >&2; exit "$_rc"' ERR

### FUNCTIONS ###

Die() {
 local msg=${1:-"Fatal error."}
 printf '%bError:%b %s\n' "$colr" "$ncol" "$msg" >&2
 exit 1
}

ReadTTY() {
 if [[ ! -r /dev/tty ]]; then
  Die "No interactive terminal available (/dev/tty unreadable)."
 fi
 read "$@" </dev/tty
}

DetectExistingInstall() {
 if [[ -f "$HomePath/.profile" ]] && grep -qF "DigiHub" "$HomePath/.profile"; then
  existing_install_detected=1
 else
  existing_install_detected=0
 fi
}

PromptOpt() {
 local var_name=$1 prompt=$2 value=""
 ReadTTY -r -p "$prompt" value
 printf -v "$var_name" '%s' "$value"
}

SetUnknownIfEmpty() {
 local v
 for v in "$@"; do
  [[ -z ${!v//[[:space:]]/} ]] && printf -v "$v" '%s' "Unknown"
 done
}

PromptEdit() {
 local var_name=$1 prompt=$2 required=${3:-0}
 local current value=""

 while :; do
  current=${!var_name-}

  if [[ -n $current ]]; then
   ReadTTY -r -p "${prompt} [${current}]: " value
  else
   ReadTTY -r -p "${prompt}: " value
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

  ReadTTY -r -p $'\nEnter a number to edit (1-16), or press Enter to accept: ' choice
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

YnCont() {
 local prompt=${1:-"Continue (y/N)? "} reply=""
 while :; do
  ReadTTY -n1 -r -p "$prompt" reply
  printf '\n'
  case $reply in
   [Yy]) return 0 ;;
   [Nn]|'') return 1 ;;
   *) printf 'Invalid response. Select y or N.\n' ;;
  esac
 done
}

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

normalize_cs() {
 local s="$1"
 s="${s#"${s%%[![:space:]]*}"}"
 s="${s%"${s##*[![:space:]]}"}"
 printf '%s' "${s^^}"
}

PurgeExistingInstall() {
 deactivate >/dev/null 2>&1 || true

 if [[ -f "$HomePath/.dhinfo" ]]; then
  cp -f "$HomePath/.dhinfo" "$HomePath/.dhinfo.last" >/dev/null 2>&1 || true
 fi
 rm -f "$HomePath/.dhinfo" >/dev/null 2>&1 || true

 if [[ -f "$HomePath/.profile.dh" ]]; then
  mv "$HomePath/.profile.dh" "$HomePath/.profile" >/dev/null 2>&1 || true
 fi

 if [[ -f "$HomePath/.profile" ]]; then
  tmp="$HomePath/.profile.tmp.$$"
  set +e
  grep -vF -e "DigiHub" -e "sysinfo" "$HomePath/.profile" > "$tmp"
  set -e
  mv "$tmp" "$HomePath/.profile"
 fi

 perl -i.bak -0777 -pe 's{\s+\z}{}m' "$HomePath/.profile" >/dev/null 2>&1 || true
 printf '\n' >> "$HomePath/.profile" 2>/dev/null || true
 rm -f "$HomePath/.profile.bak"* >/dev/null 2>&1 || true

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

 if (( purge_on_abort == 1 )); then
  PurgeExistingInstall
 else
  if (( existing_install_detected == 1 )); then
   printf '%bNotice:%b Existing DigiHub installation left intact (install failed before replacement).\n' "$colb" "$ncol" >&2
  fi
 fi

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
 if (( purge_on_abort == 1 )); then
  PurgeExistingInstall
 else
  if (( existing_install_detected == 1 )); then
   printf '\n%bNotice:%b Existing DigiHub installation left intact (interrupted before replacement).\n' "$colb" "$ncol" >&2
  fi
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
 sudo apt-get update || return 1
 sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade || return 1
 sudo apt-get -y autoremove || return 1
 printf '\nOS update complete.\n\n'
}

### MAIN SCRIPT ###

if ! ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
 printf '\nNo internet connectivity detected, which is a requirement for installation. Aborting.\n\n' >&2
 exit 1
fi

if (( $# > 1 )); then
 printf '\nError: too many arguments.\n' >&2
 printf 'Usage: %s [callsign|noFCC]\n\n' "$0" >&2
 exit 1
fi

DetectExistingInstall

arg_cs="${1:-}"
cs=""
force_manual=0

if [[ -z "$arg_cs" ]]; then
 ReadTTY -r -p "Enter callsign (or press Enter for manual entry): " cs
 cs="$(normalize_cs "${cs:-NOFCC}")"
else
 cs="$(normalize_cs "$arg_cs")"
fi

if [[ "$cs" == "NOFCC" ]]; then
 force_manual=1
fi

if (( force_manual == 1 )) && [[ -f "$HomePath/.dhinfo.last" ]]; then
 if YnCont "Previous install info found. Reuse it as defaults (y/N)? "; then
  IFS=',' read -r callsign class expiry grid lat lon licstat forename initial surname suffix street town state zip country < "$HomePath/.dhinfo.last" || true
 fi
fi

if (( force_manual == 0 )); then
 qth="$(curl -fsS "https://api.hamdb.org/v1/${cs}/csv/${cs}" 2>/dev/null || true)"
 if [[ -n "$qth" ]]; then
  IFS=',' read -r callsign class expiry grid lat lon licstat forename initial surname suffix street town state zip country <<< "$qth"
  if [[ "$callsign" == "$cs" ]]; then
   printf '\nThe callsign "%b%s%b" was found. Please review the information below and edit as needed.\n' "$colb" "$cs" "$ncol"
  else
   printf '%bNotice:%b Callsign lookup did not match; continuing with manual entry.\n' "$colr" "$ncol" >&2
   callsign="$cs"
   force_manual=1
  fi
 else
  printf '%bNotice:%b Callsign lookup failed or was unavailable; continuing with manual entry.\n' "$colr" "$ncol" >&2
  callsign="$cs"
  force_manual=1
 fi
else
 callsign="$cs"
fi

if (( force_manual == 1 )); then
 printf '\nPlease enter the requested information. All fields are required unless stated otherwise.\n\n'
 PromptEdit callsign "Callsign" 1
 PromptEdit lat "Latitude (-90..90)" 1
 PromptEdit lon "Longitude (-180..180)" 1

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
    ReadTTY -r -p " Enter latitude  (-90..90): " lat
    ReadTTY -r -p " Enter longitude (-180..180): " lon
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
fi

SetUnknownIfEmpty class expiry licstat forename surname street town state zip country
ReviewAndEdit
BuildFullName
BuildAddress

printf '\nIf you still see an immediate abort, the error above will tell us exactly what failed.\n'