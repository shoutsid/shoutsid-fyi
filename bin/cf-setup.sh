#!/usr/bin/env bash
#
# bin/cf-setup.sh — one-time provisioning of the Cloudflare edge for
# shoutsid.fyi.
#
# Creates (or reuses) a dedicated tunnel named after this site, points its
# remotely-managed ingress at the `web` service on the compose network, and
# creates the proxied DNS records for the apex and www. Idempotent: safe to
# re-run, and re-running is how you repair a record someone deleted.
#
# Usage:
#   CF_API_TOKEN=<token> bin/cf-setup.sh
#   CF_API_TOKEN=<token> bin/cf-setup.sh --dry-run
#
# Token scopes (a custom token, not the Global API Key):
#   Account   | Cloudflare Tunnel | Edit
#   Zone      | DNS               | Edit
#   Zone      | Zone              | Read
#
# Why a dedicated tunnel rather than a hostname on the existing `webcap`
# tunnel: webcap's tunnel is run from the host by its own cron watchdog, so
# joining it would make this site's uptime a function of that project's
# process. A tunnel per site means one site's watchdog cannot take the other
# down.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
API="https://api.cloudflare.com/client/v4"

CF_TOKEN="${CF_API_TOKEN:-${1:-}}"
DRY_RUN=0

for arg in "$@"; do
  [ "$arg" = "--dry-run" ] && DRY_RUN=1
done

log()  { printf '[cf-setup] %s\n' "$*"; }
fail() { printf '[cf-setup] FAIL: %s\n' "$*" >&2; exit 1; }
ok()   { printf '[cf-setup] OK: %s\n' "$*"; }

# ------------------------------------------------------------ configuration

CF_ZONE="${CF_ZONE:-shoutsid.fyi}"
CF_TUNNEL_NAME="${CF_TUNNEL_NAME:-shoutsid-fyi}"

# The apex plus www. Override with CF_HOSTS="shoutsid.fyi www.shoutsid.fyi" to
# serve something else; every hostname gets the same ingress.
CF_HOSTS="${CF_HOSTS:-$CF_ZONE www.$CF_ZONE}"

# Where cloudflared should send traffic. This is the compose *service* name and
# the container port, because the tunnel runs in the same compose network as
# the app — it never leaves the machine, so the origin is not on the public
# internet at any point.
CF_ORIGIN="${CF_ORIGIN:-http://web:3000}"

# ------------------------------------------------------------ preconditions

[ -n "$CF_TOKEN" ] || fail "no API token. Run: CF_API_TOKEN=<token> bin/cf-setup.sh"

for cmd in curl python3; do
  command -v "$cmd" >/dev/null 2>&1 || fail "missing required command: $cmd"
done

[ -f "$ENV_FILE" ] || fail "no .env — run 'bin/site setup' first"

auth=(-sS -m 25 -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json")

api() { # $1=METHOD $2=path [$3=json body]
  if [ $# -ge 3 ]; then
    curl "${auth[@]}" -X "$1" "$API$2" -d "$3"
  else
    curl "${auth[@]}" -X "$1" "$API$2"
  fi
}

# Cloudflare reports failures with HTTP 200 and success=false, so the body is
# the only reliable signal. Every call is checked rather than assuming a 2xx.
validate() { # $1=body $2=context
  local success errors
  success="$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("success", False))' 2>/dev/null || printf 'False')"
  if [ "$success" != "True" ]; then
    errors="$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("errors", [])))' 2>/dev/null || printf 'unparseable response')"
    fail "$2: $errors"
  fi
}

jget() { # $1=json $2=python expression over `d`
  printf '%s' "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); print($2)" 2>/dev/null || printf ''
}

# ------------------------------------------------------------------- token

log "verifying API token"
verify="$(api GET /user/tokens/verify)"
if [ "$(jget "$verify" 'd.get("success", False)')" != "True" ]; then
  # A zone-scoped token cannot call /user/tokens/verify. The zone lookup below
  # is the real test; a token that can read the zone is good enough.
  log "token verify endpoint unavailable (scoped token) — checking zone access instead"
fi

# -------------------------------------------------------------------- zone

log "resolving zone $CF_ZONE"
zone_resp="$(api GET "/zones?name=$CF_ZONE&per_page=1")"
validate "$zone_resp" "zone lookup"

ZONE_ID="$(jget "$zone_resp" 'd["result"][0]["id"] if d.get("result") else ""')"
[ -n "$ZONE_ID" ] || fail "zone $CF_ZONE not found on this account (is it delegated to Cloudflare?)"

ACCT_ID="$(jget "$zone_resp" 'd["result"][0].get("account", {}).get("id", "") if d.get("result") else ""')"
[ -n "$ACCT_ID" ] || fail "zone $CF_ZONE has no account id"
ok "zone $CF_ZONE -> $ZONE_ID (account $ACCT_ID)"

# ------------------------------------------------------------------ tunnel

log "finding or creating tunnel '$CF_TUNNEL_NAME'"
tunnels="$(api GET "/accounts/$ACCT_ID/cfd_tunnel?name=$CF_TUNNEL_NAME&is_deleted=false")"
validate "$tunnels" "tunnel lookup"

TUNNEL_ID="$(jget "$tunnels" 'd["result"][0]["id"] if d.get("result") else ""')"

if [ -z "$TUNNEL_ID" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] would create tunnel $CF_TUNNEL_NAME"
  else
    # The secret is generated here so the tunnel is created with a known
    # credential; 32 random bytes is what `cloudflared tunnel create` uses.
    secret="$(head -c 32 /dev/urandom | base64)"
    created="$(api POST "/accounts/$ACCT_ID/cfd_tunnel" \
      "$(python3 -c 'import json,sys; print(json.dumps({"name": sys.argv[1], "tunnel_secret": sys.argv[2]}))' "$CF_TUNNEL_NAME" "$secret")")"
    validate "$created" "tunnel create"
    TUNNEL_ID="$(jget "$created" 'd["result"]["id"]')"
    [ -n "$TUNNEL_ID" ] || fail "tunnel created but no id returned"
    ok "created tunnel $TUNNEL_ID"
  fi
else
  ok "reusing existing tunnel $TUNNEL_ID"
fi

# --------------------------------------------------------------- ingress

log "setting remotely-managed ingress for: $CF_HOSTS"
ingress_json="$(python3 - "$CF_HOSTS" "$CF_ORIGIN" <<'PY'
import json, sys

hosts = sys.argv[1].split()
origin = sys.argv[2]

rules = [{"hostname": host, "service": origin} for host in hosts]
# A remotely-managed tunnel config must end with a catch-all, or cloudflared
# refuses the configuration. It also keeps an unknown hostname from being
# forwarded anywhere.
rules.append({"service": "http_status:404"})

print(json.dumps({"config": {"ingress": rules}}))
PY
)"

if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] would PUT ingress: $ingress_json"
else
  [ -n "$TUNNEL_ID" ] || fail "no tunnel id; cannot set ingress"
  cfg="$(api PUT "/accounts/$ACCT_ID/cfd_tunnel/$TUNNEL_ID/configurations" "$ingress_json")"
  validate "$cfg" "ingress configuration"
  ok "ingress configured ($CF_HOSTS -> $CF_ORIGIN)"
fi

# ------------------------------------------------------------------- dns

log "creating DNS records"
for host in $CF_HOSTS; do
  # An existing record for the hostname is updated rather than duplicated: a
  # second CNAME on the same name is an error, and re-running this script has
  # to be safe.
  existing="$(api GET "/zones/$ZONE_ID/dns_records?name=$host&per_page=1")"
  validate "$existing" "dns lookup for $host"
  record_id="$(jget "$existing" 'd["result"][0]["id"] if d.get("result") else ""')"

  body="$(python3 -c 'import json,sys; print(json.dumps({"type": "CNAME", "name": sys.argv[1], "content": sys.argv[2], "proxied": True, "ttl": 1, "comment": "shoutsid-fyi portfolio tunnel"}))' "$host" "$TUNNEL_ID.cfargotunnel.com")"

  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] would $([ -n "$record_id" ] && echo update || echo create) $host -> $TUNNEL_ID.cfargotunnel.com"
    continue
  fi

  if [ -n "$record_id" ]; then
    res="$(api PUT "/zones/$ZONE_ID/dns_records/$record_id" "$body")"
    validate "$res" "dns update for $host"
    ok "updated CNAME $host"
  else
    res="$(api POST "/zones/$ZONE_ID/dns_records" "$body")"
    validate "$res" "dns create for $host"
    ok "created CNAME $host -> $TUNNEL_ID.cfargotunnel.com"
  fi
done

# ---------------------------------------------------------- tunnel token

log "fetching tunnel token"
TUNNEL_TOKEN=""
if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] would fetch token for tunnel $TUNNEL_ID"
else
  [ -n "$TUNNEL_ID" ] || fail "no tunnel id; cannot fetch token"
  token_resp="$(api GET "/accounts/$ACCT_ID/cfd_tunnel/$TUNNEL_ID/token")"
  validate "$token_resp" "tunnel token"
  TUNNEL_TOKEN="$(jget "$token_resp" 'd["result"]')"
  [ -n "$TUNNEL_TOKEN" ] || fail "tunnel token was empty"
fi

# ------------------------------------------------------------- write .env

if [ "$DRY_RUN" = "1" ]; then
  log "[dry-run] would write CF_TUNNEL_TOKEN into $ENV_FILE"
else
  # Replace the line if present, append it if not. `sed` in place keeps the
  # rest of the file (and its comments) exactly as it was.
  if grep -q '^CF_TUNNEL_TOKEN=' "$ENV_FILE"; then
    tmp="$(mktemp)"
    # The token contains no characters that are special to a plain s///.
    awk -v token="$TUNNEL_TOKEN" '
      /^CF_TUNNEL_TOKEN=/ { print "CF_TUNNEL_TOKEN=" token; next }
      { print }
    ' "$ENV_FILE" > "$tmp"
    cat "$tmp" > "$ENV_FILE"
    rm -f "$tmp"
  else
    printf 'CF_TUNNEL_TOKEN=%s\n' "$TUNNEL_TOKEN" >> "$ENV_FILE"
  fi
  chmod 600 "$ENV_FILE"
  ok "wrote CF_TUNNEL_TOKEN into .env (mode 600)"
fi

# ------------------------------------------------------------------ done

cat <<EOF

$(printf 'Cloudflare setup complete.')
  zone      $CF_ZONE
  tunnel    $CF_TUNNEL_NAME ($TUNNEL_ID)
  ingress   $(printf '%s' "$CF_HOSTS" | tr ' ' ', ') -> $CF_ORIGIN
  dns       proxied CNAME -> $TUNNEL_ID.cfargotunnel.com

Next:
  bin/site deploy                 # build, start the site and the tunnel, verify
  bin/site tunnel status          # inspect the tunnel container

Note: a newly created DNS record can take a few minutes to resolve. Apex
records are proxied through Cloudflare, so the certificate is issued
automatically and nothing needs renewing on this host.
EOF
