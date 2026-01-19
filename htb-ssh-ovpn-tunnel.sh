#!/usr/bin/env bash
set -euo pipefail

# =========================
# htb-ssh-ovpn-tunnel.sh
# =========================
# Requirements: bash, sed, awk, grep, dirname, realpath (or readlink -f)
#
# Usage examples:
#   ./htb-ssh-ovpn-tunnel.sh --ovpn htb.ovpn --lport 1443 --ip 72.56.78.157 --user root
#   ./htb-ssh-ovpn-tunnel.sh --ovpn htb.ovpn --lport 1443 --ip 72.56.78.157 --user root --key aeza.key
#   ./htb-ssh-ovpn-tunnel.sh --ovpn htb.ovpn --lport 1443 --ip 72.56.78.157 --user root --htb edge-eu-free-5.hackthebox.eu

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

OVPN=""
LPORT=""
EXT_IP=""
EXT_USER=""
KEY_FILE=""     # optional, name or path. If just name -> must exist in script dir.
HTB_HOST=""     # optional, can be extracted from ovpn remote line

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Usage:
  htb-ssh-ovpn-tunnel.sh --ovpn <file.ovpn> --lport <local_port> --ip <external_host_ip> --user <ssh_user> [--key <keyfile.key>] [--htb <htb_hostname>]

Arguments:
  --ovpn   Path to .ovpn config (required)
  --lport  Local port for SSH -L (required)
  --ip     External host IP (required)
  --user   SSH user on external host (required)
  --key    SSH private key filename or path (optional). If it's just a filename, it must sit next to this script.
  --htb    HTB server hostname (optional). If omitted, extracted from first 'remote <host> <port>' line in ovpn.

Behavior:
  - Creates patched ovpn рядом с исходным: <name>.patched.ovpn
  - Replaces first 'remote ...' with 'remote 127.0.0.1 <lport>'
  - Replaces/sets proto to 'proto tcp-client'
  - Starts SSH tunnel:
      sudo ssh -v -N -L <lport>:<htb_host>:443 [-i <key>] <user>@<ip>
EOF
  exit 2
}

# ---- parse args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ovpn) OVPN="${2:-}"; shift 2;;
    --lport) LPORT="${2:-}"; shift 2;;
    --ip) EXT_IP="${2:-}"; shift 2;;
    --user) EXT_USER="${2:-}"; shift 2;;
    --key) KEY_FILE="${2:-}"; shift 2;;
    --htb) HTB_HOST="${2:-}"; shift 2;;
    -h|--help) usage;;
    *) die "Unknown argument: $1 (use --help)";;
  esac
done

[[ -n "$OVPN" ]] || usage
[[ -n "$LPORT" ]] || usage
[[ -n "$EXT_IP" ]] || usage
[[ -n "$EXT_USER" ]] || usage

[[ -f "$OVPN" ]] || die "OVPN file not found: $OVPN"
[[ "$LPORT" =~ ^[0-9]+$ ]] || die "--lport must be a number"
(( LPORT >= 1 && LPORT <= 65535 )) || die "--lport must be 1..65535"

# ---- resolve HTB host from ovpn if not provided ----
if [[ -z "$HTB_HOST" ]]; then
  # take first 'remote <host> <port>' line that is not commented
  HTB_HOST="$(grep -E '^[[:space:]]*remote[[:space:]]+' "$OVPN" | grep -Ev '^[[:space:]]*;' | head -n 1 | awk '{print $2}')"
  [[ -n "$HTB_HOST" ]] || die "Could not extract HTB host from ovpn (no 'remote ...' found). Provide --htb explicitly."
fi

# ---- locate key file if provided ----
KEY_ARG=()
if [[ -n "$KEY_FILE" ]]; then
  # If it's an absolute or relative path to existing file, use it.
  if [[ -f "$KEY_FILE" ]]; then
    KEY_PATH="$KEY_FILE"
  else
    # else expect it next to script
    KEY_PATH="$SCRIPT_DIR/$KEY_FILE"
    [[ -f "$KEY_PATH" ]] || die "Key file not found: '$KEY_FILE' (also tried '$KEY_PATH')"
  fi
  KEY_ARG=(-i "$KEY_PATH")
fi

# ---- patch ovpn file ----
OVPN_ABS="$OVPN"
# attempt to make absolute path for nicer output, but don't fail if realpath missing
if command -v realpath >/dev/null 2>&1; then
  OVPN_ABS="$(realpath "$OVPN")"
elif command -v readlink >/dev/null 2>&1; then
  OVPN_ABS="$(readlink -f "$OVPN" 2>/dev/null || echo "$OVPN")"
fi

OVPN_DIR="$(dirname "$OVPN_ABS")"
OVPN_BASE="$(basename "$OVPN_ABS")"
OVPN_NAME="${OVPN_BASE%.*}"
PATCHED_OVPN="$OVPN_DIR/${OVPN_NAME}.patched.ovpn"

# 1) Replace first remote line with local endpoint
# 2) Replace any proto line with 'proto tcp-client'; if none exists, insert after 'dev' (or after 'client')
awk -v lport="$LPORT" '
BEGIN { remote_done=0; proto_found=0; inserted_proto=0; }
{
  line=$0

  # Replace first "remote ..."
  if (!remote_done && match(line, /^[[:space:]]*remote[[:space:]]+/)) {
    print "remote 127.0.0.1 " lport
    remote_done=1
    next
  }

  # Replace proto line
  if (match(line, /^[[:space:]]*proto[[:space:]]+/)) {
    print "proto tcp-client"
    proto_found=1
    next
  }

  print line

  # If no proto line exists, we will insert later (after dev or client)
}
END { }
' "$OVPN_ABS" > "$PATCHED_OVPN.tmp"

# If no proto line existed, insert it in a sensible place.
if ! grep -Eq '^[[:space:]]*proto[[:space:]]+' "$OVPN_ABS"; then
  awk '
  BEGIN { done=0 }
  {
    print
    if (!done && ($0 ~ /^[[:space:]]*dev[[:space:]]+/ || $0 ~ /^[[:space:]]*client[[:space:]]*$/)) {
      # insert once after first dev/client line
      print "proto tcp-client"
      done=1
    }
  }
  END {
    if (!done) {
      print "proto tcp-client"
    }
  }
  ' "$PATCHED_OVPN.tmp" > "$PATCHED_OVPN"
  rm -f "$PATCHED_OVPN.tmp"
else
  mv -f "$PATCHED_OVPN.tmp" "$PATCHED_OVPN"
fi

echo "HTB host:           $HTB_HOST"
echo "External SSH host:  $EXT_USER@$EXT_IP"
echo "Local forward port: $LPORT"
echo "Patched OVPN:       $PATCHED_OVPN"
echo

echo "Starting SSH tunnel (Ctrl+C to stop)..."
echo "Command:"
echo "  sudo ssh -v -N -L ${LPORT}:${HTB_HOST}:443 ${KEY_ARG[*]} ${EXT_USER}@${EXT_IP}"
echo

# ---- run tunnel ----
sudo ssh -v -N -L "${LPORT}:${HTB_HOST}:443" "${KEY_ARG[@]}" "${EXT_USER}@${EXT_IP}"
