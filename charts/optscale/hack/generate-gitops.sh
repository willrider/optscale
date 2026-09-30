#!/usr/bin/env bash
# Generate a GitOps (Argo CD) deployment of OptScale from this repository:
#
#   <gitops-repo>/charts/optscale      vendored copy of this chart
#   <gitops-repo>/apps/<name>.yaml     Argo CD Application (generated — do
#                                      not edit, rerun this script instead)
#   <gitops-repo>/values/<name>.yaml   your OptScale configuration (created
#                                      once with examples, never overwritten)
#
# Configuration model of the generated deployment:
#   - non-secret settings: edit values/<name>.yaml, commit, push — Argo CD
#     syncs and the configurator hook writes them into etcd;
#   - credentials: generated in-cluster by the chart's secrets-init hook on
#     first sync, never stored in git;
#   - secret settings (SMTP password, cloud credentials, Stripe keys, ...):
#     the optional Secret `optscale-secret-config` (key etcd.yaml), managed
#     outside git (kubectl, External Secrets, ...).
#
# Usage:
#   charts/optscale/hack/generate-gitops.sh --dest ~/git/my-gitops \
#     --repo-url git@github.com:me/my-gitops.git \
#     --host optscale.example.com
#
# Flags:
#   --dest DIR             gitops repository checkout to write into (required)
#   --repo-url URL         repoURL the Application syncs from (required)
#   --host HOST            ingress hostname                (required)
#   --app-name NAME        Application/release name        (default: optscale)
#   --namespace NS         destination namespace           (default: optscale)
#   --chart-path PATH      chart path inside the gitops repo
#                                                  (default: charts/optscale)
#   --values-path PATH     user values file inside the gitops repo
#                                          (default: values/<app-name>.yaml)
#   --target-revision REV  branch/tag to sync from         (default: main)
#   --argocd-namespace NS  namespace Argo CD runs in       (default: argocd)
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
# Deterministic: rerunning with the same flags is a no-op, so chart updates
# flow to the gitops repo by rerunning the script and committing the diff.
set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEST="" REPO_URL="" APP_NAME=optscale NAMESPACE=optscale
CHART_PATH=charts/optscale VALUES_PATH="" TARGET_REVISION=main ARGOCD_NS=argocd
HOST="" INGRESS_CLASS=traefik TLS_SECRET=defaultcert
ISSUER="" ISSUER_TYPE=cluster-issuer PROXY_URL=http://traefik.kube-system
SKIP_VENDOR=false

usage() { sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

CMDLINE=("$(basename "$0")" "$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --dest)             DEST="$2"; shift 2;;
    --repo-url)         REPO_URL="$2"; shift 2;;
    --app-name)         APP_NAME="$2"; shift 2;;
    --namespace)        NAMESPACE="$2"; shift 2;;
    --chart-path)       CHART_PATH="$2"; shift 2;;
    --values-path)      VALUES_PATH="$2"; shift 2;;
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
VALUES_PATH="${VALUES_PATH:-values/${APP_NAME}.yaml}"

# Argo CD resolves valueFiles relative to the chart path.
VALUES_REF="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
  "$VALUES_PATH" "$CHART_PATH")"

# ── vendor the chart ────────────────────────────────────────────────────────
if ! $SKIP_VENDOR; then
  mkdir -p "$DEST/$(dirname "$CHART_PATH")"
  rm -rf "${DEST:?}/$CHART_PATH"
  cp -R "$CHART_DIR" "$DEST/$CHART_PATH"
  echo ">> vendored chart -> $DEST/$CHART_PATH" >&2
fi

# ── user values file (created once, never overwritten) ──────────────────────
if [ ! -e "$DEST/$VALUES_PATH" ]; then
  mkdir -p "$DEST/$(dirname "$VALUES_PATH")"
  cat > "$DEST/$VALUES_PATH" <<EOF
# OptScale configuration for the ${APP_NAME} Argo CD Application.
#
# Non-secret settings only — this file is in git. Commit and push to apply:
# Argo CD syncs and the configurator hook writes the result into etcd.
# See ${CHART_PATH}/values.yaml for every option. Keys set by the generator
# in apps/${APP_NAME}.yaml (ingress, secret wiring) take precedence.
#
# Secrets never go here. Database/cluster credentials are generated
# in-cluster automatically; secret settings (SMTP password, cloud pricing
# credentials, ...) go in the optscale-secret-config Secret — see the chart
# README ("Secret settings").

# Uncomment what you need (keep the \`config:\` line once):
#
# config:
#   # Sign in with Microsoft (Entra ID app registration client ID):
#   oauth:
#     microsoftClientId: 00000000-0000-0000-0000-000000000000
#
#   # Restrict who can create accounts (password sign-up and first SSO login):
#   domainsWhitelists:
#     registration: ["@example.com"]
#
#   # Outgoing mail (the password goes in optscale-secret-config):
#   smtp:
#     server: smtp.example.com
#     port: 465
#     email: optscale@example.com
#     protocol: SSL
EOF
  echo ">> created $DEST/$VALUES_PATH (yours to edit)" >&2
fi

# ── generator-owned wiring values ───────────────────────────────────────────
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
{
  cat <<EOF
configurator:
  argocdHook: true
config:
  existingSecretConfig: optscale-secret-config
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
} > "$TMP/wiring.yaml"

# ── validate: the vendored chart must render with the user values + wiring ──
helm lint "$DEST/$CHART_PATH" > /dev/null
helm template "$APP_NAME" "$DEST/$CHART_PATH" --namespace "$NAMESPACE" \
  -f "$DEST/$VALUES_PATH" -f "$TMP/wiring.yaml" > /dev/null
echo ">> chart lints and renders with $VALUES_PATH + generated wiring" >&2

# ── write the Application manifest ──────────────────────────────────────────
mkdir -p "$DEST/apps"
APP_FILE="$DEST/apps/${APP_NAME}.yaml"
{
  cat <<EOF
# OptScale (Hystax FinOps platform) — full stack in the \`${NAMESPACE}\`
# namespace, deployed from the chart vendored at ${CHART_PATH} (source:
# github.com/hystax/optscale; see the chart README).
#
# GENERATED by ${CHART_PATH}/hack/generate-gitops.sh — do not edit; rerun:
#   ${CMDLINE[@]}
#
# Configure OptScale in ${VALUES_PATH} (non-secret, in git). Credentials
# are generated in-cluster by the chart's secrets-init hook; secret settings
# (SMTP password, cloud credentials, ...) go in the optscale-secret-config
# Secret, managed outside git — after changing it, sync this app so the
# configurator hook re-applies the configuration.
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
      valueFiles:
        - ${VALUES_REF}
      # Generator-owned wiring; takes precedence over ${VALUES_PATH}.
      values: |
EOF
  sed 's/^/        /' "$TMP/wiring.yaml"
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
  1. Review the diff in $DEST, commit and push.
  2. Ensure your app-of-apps picks up apps/${APP_NAME}.yaml (or kubectl apply it once).
  3. Credentials are generated on the first sync; back them up afterwards:
       kubectl -n $NAMESPACE get secret -l app.kubernetes.io/created-by=optscale-secrets-init -o yaml
EOF
