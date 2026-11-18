#!/usr/bin/env bash
# Version der App setzen und ausrollen – mit Backup davor, Health-Check danach und Rücksprung bei Fehler.
#   ./deploy.sh 0.3.1          neue Version einspielen (Digest wird ermittelt, angezeigt und bestätigt)
#   ./deploy.sh --auto 0.3.1   dasselbe ohne Rückfrage (host/autodeploy.sh); Digest wird protokolliert
#   ./deploy.sh                aktuelle Version neu starten (z. B. nach Änderung an .env)
# Rückweg von Hand: ./deploy.sh <vorherige Version>  (Datenbank-Migrationen sind vorwärts gerichtet – Betriebshandbuch)
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
[[ -f .env ]] || { echo "Fehlt: .env (Vorlage .env.example)"; exit 1; }

auto=0
[[ "${1:-}" == "--auto" ]] && { auto=1; shift; }
neu="${1:-}"
alt="$(grep -E '^VN_VERSION=' .env | cut -d= -f2)"
wer="${SUDO_USER:-${USER:-root}}"; [[ $auto == 1 ]] && wer="autodeploy"

gesund() {
  for _ in $(seq 1 45); do
    if docker exec vibez-app python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=3).status==200 else 1)" 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

if [[ -n "$neu" && "$neu" != "${alt%%@*}" ]]; then
  [[ "$neu" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version im Format 1.2.3 angeben"; exit 1; }
  # Digest festschreiben: das Tag allein könnte (bei kompromittiertem Registry-Konto) ausgetauscht werden
  digest="$(docker buildx imagetools inspect "ghcr.io/mbay-odw/vibez-nachweise:${neu}" --format '{{json .Manifest.Digest}}' | tr -d '"')"
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "Digest für ${neu} nicht ermittelbar"; exit 1; }
  echo "Digest ${neu}: ${digest}"
  if [[ $auto == 0 ]]; then
    echo "Bitte mit dem CI-Lauf auf GitHub vergleichen."
    read -r -p "Stimmt der Digest? Tippe JA: " ok; [[ "$ok" == "JA" ]] || exit 1
  fi
  neu="${neu}@${digest}"
  if grep -qE '^RESTIC_REPOSITORY=.+' .env; then
    echo "Backup vor dem Update …"
    /opt/vibez/host/backup.sh
  else
    echo "WARNUNG: restic ist nicht eingerichtet – Update ohne Backup (nur zulässig, solange keine echten Daten existieren)"
    logger -t vibez-deploy "WARNUNG update ohne backup ${alt} -> ${neu}"
  fi
  sed -i "s/^VN_VERSION=.*/VN_VERSION=${neu}/" .env
  echo "Version ${alt} -> ${neu}"
fi

docker compose pull --quiet
docker compose up -d --remove-orphans

echo -n "Warte auf die App … "
if gesund; then
  v="$(grep -E '^VN_VERSION=' .env | cut -d= -f2)"
  echo "läuft (Version ${v})."
  logger -t vibez-deploy "deploy ok version=${v} by=${wer}"
  exit 0
fi
echo "FEHLER: App meldet sich nicht gesund."
if [[ -n "$neu" && "$neu" != "$alt" ]]; then
  echo "Rücksprung auf ${alt} …"
  sed -i "s/^VN_VERSION=.*/VN_VERSION=${alt}/" .env
  docker compose up -d --remove-orphans
  gesund && echo "Vorige Version läuft wieder." || echo "ACHTUNG: auch die vorige Version ist nicht gesund."
  logger -t vibez-deploy "deploy FEHLGESCHLAGEN ${neu} – zurück auf ${alt} by=${wer}"
fi
echo "Logs: docker logs --tail 100 vibez-app"
exit 1
