#!/usr/bin/env bash
# App-Version ausrollen (Portainer-Stack per API) – Digest festschreiben, Backup davor (Prod), Health-Check, Rücksprung.
#   sudo host/deploy.sh prod 0.3.2           Produktion: Nummer aus VERSION (Digest wird gezeigt und bestätigt)
#   sudo host/deploy.sh testing testing      Testumgebung: Tag „testing“ (aktueller Digest)
#   … --auto …                               ohne Rückfrage (host/autodeploy.sh)
set -euo pipefail
source /opt/vibez/host/portainer.sh
auto=0; [[ "${1:-}" == "--auto" ]] && { auto=1; shift; }
umg="${1:?prod|testing}"; tag="${2:?Version bzw. testing}"
case "$umg" in
  prod)    stack=vibez-nachweise-prod;    app=vibez-app
           [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Produktion nur mit Versionsnummer 1.2.3"; exit 1; } ;;
  testing) stack=vibez-nachweise-testing; app=vibez-testing-app ;;
  *) echo "prod oder testing"; exit 1 ;;
esac
wer="${SUDO_USER:-${USER:-root}}"; [[ $auto == 1 ]] && wer=autodeploy
alt="$(stack_var "$stack" VN_VERSION)"
digest="$(ghcr_digest "$tag")"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "Digest für ${tag} nicht ermittelbar"; exit 1; }
neu="${tag}@${digest}"
[[ "$neu" == "$alt" ]] && { echo "${stack}: ${neu} läuft schon"; exit 0; }
echo "${stack}: ${alt:-–} -> ${neu}"
if [[ $auto == 0 ]]; then
  echo "Digest bitte mit dem CI-Lauf auf GitHub vergleichen."
  read -r -p "Stimmt der Digest? Tippe JA: " ok; [[ "$ok" == "JA" ]] || exit 1
fi
if [[ $umg == prod ]]; then
  if grep -qE '^RESTIC_REPOSITORY=.+' $SECRETS/vibez-nachweise-prod/backup.env 2>/dev/null; then
    echo "Backup vor dem Update …"; /opt/vibez/host/backup.sh
  else
    echo "WARNUNG: restic ist nicht eingerichtet – Update ohne Backup (nur zulässig, solange keine echten Daten existieren)"
    logger -t vibez-deploy "WARNUNG update ohne backup ${stack} ${alt} -> ${neu}"
  fi
fi
stack_redeploy "$stack" "VN_VERSION=${neu}"
if app_gesund "$app"; then
  echo "${stack}: ${neu} läuft."; logger -t vibez-deploy "deploy ok ${stack} ${neu} by=${wer}"; exit 0
fi
echo "FEHLER: ${app} meldet sich nicht gesund."
if [[ -n "$alt" ]]; then
  echo "Rücksprung auf ${alt} …"; stack_redeploy "$stack" "VN_VERSION=${alt}"
  app_gesund "$app" && echo "Vorige Version läuft wieder." || echo "ACHTUNG: auch die vorige Version ist nicht gesund."
fi
logger -t vibez-deploy "deploy FEHLGESCHLAGEN ${stack} ${neu} – zurück auf ${alt} by=${wer}"
exit 1
