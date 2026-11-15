#!/usr/bin/env bash
# Atlas-IP-Zugriffsliste des Projekts auf genau die öffentliche IPv4 dieses Servers setzen (Atlas Admin API v2).
# Benötigt einen Programmatic API Key des Atlas-Projekts mit Rolle „Project IP Access List Admin“ – nur für diesen Zweck.
#   ATLAS_PUBLIC_KEY=… ATLAS_PRIVATE_KEY=… ATLAS_GROUP_ID=… ./atlas-zugriffsliste.sh
# Ohne Argument: zeigt die Liste. Mit „setzen“: trägt die Server-IP ein und entfernt alle anderen Einträge.
set -euo pipefail
: "${ATLAS_PUBLIC_KEY:?}" "${ATLAS_PRIVATE_KEY:?}" "${ATLAS_GROUP_ID:?}"
API="https://cloud.mongodb.com/api/atlas/v2/groups/${ATLAS_GROUP_ID}/accessList"
H=(-H "Accept: application/vnd.atlas.2023-01-01+json" -H "Content-Type: application/json")
auth=(--digest -u "${ATLAS_PUBLIC_KEY}:${ATLAS_PRIVATE_KEY}")

liste() { curl -fsS "${auth[@]}" "${H[@]}" "$API?itemsPerPage=100" | jq -r '.results[] | "\(.cidrBlock // .ipAddress)\t\(.comment // "")"'; }
if [[ "${1:-}" != "setzen" ]]; then liste; exit 0; fi

ip="$(curl -fsS -4 https://api.ipify.org)"
echo "Server-IP: $ip"
curl -fsS "${auth[@]}" "${H[@]}" -X POST "$API" -d "[{\"ipAddress\":\"${ip}\",\"comment\":\"vibez-prod (Hetzner)\"}]" >/dev/null
for eintrag in $(curl -fsS "${auth[@]}" "${H[@]}" "$API?itemsPerPage=100" | jq -r '.results[] | (.cidrBlock // .ipAddress)'); do
  if [[ "$eintrag" != "${ip}/32" && "$eintrag" != "$ip" ]]; then
    echo "entferne $eintrag"
    curl -fsS "${auth[@]}" "${H[@]}" -X DELETE "$API/$(printf '%s' "$eintrag" | jq -sRr @uri)" >/dev/null
  fi
done
liste
