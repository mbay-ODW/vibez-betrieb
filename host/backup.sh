#!/usr/bin/env bash
# Zweite, unabhängige Sicherung neben Atlas Cloud Backup:
# mongodump aus Atlas (Backup-Benutzer, nur lesen) -> restic (verschlüsselt auf dem Server) -> Hetzner Storage Box.
# Aufbewahrung: 7 tägliche, 5 wöchentliche, 12 monatliche Stände. Erfolg wird an Uptime Kuma gemeldet.
set -euo pipefail
ENV=/srv/vibez/secrets/vibez-nachweise-prod/backup.env
set -a; source "$ENV"; set +a

restic() {
  docker run --rm -i \
    -e RESTIC_REPOSITORY -e RESTIC_PASSWORD \
    -v /root/.ssh:/root/.ssh:ro -v /srv/vibez/restic-cache:/root/.cache/restic \
    "restic/restic:${RESTIC_VERSION}" "$@"
}

stempel="$(date +%F_%H%M)"
docker run --rm -e MONGODB_BACKUP_URI -v /srv/vibez/secrets/vibez-nachweise-prod/atlas-backup.pem:/certs/atlas-backup.pem:ro \
  "mongo:${MONGO_TOOLS_VERSION}" \
  sh -c 'mongodump --quiet --uri "$MONGODB_BACKUP_URI" --db vibez --archive --gzip' \
  | restic backup --quiet --stdin --stdin-filename "vibez-${stempel}.archive.gz" --tag mongodump

restic forget --quiet --tag mongodump --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --prune
# einmal pro Woche (sonntags) 10 % der Daten gegenlesen
if [[ "$(date +%u)" == "7" ]]; then restic check --read-data-subset=10% >/dev/null; fi

logger -t vibez-backup "backup ok ${stempel}"
[[ -n "${BACKUP_PING_URL:-}" ]] && curl -fsS -m 10 "${BACKUP_PING_URL}?status=up&msg=ok" >/dev/null || true
