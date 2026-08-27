# OptScale Helm chart

Deploys [OptScale](https://github.com/hystax/optscale) — Hystax's open source
FinOps and cloud cost management platform — as a standalone Helm release:
all application services, background workers and scheduled jobs, plus the
backing stores (MariaDB, MongoDB, ClickHouse, InfluxDB, etcd, RabbitMQ,
Redis, MinIO) and the Thanos-based metrics pipeline.

Unlike the `optscale-deploy/runkube.py` flow, this chart needs **no deploy
scripts, no pre-pulled images and no hostPath volumes**: images come from
Docker Hub (`hystax/*`), storage comes from PersistentVolumeClaims, and the
release works in any namespace.

## How bootstrap works

OptScale services are configured through etcd. On every install/upgrade a
`configurator` Job:

1. waits for etcd, MariaDB, MongoDB, RabbitMQ, InfluxDB and MinIO,
2. creates databases, queues and buckets,
3. writes the rendered configuration (see `config` in values) into etcd,
4. sets the `/configured` key.

Application pods block on that key, so the whole release converges by
itself — the first start typically takes 5–15 minutes while images pull.

## Prerequisites

- Kubernetes ≥ 1.25, Helm ≥ 3.8
- A default StorageClass (or set `global.storageClass`)
- An ingress controller (any class; see below)
- ~6 CPU / 12 GiB free capacity for the default footprint

## Installing

```bash
helm install optscale ./charts/optscale \
  --namespace optscale --create-namespace \
  --set ingress.host=optscale.example.com \
  --set config.secrets.cluster="$(openssl rand -hex 20)" \
  --set config.encryptionKey="$(openssl rand -hex 16)" \
  --set config.encryptionSalt="$(openssl rand -hex 12)" \
  --set config.encryptionSaltAuth="$(openssl rand -hex 12)"
```

Watch progress:

```bash
kubectl -n optscale get pods
kubectl -n optscale logs -f job/configurator-r1
```

Then open the host you configured and register the first user (the first
registered user owns the organization). Use one release per namespace —
Services use fixed short names (`restapi`, `auth`, `mariadb`, ...) that are
also written into etcd.

### Production checklist

- Set unique values for `config.secrets.cluster`, the `encryption*` keys and
  every database password (`mariadb.rootPassword`, `mongo.password`,
  `mongo.key`, `clickhouse.password`, `rabbitmq.password`,
  `rabbitmq.erlangCookie`, `minio.secretKey`).
- Provide `config.serviceCredentials` — cloud credentials OptScale uses to
  pull pricing catalogs. **Recommendations do not work without them** (see
  `optscale-deploy/overlay/user_template.yml` for the expected structure).
- Configure `config.smtp` for outgoing email, or leave
  `config.disableEmailVerification: true`.
- Size persistence (`*.persistence.size`) for your data volume; MariaDB,
  MongoDB and ClickHouse hold the durable data, MinIO holds report files
  and Thanos blocks.

### Example: Traefik + cert-manager

```yaml
ingress:
  className: traefik
  host: finops.example.com
  tls:
    enabled: true
    secretName: defaultcert
    certManager:
      enabled: true
      issuerType: cluster-issuer   # or "issuer"
      issuer: letsencrypt-prod
ngui:
  # target for the UI server's fallback proxy — point at your ingress
  # controller's in-cluster service
  proxyUrl: http://traefik.kube-system
```

With ingress-nginx keep the defaults (`className: nginx`) and set
`ngui.proxyUrl` to your controller's service, e.g.
`http://ingress-nginx-controller.ingress-nginx`. The nginx-specific
annotations (custom error page backend, body-size limits) only take effect
on ingress-nginx; on other controllers they are inert.

TLS options, pick one:

- `ingress.tls.certManager.enabled=true` — cert-manager issues the
  certificate into `ingress.tls.secretName`;
- `ingress.tls.crt`/`ingress.tls.key` — the chart creates the TLS secret;
- pre-create a secret named `ingress.tls.secretName` yourself;
- `ingress.tls.enabled=false` — plain HTTP (labs only).

## Values overview

| Section | What it controls |
| --- | --- |
| `global.*` | image registry/org/tag, pull policy, storage class, cluster domain, default scheduling |
| `config.*` | everything written to etcd: secrets, SMTP, OAuth, Slack, service credentials, feature settings |
| `configurator.*` | bootstrap job behavior (`skipConfigUpdate` preserves manually edited etcd keys) |
| `ingress.*` | ingress class, host, TLS/cert-manager |
| `etcd/mariadb/mongo/clickhouse/rabbitmq/redis/influxdb/minio` | the data plane; `mongo.external.*` and `clickhouse.external.*` switch to managed instances |
| `thanos.*`, `tempo.*`, `grafana.*` | metrics/traces pipeline; `thanos.enabled=false` also disables the `diproxy` metrics gateway |
| `ngui`, `apis.*`, `herald`, `katara` | UI and API services (replicas, images, resources, extra env) |
| `workers.*`, `cronjobs.*`, `reportImport.*`, `cleaninfluxdb.*` | background workers and scheduled jobs |
| `elk.*`, `phpmyadmin.*` | optional centralized logging and DB admin tools (off by default) |

Per-component keys accept `replicaCount`, `imageTag`, `resources`,
`nodeSelector`, `tolerations`, `affinity` and (for generic entries)
`extraEnv`, whose values are template-rendered — e.g.
`value: "{{ .Values.config.fakeCadEnabled }}"`.

### Bring your own secrets (GitOps / External Secrets)

Every credential the chart renders can instead come from pre-existing
Secrets (created out-of-band or by External Secrets Operator), so no secret
material ever appears in rendered manifests or values files:

| Value | Secret keys expected |
| --- | --- |
| `mariadb.existingSecret` | `password` |
| `mongo.existingSecret` | `username`, `password`, `key.txt` |
| `clickhouse.existingSecret` | `password` |
| `rabbitmq.existingSecret` | `username`, `password`, `management-username`, `management-password`, `erlang-cookie`, `definitions.json` |
| `minio.existingSecret` | `access`, `secret` |
| `config.secrets.existingSecret` | `cluster_secret` |
| `thanos.existingObjstoreSecret` | `thanos_conf.yaml` (S3 objstore config) |
| `configurator.existingConfigSecret` | `config` (the full configurator YAML — render it once with `helm template` and store it) |

With all of these set the chart renders **zero** Secret objects.

For Argo CD also set `configurator.argocdHook: true` — the bootstrap Job then
runs as a Sync-phase hook (recreated every sync) instead of a
revision-suffixed Job, which does not work under Argo CD.

#### Creating the bootstrap Secrets: `hack/bootstrap-secrets.sh`

The helper script renders the chart and applies **only** the Secret objects
listed above, so the Secrets live in the cluster and never in git:

```bash
# Fresh install: mint random credentials (keep the --out file safe — it is
# the only copy; the passwords are baked into the databases on first start)
charts/optscale/hack/bootstrap-secrets.sh \
  -n optscale --context mycluster \
  --generate --out optscale-secret-values.yaml \
  --app-file apps/optscale.yaml

# Re-apply / update from the saved values file
charts/optscale/hack/bootstrap-secrets.sh \
  -n optscale --context mycluster \
  -f optscale-secret-values.yaml --app-file apps/optscale.yaml
```

`--app-file` layers in the Argo CD Application's inline helm values so the
rendered `optscale-config` matches the deployed configuration (ingress
host, feature toggles, ...). After changing any configuration, re-run the
script and sync the app — the configurator hook re-runs on every sync and
writes the new config into etcd. `--dry-run` prints the manifests instead
of applying. Note that the database passwords cannot be rotated by
re-running the script alone: they are baked into the data volumes.

### Generating a GitOps deployment: `hack/generate-gitops.sh`

`hack/generate-gitops.sh` scaffolds (and keeps updated) an Argo CD
deployment of this chart in a gitops repository: it vendors the chart into
`<gitops-repo>/charts/optscale` and writes an `apps/<name>.yaml` Argo CD
Application wired for the patterns above — bootstrap-Secret references,
the configurator as a Sync-phase hook, and `ignoreDifferences` for the
server-defaulted StatefulSet `volumeClaimTemplates` fields:

```bash
charts/optscale/hack/generate-gitops.sh \
  --dest ~/git/my-gitops \
  --repo-url git@github.com:me/my-gitops.git \
  --host optscale.example.com \
  --issuer letsencrypt-prod          # omit to manage the TLS secret yourself
```

The script validates the result with `helm lint` + `helm template` and is
deterministic — rerun it after chart updates and commit the diff. See
`--help` for all flags (ingress class, namespaces, proxy URL, ...).

### Enabling paid-feature components

`config.stripe.enabled=true` additionally deploys `subspector`,
`subsyncer` and `bailiff` (billing/subscription services).

### Versions

`global.imageTag` defaults to the chart's `appVersion` (an OptScale release
tag). To deploy another release:

```bash
helm upgrade optscale ./charts/optscale --reuse-values \
  --set global.imageTag=<tag from github.com/hystax/optscale/releases>
```

## Differences from the runkube deployment

- **Images** are pulled per-pod from `hystax/*` on Docker Hub instead of
  being pre-pulled to every node and retagged `:local`.
- **Storage** uses PVCs instead of `/optscale/*` hostPath directories, and
  nothing is pinned to control-plane nodes.
- **Namespace-safe**: no hardcoded `default` namespace anywhere.
- **RabbitMQ** starts clean on 4.1.x. The in-place 3.8→4.1 feature-flag
  migration ladder from the original manifests is not included — this chart
  is for fresh installations, not for upgrading a runkube cluster's data
  in place.
- **ClickHouse** uses the upstream image with env-based user setup (same
  approach as OptScale's Docker Compose deployment).
- **TLS material** is no longer read from a pre-created `defaultcert`
  secret by a deploy script; use the `ingress.tls` options instead.
- The `configurator` Job runs as `configurator-r<revision>`, so upgrades
  re-run it automatically (old jobs are TTL-cleaned).

## Uninstalling

```bash
helm uninstall optscale -n optscale
```

PVCs created from StatefulSet `volumeClaimTemplates` are kept by design;
delete them explicitly to drop data:

```bash
kubectl -n optscale delete pvc --all
```
