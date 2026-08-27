#!/usr/bin/env bash
# Create (or update) the OptScale bootstrap Secrets for a GitOps deployment.
#
# The chart can run with every credential coming from pre-existing Secrets
# (see "Bring your own secrets" in the chart README). Those Secrets live only
# in the cluster — never in git. This script produces them by rendering the
# chart in its default mode and applying ONLY the Secret objects:
#
#   mariadb-secret  mongo-secret  clickhouse-secret  rabbit-secret
#   minio-secret    cluster-secret  thanos-secret    optscale-config
#
# Usage:
#   Fresh install — mint random credentials and keep a copy of the values:
#     ./bootstrap-secrets.sh -n optscale --context mycluster \
#         --generate --out optscale-secret-values.yaml \
#         --app-file apps/optscale.yaml
#
#   Reapply / update from a saved values file:
#     ./bootstrap-secrets.sh -n optscale --context mycluster \
#         -f optscale-secret-values.yaml --app-file apps/optscale.yaml
#
#   Config-only change (edit the Argo Application values, then):
#     ./bootstrap-secrets.sh -n optscale --context mycluster \
#         -f optscale-secret-values.yaml --app-file apps/optscale.yaml
#     ...then sync the Argo app — the configurator hook re-runs on sync and
#     writes the new config into etcd.
#
# Flags:
#   -n, --namespace NS     target namespace (default: optscale)
#       --context CTX      kubectl/helm context (default: current context)
#   -f, --values FILE      values file, repeatable (helm layering order)
#       --app-file FILE    Argo CD Application YAML — its inline
#                          spec.source.helm.values are layered FIRST so the
#                          rendered optscale-config matches what Argo deploys
#                          (ingress host, toggles, ...)
#       --generate         mint random credentials (requires --out)
#       --out FILE         where --generate writes the secret values
#                          (chmod 600; store it in your password manager)
#       --dry-run          print the Secret manifests instead of applying
#   -h, --help
#
# IMPORTANT: the *-secret passwords are baked into the database volumes on
# first start. Changing them later on an existing installation requires
# changing the databases too — this script only updates the Secrets.
set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE=optscale
CONTEXT=""
GENERATE=false
DRY_RUN=false
OUT=""
APP_FILE=""
VALUES_ARGS=()

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--namespace) NAMESPACE="$2"; shift 2;;
    --context)      CONTEXT="$2"; shift 2;;
    -f|--values)    VALUES_ARGS+=(-f "$2"); shift 2;;
    --app-file)     APP_FILE="$2"; shift 2;;
    --generate)     GENERATE=true; shift;;
    --out)          OUT="$2"; shift 2;;
    --dry-run)      DRY_RUN=true; shift;;
    -h|--help)      usage;;
    *) echo "unknown flag: $1" >&2; usage 1;;
  esac
done

command -v helm >/dev/null || { echo "helm not found" >&2; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl not found" >&2; exit 1; }

KUBECTL=(kubectl); HELM_CTX=()
[ -n "$CONTEXT" ] && { KUBECTL+=(--context "$CONTEXT"); HELM_CTX+=(--kube-context "$CONTEXT"); }

TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

rand() { LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$1"; }

# Layer 1 (lowest): the Argo Application's inline helm values, so the
# rendered optscale-config agrees with the deployed configuration.
if [ -n "$APP_FILE" ]; then
  awk '
    /^[[:space:]]*values: \|/ { ind = index($0, "v"); grab = 1; next }
    grab {
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      cur = match($0, /[^ ]/)
      if (cur <= ind) exit
      print substr($0, ind + 2)
    }
  ' "$APP_FILE" > "$TMPDIR_LOCAL/app-values.yaml"
  [ -s "$TMPDIR_LOCAL/app-values.yaml" ] || { echo "no inline helm values found in $APP_FILE" >&2; exit 1; }
  VALUES_ARGS=(-f "$TMPDIR_LOCAL/app-values.yaml" "${VALUES_ARGS[@]+"${VALUES_ARGS[@]}"}")
fi

# Layer 2 (highest): generated credentials.
if $GENERATE; then
  [ -n "$OUT" ] || { echo "--generate requires --out FILE (you must keep these values)" >&2; exit 1; }
  umask 177
  cat > "$OUT" <<EOF
# OptScale bootstrap secret values — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
# KEEP THIS FILE SAFE (password manager / vault). It is the only copy of
# the credentials baked into the databases on first start.
config:
  secrets:
    cluster: $(rand 40)
  encryptionKey: $(rand 32)
  encryptionSalt: $(rand 24)
  encryptionSaltAuth: $(rand 24)
mariadb:
  rootPassword: $(rand 24)
mongo:
  password: $(rand 24)
  key: $(rand 40)
clickhouse:
  password: $(rand 24)
rabbitmq:
  password: $(rand 24)
  erlangCookie: $(rand 40)
minio:
  secretKey: $(rand 24)
EOF
  umask 022
  echo ">> wrote generated credentials to $OUT (mode 600) — store it safely" >&2
  VALUES_ARGS+=(-f "$OUT")
fi

[ ${#VALUES_ARGS[@]} -gt 0 ] || { echo "no values given: use -f/--generate/--app-file (see --help)" >&2; exit 1; }

# Render the chart in default mode (existingSecret flags cleared so the
# Secret objects are produced) and keep only the Secret documents.
helm template optscale "$CHART_DIR" --namespace "$NAMESPACE" \
  "${VALUES_ARGS[@]}" \
  --set configurator.existingConfigSecret= \
  --set config.secrets.existingSecret= \
  --set mariadb.existingSecret= \
  --set mongo.existingSecret= \
  --set clickhouse.existingSecret= \
  --set rabbitmq.existingSecret= \
  --set minio.existingSecret= \
  --set thanos.existingObjstoreSecret= \
  > "$TMPDIR_LOCAL/render.yaml"

awk '
  /^---$/ { if (buf ~ /(^|\n)kind: Secret(\n|$)/) printf "%s", buf; buf = "---\n"; next }
  { buf = buf $0 "\n" }
  END { if (buf ~ /(^|\n)kind: Secret(\n|$)/) printf "%s", buf }
' "$TMPDIR_LOCAL/render.yaml" > "$TMPDIR_LOCAL/secrets.yaml"

COUNT=$(grep -c '^kind: Secret$' "$TMPDIR_LOCAL/secrets.yaml" || true)
[ "$COUNT" -ge 7 ] || { echo "expected at least 7 Secrets, rendered $COUNT — aborting" >&2; exit 1; }

if $DRY_RUN; then
  cat "$TMPDIR_LOCAL/secrets.yaml"
  echo ">> dry run: $COUNT Secrets rendered for namespace $NAMESPACE (not applied)" >&2
  exit 0
fi

"${KUBECTL[@]}" get namespace "$NAMESPACE" >/dev/null 2>&1 \
  || "${KUBECTL[@]}" create namespace "$NAMESPACE"
"${KUBECTL[@]}" -n "$NAMESPACE" apply -f "$TMPDIR_LOCAL/secrets.yaml"
echo ">> applied $COUNT bootstrap Secrets to namespace $NAMESPACE" >&2
