#!/usr/bin/env bash
# Version der App setzen und ausrollen – mit Backup davor und Health-Check danach.
#   ./deploy.sh 0.2.5        neue Version einspielen (Digest wird ermittelt und mit festgeschrieben)
#   ./deploy.sh              aktuelle Version neu starten (z. B. nach Änderung an .env)
# Rückweg: ./deploy.sh <vorherige Version>  (Datenbank-Migrationen sind vorwärts gerichtet – siehe Betriebshandbuch)
set -euo pipefail
cd "$(dirname "$0")"
[[ -f .env ]] || { echo "Fehlt: .env (Vorlage .env.example)"; exit 1; }

neu="${1:-}"
alt="$(grep -E '^VN_VERSION=' .env | cut -d= -f2)"
if [[ -n "$neu" && "$neu" != "${alt%%@*}" ]]; then
  [[ "$neu" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version im Format 1.2.3 angeben"; exit 1; }
  # Digest festschreiben: das Tag allein könnte (bei kompromittiertem Registry-Konto) ausgetauscht werden
  digest="$(docker buildx imagetools inspect "ghcr.io/mbay-odw/vibez-nachweise:${neu}" --format '{{json .Manifest.Digest}}' | tr -d '"')"
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "Digest für ${neu} nicht ermittelbar"; exit 1; }
  echo "Digest ${neu}: ${digest} – bitte mit dem CI-Lauf auf GitHub vergleichen."
  read -r -p "Stimmt der Digest? Tippe JA: " ok; [[ "$ok" == "JA" ]] || exit 1
  neu="${neu}@${digest}"
  echo "Backup vor dem Update …"
  /opt/vibez/host/backup.sh
  sed -i "s/^VN_VERSION=.*/VN_VERSION=${neu}/" .env
  echo "Version ${alt} -> ${neu}"
fi

docker compose pull --quiet
docker compose up -d --remove-orphans

echo -n "Warte auf die App "
for i in $(seq 1 30); do
  if docker exec vibez-app python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=3).status==200 else 1)" 2>/dev/null; then
    echo " – läuft (Version $(grep -E '^VN_VERSION=' .env | cut -d= -f2))."
    logger -t vibez-deploy "deploy ok version=$(grep -E '^VN_VERSION=' .env | cut -d= -f2) by=${SUDO_USER:-$USER}"
    exit 0
  fi
  echo -n "."; sleep 2
done
echo; echo "FEHLER: App meldet sich nicht gesund. Logs: docker logs --tail 100 vibez-app"
exit 1
