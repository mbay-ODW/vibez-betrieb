#!/usr/bin/env bash
# Automatisches Ausrollen (Timer vibez-autodeploy.timer, alle 5 Minuten). Der Server holt selbst – GitHub hat keinen
# Zugang zum Server.
#   Produktion: höchste Versionsnummer x.y.z in GHCR > laufende Version  ->  stack/deploy.sh --auto <version>
#               (Digest festgeschrieben, Backup davor sofern eingerichtet, Rücksprung bei Fehler)
#   Testing:    Digest von :testing weicht vom laufenden ab  ->  stack-testing neu starten
# Meldung: Syslog (vibez-autodeploy) und optional ntfy (DEPLOY_NTFY_URL in stack/.env).
set -euo pipefail
exec 9>/run/vibez-autodeploy.lock; flock -n 9 || exit 0
REPO=mbay-odw/vibez-nachweise
S=/opt/vibez/stack; T=/opt/vibez/repo/stack-testing
ntfy="$(grep -E '^DEPLOY_NTFY_URL=' $S/.env | cut -d= -f2- || true)"
log() { logger -t vibez-autodeploy "$*"; echo "$*"; }
melde() { log "$1"; [[ -n "$ntfy" ]] && curl -fsS -m 10 -H "Title: VIBEZ Deploy" -d "$1" "$ntfy" >/dev/null || true; }

# Lesezugang zur Registry aus „docker login ghcr.io“ (nur read:packages)
basis="$(jq -r '.auths["ghcr.io"].auth // empty' /root/.docker/config.json | base64 -d)"
[[ -n "$basis" ]] || { log "kein GHCR-Login – nichts zu tun"; exit 1; }
token="$(curl -fsS -m 20 -u "$basis" "https://ghcr.io/token?service=ghcr.io&scope=repository:${REPO}:pull" | jq -r .token)"
reg() { curl -fsS -m 20 -H "Authorization: Bearer ${token}" "$@"; }
digest() {
  reg -o /dev/null -D - -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \
    "https://ghcr.io/v2/${REPO}/manifests/$1" | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}'
}

# --- Produktion
neueste="$(reg "https://ghcr.io/v2/${REPO}/tags/list?n=1000" | jq -r '.tags[]' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
laufend="$(grep -E '^VN_VERSION=' $S/.env | cut -d= -f2 | cut -d@ -f1)"
if [[ -n "$neueste" && "$neueste" != "$laufend" && "$(printf '%s\n%s\n' "$laufend" "$neueste" | sort -V | tail -1)" == "$neueste" ]]; then
  melde "Produktion: neue Version ${neueste} gefunden (läuft: ${laufend}) – rolle aus"
  if $S/deploy.sh --auto "$neueste" >/tmp/vibez-deploy.log 2>&1; then
    melde "Produktion: ${neueste} läuft ($(grep -oE 'sha256:[0-9a-f]{12}' /tmp/vibez-deploy.log | head -1)…)"
  else
    melde "Produktion: Ausrollen von ${neueste} FEHLGESCHLAGEN – $(tail -3 /tmp/vibez-deploy.log | tr '\n' ' ')"
  fi
fi

# --- Testing
soll="$(digest testing)"
ist="$(grep -E '^VN_TESTING_VERSION=' $T/.env | cut -d@ -f2)"
if [[ "$soll" =~ ^sha256:[0-9a-f]{64}$ && "$soll" != "$ist" ]]; then
  sed -i "s/^VN_TESTING_VERSION=.*/VN_TESTING_VERSION=testing@${soll}/" $T/.env
  cd $T && docker compose pull --quiet && docker compose up -d --remove-orphans >/dev/null 2>&1
  ok=0; for _ in $(seq 1 60); do
    docker exec vibez-testing-app python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=3).status==200 else 1)" 2>/dev/null && { ok=1; break; }
    sleep 3; done
  if [[ $ok == 1 ]]; then melde "Testing: ${soll:0:19}… läuft"; else melde "Testing: ${soll:0:19}… meldet sich nicht gesund"; fi
fi
