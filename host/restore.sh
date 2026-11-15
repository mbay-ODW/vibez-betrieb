#!/usr/bin/env bash
# Wiederherstellen aus der zweiten Sicherung (restic auf der Storage Box).
# Erste Wahl bei Datenverlust ist das Atlas Cloud Backup (Atlas-Oberfläche, siehe Betriebshandbuch).
#   ./restore.sh                       verfügbare Stände anzeigen
#   ./restore.sh latest --test         neuesten Stand in eine Wegwerf-MongoDB auf dem Server einspielen und zählen (Monatsprobe)
#   ./restore.sh <snapshot-id> --datei Stand als Archiv nach /srv/vibez/restore/ schreiben (für Atlas-Import mit mongorestore)
set -euo pipefail
ENV=/opt/vibez/stack/.env
set -a; source "$ENV"; set +a
restic() {
  docker run --rm -i -e RESTIC_REPOSITORY -e RESTIC_PASSWORD \
    -v /root/.ssh:/root/.ssh:ro -v /srv/vibez/restic-cache:/root/.cache/restic \
    "restic/restic:${RESTIC_VERSION}" "$@"
}
snap="${1:-}"
if [[ -z "$snap" ]]; then restic snapshots --tag mongodump; exit 0; fi
datei="$(restic ls "$snap" --json | grep -o '"path":"/vibez-[^"]*"' | head -1 | cut -d'"' -f4)"
[[ -n "$datei" ]] || { echo "Keine Sicherung in $snap gefunden"; exit 1; }

case "${2:-}" in
  --test)
    name="vibez-restoretest-$$"
    docker run -d --rm --name "$name" --network none "mongo:${MONGO_TOOLS_VERSION}" >/dev/null
    trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
    for i in $(seq 1 30); do docker exec "$name" mongosh --quiet --eval 'db.adminCommand("ping").ok' >/dev/null 2>&1 && break; sleep 1; done
    restic dump "$snap" "$datei" | docker exec -i "$name" mongorestore --quiet --gzip --archive
    n=$(docker exec "$name" mongosh --quiet --eval 'db.getSiblingDB("vibez").nachweise.countDocuments()')
    r=$(docker exec "$name" mongosh --quiet --eval 'db.getSiblingDB("vibez").rechnungen.countDocuments()')
    echo "Restore-Test ok: ${n} Nachweise, ${r} Rechnungen (Stand ${datei})"
    logger -t vibez-backup "restore-test ok snapshot=${snap} nachweise=${n} rechnungen=${r}"
    ;;
  --datei)
    install -d -m 700 /srv/vibez/restore
    restic dump "$snap" "$datei" > "/srv/vibez/restore/$(basename "$datei")"
    chmod 600 "/srv/vibez/restore/$(basename "$datei")"
    echo "Geschrieben: /srv/vibez/restore/$(basename "$datei")"
    echo "Einspielen nach Atlas (App vorher stoppen, Admin-Benutzer nur für diesen Vorgang anlegen):"
    echo "  docker run --rm -i mongo:${MONGO_TOOLS_VERSION} mongorestore --uri 'mongodb+srv://ADMIN:PW@CLUSTER/' --gzip --archive --drop --nsInclude 'vibez.*' < DATEI"
    echo "Danach Datei löschen: shred -u /srv/vibez/restore/*"
    ;;
  *) echo "Option --test oder --datei angeben"; exit 1 ;;
esac
