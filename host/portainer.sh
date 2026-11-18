# Hilfsfunktionen für Portainer-API und GHCR (wird von deploy.sh/autodeploy.sh/stacks-anlegen.sh per „source“ geladen).
# API-Schlüssel: /srv/vibez/secrets/portainer/api_token (nur root). Er wird per Umgebungsvariable an einen Wegwerf-
# Container im Netz fe-admin übergeben – nie als Kommandozeilen-Argument, nie ausgegeben.
PORTAINER=http://portainer:9000/api
ENDPOINT=1
REPO_IMAGE=mbay-odw/vibez-nachweise
SECRETS=/srv/vibez/secrets

pt() {   # pt <curl-Argumente…>  (Pfad relativ zu /api); Standardeingabe nur bei „--data-binary @-“ weiterreichen
  local ein=/dev/null; [[ " $* " == *" @- "* ]] && ein=/dev/stdin
  KEY="$(cat $SECRETS/portainer/api_token)" docker run --rm -i -e KEY --network fe-admin --entrypoint sh \
    curlimages/curl:8.11.0 -c 'exec curl -sS --fail-with-body -H "X-API-Key: $KEY" -H "Content-Type: application/json" "$@"' -- "$@" <"$ein"
}
stack_id()  { pt "$PORTAINER/stacks" | jq -r --arg n "$1" '.[] | select(.Name==$n) | .Id'; }
stack_var() { pt "$PORTAINER/stacks/$(stack_id "$1")" | jq -r --arg k "$2" '.Env[]? | select(.name==$k) | .value'; }

# Stack mit geänderten Variablen aus Git neu ausrollen: stack_redeploy <name> <VAR=wert>…
stack_redeploy() {
  local name="$1"; shift
  local id; id="$(stack_id "$name")"
  local env; env="$(pt "$PORTAINER/stacks/$id" | jq -c '.Env // []')"
  for kv in "$@"; do
    env="$(jq -c --arg k "${kv%%=*}" --arg v "${kv#*=}" '[.[] | select(.name!=$k)] + [{name:$k, value:$v}]' <<<"$env")"
  done
  jq -n --argjson env "$env" --rawfile pw $SECRETS/portainer/github_token \
    '{env:$env, prune:true, pullImage:true, repositoryReferenceName:"refs/heads/main",
      repositoryAuthentication:true, repositoryUsername:"x-access-token", repositoryPassword:($pw|rtrimstr("\n"))}' \
    | pt -X PUT "$PORTAINER/stacks/$id/git/redeploy?endpointId=$ENDPOINT" --data-binary @- \
    | jq -er '"redeploy " + .Name + " auf Commit " + .GitConfig.ConfigHash[0:7]' \
    || { echo "FEHLER: Redeploy von ${name} fehlgeschlagen" >&2; return 1; }
}

# GHCR (Lesezugang aus „docker login ghcr.io“)
ghcr_token() {
  local basis; basis="$(jq -r '.auths["ghcr.io"].auth // empty' /root/.docker/config.json | base64 -d)"
  curl -fsS -m 20 -u "$basis" "https://ghcr.io/token?service=ghcr.io&scope=repository:${REPO_IMAGE}:pull" | jq -r .token
}
ghcr_tags() { curl -fsS -m 20 -H "Authorization: Bearer $(ghcr_token)" "https://ghcr.io/v2/${REPO_IMAGE}/tags/list?n=1000" | jq -r '.tags[]'; }
ghcr_digest() {
  curl -fsS -m 20 -o /dev/null -D - -H "Authorization: Bearer $(ghcr_token)" \
    -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \
    "https://ghcr.io/v2/${REPO_IMAGE}/manifests/$1" | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}'
}
app_gesund() {   # app_gesund <container> [digest] – mit Digest erst, wenn der Container wirklich dieses Image hat
  for _ in $(seq 1 60); do
    if [[ -n "${2:-}" ]]; then
      local img; img="$(docker inspect -f '{{.Config.Image}} {{.State.Running}}' "$1" 2>/dev/null || true)"
      [[ "$img" == *"$2"*" true" ]] || { sleep 3; continue; }
    fi
    docker exec "$1" python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=3).status==200 else 1)" 2>/dev/null && return 0
    sleep 3
  done
  return 1
}
