#!/usr/bin/env bash
# Sends ONE command to the VPS deploy gateway over SSH, with limited retries that can only
# happen BEFORE anything runs on the VPS.
#
#   Phase 1 — connection only: `ssh -M -N -f` does TCP + host key check + public-key auth and
#             opens no session, so the gateway is NOT executed. Retried (max RETRY_MAX, every
#             RETRY_DELAY s) only for network-level errors; auth/host-key/unknown errors stop.
#   Phase 2 — the gateway command runs exactly once over the authenticated master connection.
#             Its result is final: never retried (a remote result may be unknown).
#
# Env: KEY, KNOWN, HOST (required); RETRY_MAX=3 RETRY_DELAY=20 CONNECT_TIMEOUT=30 SSH_PORT=22.
# Usage: vps-gateway.sh status | rollback | deploy <tag> <sha256:digest>
set -euo pipefail
cmd="$*"
[[ "$cmd" =~ ^(status|rollback|deploy\ [0-9a-f]{7,40}\ sha256:[0-9a-f]{64})$ ]] || { echo "vps-gateway: invalid command"; exit 2; }
: "${KEY:?}" "${KNOWN:?}" "${HOST:?}"
max=${RETRY_MAX:-3} delay=${RETRY_DELAY:-20} ct=${CONNECT_TIMEOUT:-30} port=${SSH_PORT:-22}
log() { echo "vps-gateway: $*"; [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "- $*" >> "$GITHUB_STEP_SUMMARY"; return 0; }

umask 077
d=$(mktemp -d)
cleanup() { ssh -o ControlPath="$d/cm" -O exit "deployer@$HOST" >/dev/null 2>&1 || true; rm -rf "$d"; }
trap cleanup EXIT
printf '%s\n' "$KEY" > "$d/key"
printf '%s\n' "$KNOWN" > "$d/known_hosts"
opts=(-p "$port" -i "$d/key" -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes
      -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$d/known_hosts" -o ConnectTimeout="$ct"
      -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ControlPath="$d/cm")

# Network-level failures that happen before authentication: safe to retry.
retryable='Connection timed out|Operation timed out|Connection refused|No route to host|Network is unreachable|kex_exchange_identification|Connection reset by peer|Connection closed by .* port [0-9]+$'
# Never retry these (credential, host identity, or policy problems).
fatal='Permission denied|Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED|No .*host key is known|Too many authentication failures|Could not resolve hostname'

attempt=1
while :; do
  if ssh "${opts[@]}" -o ControlMaster=yes -o ControlPersist=300 -N -f "deployer@$HOST" 2> "$d/err"; then
    log "connection established on attempt $attempt/$max (no command sent yet)"
    break
  fi
  msg=$(grep -v '^Warning: Permanently added' "$d/err" | tail -n 1 | sed -E 's/[[:cntrl:]]//g' | cut -c1-200)
  if grep -qE "$fatal" <<<"$msg"; then log "attempt $attempt: '$msg' — not retryable"; exit 255; fi
  if ! grep -qE "$retryable" <<<"$msg"; then log "attempt $attempt: '$msg' — unknown error, not retrying"; exit 255; fi
  if [ "$attempt" -ge "$max" ]; then log "attempt $attempt: '$msg' — giving up after $max attempts"; exit 255; fi
  log "attempt $attempt: '$msg' — retrying in ${delay}s"
  sleep "$delay"; attempt=$((attempt + 1))
done

# Phase 2: exactly once.
set +e
ssh "${opts[@]}" -o ControlMaster=no "deployer@$HOST" "$cmd"
rc=$?
set -e
log "gateway command '${cmd%% *}' finished with exit $rc (not retried)"
exit "$rc"
