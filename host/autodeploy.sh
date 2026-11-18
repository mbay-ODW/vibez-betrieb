#!/usr/bin/env bash
# Automatisches Ausrollen (vibez-autodeploy.timer, alle 5 Minuten). Der Server holt selbst – GitHub hat keinen Zugang.
#   0. Betriebs-Repo aktualisieren (Konfigurationsdateien für Traefik, Authelia, cloudflared)
#   1. Produktion: höchste Versionsnummer x.y.z in GHCR > laufende  ->  host/deploy.sh --auto prod <version>
#   2. Testing:    Digest von :testing weicht ab                     ->  host/deploy.sh --auto testing testing
# Meldung: Syslog (vibez-autodeploy) und optional ntfy (DEPLOY_NTFY_URL in /srv/vibez/secrets/autodeploy.env).
set -euo pipefail
exec 9>/run/vibez-autodeploy.lock; flock -n 9 || exit 0
source /opt/vibez/host/portainer.sh
ntfy="$(grep -sE '^DEPLOY_NTFY_URL=' $SECRETS/autodeploy.env | cut -d= -f2- || true)"
log()   { logger -t vibez-autodeploy "$*"; echo "$*"; }
melde() { log "$1"; [[ -n "$ntfy" ]] && curl -fsS -m 10 -H "Title: VIBEZ Deploy" -d "$1" "$ntfy" >/dev/null || true; }

git -C /opt/vibez/repo pull -q --ff-only 2>/dev/null || log "git pull fehlgeschlagen (Konfiguration bleibt beim alten Stand)"

laufend="$(stack_var vibez-nachweise-prod VN_VERSION | cut -d@ -f1)"
neueste="$(ghcr_tags | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
if [[ -n "$neueste" && "$neueste" != "$laufend" && "$(printf '%s\n%s\n' "$laufend" "$neueste" | sort -V | tail -1)" == "$neueste" ]]; then
  melde "Produktion: neue Version ${neueste} (läuft: ${laufend}) – rolle aus"
  if /opt/vibez/host/deploy.sh --auto prod "$neueste" >/tmp/vibez-deploy.log 2>&1; then melde "Produktion: ${neueste} läuft"
  else melde "Produktion: ${neueste} FEHLGESCHLAGEN – $(tail -3 /tmp/vibez-deploy.log | tr '\n' ' ')"; fi
fi

soll="$(ghcr_digest testing)"
ist="$(stack_var vibez-nachweise-testing VN_VERSION | cut -d@ -f2)"
if [[ "$soll" =~ ^sha256:[0-9a-f]{64}$ && "$soll" != "$ist" ]]; then
  if /opt/vibez/host/deploy.sh --auto testing testing >/tmp/vibez-deploy-testing.log 2>&1; then melde "Testing: ${soll:0:19}… läuft"
  else melde "Testing: ${soll:0:19}… FEHLGESCHLAGEN – $(tail -2 /tmp/vibez-deploy-testing.log | tr '\n' ' ')"; fi
fi
