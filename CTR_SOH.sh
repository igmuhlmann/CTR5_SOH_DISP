#!/usr/bin/env bash
# monitor_snmp.sh
# Linux/bash equivalent of the provided PowerShell SNMP monitor

set -euo pipefail

# === Configuration ===
SNMP_IP="192.168.178.88"
COMMUNITY="public"
CSV_FILE="CTR_SNMP_OID.csv"
OUT_FILE="CTR_SNMP_Output.txt"
INTERVAL_SECONDS=60
STATE_FILE=".snmp_state"   # persisted between runs

# require bash >= 4 for associative arrays
if (( BASH_VERSINFO[0] < 4 )); then
  echo "This script requires bash 4+"
  exit 1
fi

declare -A LAST_VALUE
declare -A LAST_CHANGED

# === helpers ===

# Get ISO 8601 timestamp, e.g. 2025-11-18T16:21:04+01:00
iso_now() {
  # date -Iseconds prints timezone offset like +01:00
  date -Iseconds
}

# load persisted state if exists
load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    while IFS='|' read -r var b64value ts; do
      # decode base64 safely; empty value allowed
      if [[ -n "$b64value" ]]; then
        value=$(echo "$b64value" | base64 --decode 2>/dev/null || printf "%s" "")
      else
        value=""
      fi
      LAST_VALUE["$var"]="$value"
      LAST_CHANGED["$var"]="$ts"
    done < "$STATE_FILE"
  fi
}

# save persisted state
save_state() {
  : > "$STATE_FILE"
  for var in "${!LAST_VALUE[@]}"; do
    # base64 encode the value so it can contain separators/newlines
    printf "%s|%s|%s\n" "$var" "$(printf "%s" "${LAST_VALUE[$var]}" | base64)" "${LAST_CHANGED[$var]}" >> "$STATE_FILE"
  done
}

# Run snmpget and return "raw" value (try -Oqv to get value only)
get_snmp_value() {
  local ip="$1"; local community="$2"; local oid="$3"
  # -v2c -c community; suppress stderr, but return empty on failure
  local res
  res=$(snmpget -v2c -c "$community" -Oqv "$ip" "$oid" 2>/dev/null) || res=""
  printf "%s" "$res"
}


# map some OIDs to human-readable states (mirrors your PowerShell switch statements)
map_oid_value() {
  local oid="$1"
  local value="$2"

  case "$oid" in
    ".1.3.6.1.4.1.58765.1.2.8.0") # nmxCentaurInstrumentState
      case "$value" in
        0) printf "0: ok" ;;
        1) printf "1: warning" ;;
        2) printf "2: error" ;;
        *) printf "%s" "$value" ;;
      esac
      ;;
    ".1.3.6.1.4.1.58765.1.2.4.0") # nmxCentaurCommitState
      case "$value" in
        0) printf "0: comitted" ;;
        1) printf "1: not committed" ;;
        *) printf "%s" "$value" ;;
      esac
      ;;
    ".1.3.6.1.4.1.58765.1.1.3.0") # nmxCentaurGnssState
      case "$value" in
        0) printf "0: off" ;;
        1) printf "1: unlocked" ;;
        2) printf "2: locked" ;;
        *) printf "%s" "$value" ;;
      esac
      ;;
    ".1.3.6.1.4.1.58765.1.1.1.0") # nmxCentaurTimingPLLState
      case "$value" in
        0) printf "0: noLock" ;;
        1) printf "1: coarseLock" ;;
        2) printf "2: fineLock" ;;
        3) printf "3: freeRunning" ;;
        *) printf "%s" "$value" ;;
      esac
      ;;
    ".1.3.6.1.4.1.58765.1.1.4.0") # nmxCentaurTimeState
      case "$value" in
        0) printf "0: timeOK" ;;
        1) printf "1: freeRunning" ;;
        2) printf "2: init" ;;
        3) printf "3: timeError" ;;
        4) printf "4: timeServerUnreachable" ;;
        5) printf "5: noAntenna" ;;
        *) printf "%s" "$value" ;;
      esac
      ;;
    ".1.3.6.1.4.1.58765.1.3.1.0"|".1.3.6.1.4.1.58765.1.3.2.0")
      case "$value" in
        0) printf "0: ok" ;;
        1) printf "1: warning" ;;
        2) printf "2: error" ;;
        *) printf "%s" "$value" ;;
      esac
      ;;
    ".1.3.6.1.4.1.58765.1.2.10.0")
      # firmware OID special handling done outside; here we pass value through
      printf "%s" "$value"
      ;;
    *)
      printf "%s" "$value"
      ;;
  esac
}

# === main ===

# Ensure CSV exists
if [[ ! -f "$CSV_FILE" ]]; then
  echo "CSV file not found: $CSV_FILE"
  exit 1
fi

# Ensure net-snmp snmpget is available
if ! command -v snmpget >/dev/null 2>&1; then
  echo "snmpget not found. Install net-snmp (e.g. 'sudo apt install snmp')"
  exit 1
fi

# Ensure base64 exists
if ! command -v base64 >/dev/null 2>&1; then
  echo "base64 utility not found. Install coreutils (usually available)."
  exit 1
fi

load_state

echo "Starting SNMP monitoring. Output -> $OUT_FILE"
echo "Press Ctrl+C to stop."

# main loop
while true; do
  output_lines=()

  # Read CSV: allow headerless CSV where each line has Variable,OID
  while IFS=',' read -r var oid; do
    # trim whitespace
    var=$(echo "$var" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    oid=$(echo "$oid" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$var" || -z "$oid" ]] && continue

    raw=$(get_snmp_value "$SNMP_IP" "$COMMUNITY" "$oid")

    if [[ -z "$raw" ]]; then
      value="ERROR"
    else
      value="$raw"

        # Firmware version OID: decode hex using xxd -r -p
        if [[ "$oid" == ".1.3.6.1.4.1.58765.1.2.10.0" ]]; then

          # 1) Extract hex pairs (safe even if raw contains text)
          hex=$(echo "$raw" | grep -oE '[0-9A-Fa-f]{2}')

          if [[ -n "$hex" ]]; then
                # 2) Convert hex → binary → ASCII
                ascii=$(echo "$hex" | tr -d '\n' | xxd -r -p 2>/dev/null)

                # 3) Cut at first NUL byte
                ascii_clean="${ascii%%$'\x00'*}"

                # 4) Use the cleaned ASCII as value
                value="$ascii_clean"
          else
                # Fallback
                value="$raw"
          fi
        fi

      # map some numeric states
      value=$(map_oid_value "$oid" "$value")
    fi

    # initialize state if missing
    if [[ -z "${LAST_VALUE[$var]+_}" ]]; then
      LAST_VALUE["$var"]="$value"
      LAST_CHANGED["$var"]="$(iso_now)"
    else
      if [[ "${LAST_VALUE[$var]}" != "$value" ]]; then
        LAST_VALUE["$var"]="$value"
        LAST_CHANGED["$var"]="$(iso_now)"
      fi
    fi

    timestamp="${LAST_CHANGED[$var]}"
    output_lines+=("$var, $value, $timestamp")

  done < "$CSV_FILE"

  # write output atomically
  {
    for l in "${output_lines[@]}"; do
      printf "%s\n" "$l"
    done
  } > "$OUT_FILE"

  save_state

  sleep "$INTERVAL_SECONDS"
done
