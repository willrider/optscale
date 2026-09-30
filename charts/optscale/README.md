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

## How configuration works

OptScale services are configured through etcd. The chart keeps three kinds
of input apart:

| What | Where it lives | How you change it |
| --- | --- | --- |
| Non-secret settings (hosts, feature flags, SSO client ID, sign-up whitelist, SMTP server, ...) | `config.*` values → ConfigMap `optscale-config` | edit values, `helm upgrade` / git push |
| Credentials (database passwords, cluster token, encryption keys) | Secrets generated in-cluster by the `secrets-init` hook | nothing to do — created on first install, never touched again |
| Secret settings (SMTP password, cloud pricing credentials, Stripe keys, ...) | Secret `optscale-secret-config`, key `etcd.yaml` | `kubectl` / External Secrets, then upgrade or sync |

On every install/upgrade:

1. **`secrets-init`** (pre-install/pre-upgrade hook — PreSync under Argo CD)
   creates any credential Secret or key that is missing, from the spec in
   the `optscale-secrets-spec` ConfigMap. Existing Secrets and keys are never
   modified.
2. **`configurator`** waits for etcd, MariaDB, MongoDB, RabbitMQ, InfluxDB and
   MinIO, assembles its input at runtime (`files/configure.py`: the
   ConfigMap, deep-merged with `optscale-secret-config`, plus credentials
   read from the Secrets), creates databases/queues/buckets, writes
   everything into etcd and sets the `/configured` key.

Application pods block on that key, so the whole release converges by
itself — the first start typically takes 5–15 minutes while images pull.
No credential is ever rendered into a manifest or stored in values.

## Prerequisites

- Kubernetes ≥ 1.25, Helm ≥ 3.8
- A default StorageClass (or set `global.storageClass`)
- An ingress controller (any class; see below)
- ~6 CPU / 12 GiB free capacity for the default footprint

## Installing

```bash
helm install optscale ./charts/optscale \
  --namespace optscale --create-namespace \
  --set ingress.host=optscale.example.com
```

Credentials are generated on first install. Back them up — the database
volumes depend on them:

```bash
kubectl -n optscale get secret -l app.kubernetes.io/created-by=optscale-secrets-init -o yaml > optscale-credentials.yaml
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

- Back up the generated credential Secrets (command above) somewhere safe.
- Provide cloud pricing credentials (`service_credentials` in
  `optscale-secret-config`, see [Secret settings](#secret-settings)).
  **Recommendations do not work without them** (structure:
  `optscale-deploy/overlay/user_template.yml`).
- Configure outgoing email (`config.smtp` + the password in
  `optscale-secret-config`), or leave
  `config.disableEmailVerification: true`. Note: with no SMTP configured,
  herald falls back to a sendmail MTA **inside its image** and tries to
  deliver alert emails direct-to-MX — which will get your egress IP listed
  on Spamhaus. The chart blocks this by default via a NetworkPolicy on
  egress TCP 25 (`networkPolicy.blockSmtpEgress`); point `config.smtp` at a
  real relay on 465/587 to actually deliver mail.
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

### Credentials

Generated by `secrets-init` unless you point the chart at your own Secret
(e.g. managed by External Secrets Operator) — Secrets referenced this way are
left entirely to you:

| Default Secret | Keys | Override with |
| --- | --- | --- |
| `mariadb-secret` | `password` | `mariadb.existingSecret` |
| `mongo-secret` | `username`, `password`, `key.txt` (`url` for external MongoDB) | `mongo.existingSecret` |
| `clickhouse-secret` | `password` | `clickhouse.existingSecret` |
| `rabbit-secret` | `username`, `password`, `erlang-cookie` | `rabbitmq.existingSecret` |
| `minio-secret` | `access`, `secret` | `minio.existingSecret` |
| `cluster-secret` | `cluster_secret` | `config.secrets.existingSecret` |
| `optscale-encryption` | `encryption-key`, `encryption-salt`, `encryption-salt-auth`, `bi-encryption-key` | `config.existingEncryptionSecret` |

To pin a specific value, create the Secret with its default name and keys
before installing — `secrets-init` only fills in what is missing. External
MongoDB/ClickHouse require an `existingSecret` (there is nothing to
generate). Never change credentials of an existing installation this way:
the databases were initialized with them.

### Secret settings

Secret-bearing etcd settings live in one Secret, `optscale-secret-config`,
key `etcd.yaml`, deep-merged over the configuration at configure time. It
uses etcd key names:

```yaml
smtp:
  password: app-password
service_credentials:
  aws:
    access_key_id: AKIA...
    secret_access_key: ...
stripe:
  api_key: ...
```

With plain Helm the chart renders it from the matching values
(`config.smtp.password`, `config.serviceCredentials`, `config.stripe.*`,
...). In GitOps setups set `config.existingSecretConfig:
optscale-secret-config` and manage the Secret outside git:

```bash
kubectl -n optscale create secret generic optscale-secret-config \
  --from-file=etcd.yaml=secret-config.yaml --dry-run=client -o yaml | kubectl apply -f -
```

then sync the app (or `helm upgrade`) — the configurator applies it. The
Secret is optional; without it those settings stay empty.

### Generating a GitOps deployment: `hack/generate-gitops.sh`

`hack/generate-gitops.sh` scaffolds (and keeps updated) an Argo CD
deployment of this chart in a gitops repository:

- `charts/optscale` — vendored copy of this chart;
- `apps/<name>.yaml` — the Argo CD Application (generated; wiring only:
  ingress, secret-config reference, configurator as a Sync hook,
  `ignoreDifferences` for server-defaulted StatefulSet fields);
- `values/<name>.yaml` — **your** configuration, referenced through
  `valueFiles`; created once with commented examples, never overwritten.

```bash
charts/optscale/hack/generate-gitops.sh \
  --dest ~/git/my-gitops \
  --repo-url git@github.com:me/my-gitops.git \
  --host optscale.example.com \
  --issuer letsencrypt-prod          # omit to manage the TLS secret yourself
```

Day-to-day: edit `values/<name>.yaml` and push. The script validates the
result with `helm lint` + `helm template` and is deterministic — rerun it
after chart updates and commit the diff. See `--help` for all flags.

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
- **No credentials in values or manifests**: upstream ships database
  passwords in values, a ConfigMap (`optscale-etcd`) and ClickHouse's
  `users.xml`; here they are generated into Secrets and only combined with
  the configuration inside the configurator pod.
- The `configurator` Job runs as `configurator-r<revision>`, so upgrades
  re-run it automatically (old jobs are TTL-cleaned).

## Uninstalling

```bash
helm uninstall optscale -n optscale
```

PVCs created from StatefulSet `volumeClaimTemplates` and the generated
credential Secrets are kept by design (a reinstall reuses both); delete them
explicitly to drop data:

```bash
kubectl -n optscale delete pvc --all
kubectl -n optscale delete secret -l app.kubernetes.io/created-by=optscale-secrets-init
```
