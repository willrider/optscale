#!/usr/bin/env bash
# Generate a GitOps (Argo CD) deployment of OptScale from this repository:
#
#   <gitops-repo>/charts/optscale     vendored copy of this chart
#   <gitops-repo>/apps/<name>.yaml    Argo CD Application (app-of-apps style)
#
# The generated Application follows the no-secrets-in-git pattern: every
# credential is referenced from pre-existing bootstrap Secrets (create them
# with hack/bootstrap-secrets.sh), the configurator runs as an Argo CD
# Sync-phase hook, and the known Argo CD StatefulSet volumeClaimTemplates
# drift is ignored.
#
# Usage (defaults shown):
#   charts/optscale/hack/generate-gitops.sh --dest ~/git/my-gitops \
#     --repo-url git@github.com:me/my-gitops.git \
#     --host optscale.example.com
#
# Flags:
#   --dest DIR             gitops repository checkout to write into (required)
#   --repo-url URL         repoURL the Application syncs from (required)
#   --app-name NAME        Application/release name        (default: optscale)
#   --namespace NS         destination namespace           (default: optscale)
#   --chart-path PATH      chart path inside the gitops repo
#                                                  (default: charts/optscale)
#   --target-revision REV  branch/tag to sync from         (default: main)
#   --argocd-namespace NS  namespace Argo CD runs in       (default: argocd)
#   --host HOST            ingress hostname                (required)
#   --ingress-class NAME   ingress class                   (default: traefik)
#   --tls-secret NAME      ingress TLS secret              (default: defaultcert)
#   --issuer NAME          cert-manager issuer; empty disables cert-manager
#                          annotations                     (default: "")
#   --issuer-type TYPE     issuer | cluster-issuer  (default: cluster-issuer)
#   --proxy-url URL        ngui fallback proxy target — your ingress
#                          controller's in-cluster service
#                                        (default: http://traefik.kube-system)
#   --skip-vendor          only (re)write the Application manifest
#   -h, --help
#
# Regeneration is deterministic: rerunning with the same flags is a no-op,
# so chart updates in this repo flow to the gitops repo by rerunning the
# script and committing the diff.
set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEST="" REPO_URL="" APP_NAME=optscale NAMESPACE=optscale
CHART_PATH=charts/optscale TARGET_REVISION=main ARGOCD_NS=argocd
HOST="" INGRESS_CLASS=traefik TLS_SECRET=defaultcert
ISSUER="" ISSUER_TYPE=cluster-issuer PROXY_URL=http://traefik.kube-system
SKIP_VENDOR=false

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

CMDLINE=("$(basename "$0")" "$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --dest)             DEST="$2"; shift 2;;
    --repo-url)         REPO_URL="$2"; shift 2;;
    --app-name)         APP_NAME="$2"; shift 2;;
    --namespace)        NAMESPACE="$2"; shift 2;;
    --chart-path)       CHART_PATH="$2"; shift 2;;
    --target-revision)  TARGET_REVISION="$2"; shift 2;;
    --argocd-namespace) ARGOCD_NS="$2"; shift 2;;
    --host)             HOST="$2"; shift 2;;
    --ingress-class)    INGRESS_CLASS="$2"; shift 2;;
    --tls-secret)       TLS_SECRET="$2"; shift 2;;
    --issuer)           ISSUER="$2"; shift 2;;
    --issuer-type)      ISSUER_TYPE="$2"; shift 2;;
    --proxy-url)        PROXY_URL="$2"; shift 2;;
    --skip-vendor)      SKIP_VENDOR=true; shift;;
    -h|--help)          usage;;
    *) echo "unknown flag: $1" >&2; usage 1;;
  esac
done

[ -n "$DEST" ] || { echo "--dest is required" >&2; usage 1; }
[ -n "$REPO_URL" ] || { echo "--repo-url is required" >&2; usage 1; }
[ -n "$HOST" ] || { echo "--host is required" >&2; usage 1; }
[ -d "$DEST" ] || { echo "--dest $DEST is not a directory" >&2; exit 1; }
command -v helm >/dev/null || { echo "helm not found" >&2; exit 1; }

# ── vendor the chart ────────────────────────────────────────────────────────
if ! $SKIP_VENDOR; then
  mkdir -p "$DEST/$(dirname "$CHART_PATH")"
  rm -rf "${DEST:?}/$CHART_PATH"
  cp -R "$CHART_DIR" "$DEST/$CHART_PATH"
  echo ">> vendored chart -> $DEST/$CHART_PATH" >&2
fi

# ── build the inline helm values ────────────────────────────────────────────
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
{
  cat <<EOF
configurator:
  argocdHook: true
  existingConfigSecret: ${APP_NAME}-config
config:
  secrets:
    existingSecret: cluster-secret
mariadb:
  existingSecret: mariadb-secret
mongo:
  existingSecret: mongo-secret
clickhouse:
  existingSecret: clickhouse-secret
rabbitmq:
  existingSecret: rabbit-secret
minio:
  existingSecret: minio-secret
thanos:
  existingObjstoreSecret: thanos-secret
ingress:
  className: ${INGRESS_CLASS}
  host: ${HOST}
  tls:
    enabled: true
    secretName: ${TLS_SECRET}
EOF
  if [ -n "$ISSUER" ]; then
    cat <<EOF
    certManager:
      enabled: true
      issuerType: ${ISSUER_TYPE}
      issuer: ${ISSUER}
EOF
  fi
  cat <<EOF
ngui:
  proxyUrl: ${PROXY_URL}
EOF
} > "$TMP/values.yaml"

# ── validate: the vendored chart must render with these values ──────────────
helm lint "$DEST/$CHART_PATH" > /dev/null
helm template "$APP_NAME" "$DEST/$CHART_PATH" --namespace "$NAMESPACE" \
  -f "$TMP/values.yaml" > /dev/null
echo ">> chart lints and renders with the generated values" >&2

# ── write the Application manifest ──────────────────────────────────────────
mkdir -p "$DEST/apps"
APP_FILE="$DEST/apps/${APP_NAME}.yaml"
{
  cat <<EOF
# OptScale (Hystax FinOps platform) — full stack in the \`${NAMESPACE}\`
# namespace, deployed from the chart vendored at ${CHART_PATH} (source:
# github.com/hystax/optscale; see the chart README).
#
# Generated by ${CHART_PATH}/hack/generate-gitops.sh — regenerate with:
#   ${CMDLINE[@]}
#
# Secrets are NOT in git: the chart runs with existingSecret references to
# bootstrap Secrets that live only in the cluster: mariadb-secret,
# mongo-secret, clickhouse-secret, rabbit-secret, minio-secret,
# cluster-secret, thanos-secret and ${APP_NAME}-config (the full
# configurator YAML). Create or update them with:
#   ${CHART_PATH}/hack/bootstrap-secrets.sh -n ${NAMESPACE} \\
#     -f <secret-values file> --app-file apps/${APP_NAME}.yaml
# (use --generate --out <file> on a fresh install and keep that file in a
# password manager — the passwords are baked into the databases on first
# start). After changing configuration here, re-run bootstrap-secrets.sh
# and sync this app: the configurator hook re-runs on every sync and
# writes the new config into etcd.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: ${ARGOCD_NS}
  finalizers: [resources-finalizer.argocd.argoproj.io]
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: ${TARGET_REVISION}
    path: ${CHART_PATH}
    helm:
      releaseName: ${APP_NAME}
      values: |
EOF
  sed 's/^/        /' "$TMP/values.yaml"
  cat <<EOF
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  # The API server defaults apiVersion/kind/volumeMode/status inside
  # volumeClaimTemplates, which server-side diffing reports as permanent
  # drift on every StatefulSet.
  ignoreDifferences:
    - group: apps
      kind: StatefulSet
      jqPathExpressions:
        - .spec.volumeClaimTemplates[]?.apiVersion
        - .spec.volumeClaimTemplates[]?.kind
        - .spec.volumeClaimTemplates[]?.spec.volumeMode
        - .spec.volumeClaimTemplates[]?.status
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - RespectIgnoreDifferences=true
EOF
} > "$APP_FILE"
echo ">> wrote $APP_FILE" >&2

cat >&2 <<EOF

Next steps:
  1. Create the bootstrap Secrets (fresh install only):
       $CHART_PATH/hack/bootstrap-secrets.sh -n $NAMESPACE \\
         --generate --out <secret-values file> --app-file apps/${APP_NAME}.yaml
  2. Review the diff in $DEST, commit and push.
  3. Ensure your app-of-apps picks up apps/${APP_NAME}.yaml (or kubectl apply it once).
EOF
