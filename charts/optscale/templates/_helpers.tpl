{{/* vim: set filetype=mustache: */}}

{{/*
Default tag for Hystax-built images.
*/}}
{{- define "optscale.tag" -}}
{{- .Values.global.imageTag | default .Chart.AppVersion -}}
{{- end -}}

{{/*
Fully qualified Hystax image reference.
Input: dict with "root" (chart root), "repo" (image name) and optional "tag".
*/}}
{{- define "optscale.image" -}}
{{- $tag := .tag | default (include "optscale.tag" .root) -}}
{{- printf "%s/%s/%s:%s" .root.Values.global.imageRegistry .root.Values.global.imageOrg .repo $tag -}}
{{- end -}}

{{/*
Common labels. Input: dict with "root" and "name".
*/}}
{{- define "optscale.labels" -}}
app: {{ .name }}
release: {{ .root.Release.Name }}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/part-of: optscale
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
Selector labels (kept aligned with the historical optscale-deploy chart).
Input: dict with "root" and "name".
*/}}
{{- define "optscale.selectorLabels" -}}
app: {{ .name }}
release: {{ .root.Release.Name }}
{{- end -}}

{{/*
Image pull secrets. Input: chart root.
*/}}
{{- define "optscale.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Scheduling settings merged with global defaults.
Input: dict with "root" and optional "comp" (component values).
*/}}
{{- define "optscale.podScheduling" -}}
{{- $root := .root -}}
{{- $comp := .comp | default (dict) -}}
{{- with (default $root.Values.global.nodeSelector $comp.nodeSelector) }}
nodeSelector:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- with (default $root.Values.global.tolerations $comp.tolerations) }}
tolerations:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- with (default $root.Values.global.affinity $comp.affinity) }}
affinity:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Environment variables pointing services at etcd. Input: chart root.
*/}}
{{- define "optscale.etcdEnv" -}}
- name: HX_ETCD_HOST
  value: {{ .Values.etcd.serviceName | quote }}
- name: HX_ETCD_PORT
  value: {{ .Values.etcd.port | quote }}
{{- end -}}

{{/*
Extra env entries; values are rendered through tpl so they may reference
other values (e.g. "{{ .Values.config.fakeCadEnabled }}").
Input: dict with "root" and "env" (list of {name,value}).
*/}}
{{- define "optscale.extraEnv" -}}
{{- $root := .root -}}
{{- range .env }}
- name: {{ .name }}
  value: {{ tpl (.value | toString) $root | quote }}
{{- end }}
{{- end -}}

{{/*
TCP wait init container. Input: dict with "root", "name", "host", "port".
*/}}
{{- define "optscale.waitTcp" -}}
- name: wait-{{ .name }}
  image: {{ .root.Values.waitImage | quote }}
  imagePullPolicy: IfNotPresent
  command: ['sh', '-c', 'until nc -z {{ .host }} {{ .port }} -w 2; do sleep 2; done']
{{- end -}}

{{/*
MariaDB wait init container — waits until the server answers queries.
Input: chart root.
*/}}
{{- define "optscale.waitMariadb" -}}
- name: wait-mariadb
  image: {{ include "optscale.image" (dict "root" . "repo" .Values.mariadb.image "tag" .Values.mariadb.imageTag) | quote }}
  imagePullPolicy: {{ .Values.global.imagePullPolicy }}
  env:
    - name: MYSQL_ROOT_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ include "optscale.mariadb.secretName" . }}
          key: password
  command: ['sh', '-c', 'until mysql --connect-timeout=2 -h {{ .Values.mariadb.name }} -p$MYSQL_ROOT_PASSWORD -e "SELECT 1"; do sleep 2; done']
{{- end -}}

{{- define "optscale.mariadb.secretName" -}}
{{- .Values.mariadb.existingSecret | default "mariadb-secret" -}}
{{- end -}}

{{- define "optscale.mongo.secretName" -}}
{{- .Values.mongo.existingSecret | default "mongo-secret" -}}
{{- end -}}

{{- define "optscale.clickhouse.secretName" -}}
{{- .Values.clickhouse.existingSecret | default "clickhouse-secret" -}}
{{- end -}}

{{- define "optscale.minio.secretName" -}}
{{- .Values.minio.existingSecret | default "minio-secret" -}}
{{- end -}}

{{- define "optscale.rabbitmq.secretName" -}}
{{- .Values.rabbitmq.existingSecret | default "rabbit-secret" -}}
{{- end -}}

{{- define "optscale.clusterSecretName" -}}
{{- .Values.config.secrets.existingSecret | default "cluster-secret" -}}
{{- end -}}

{{- define "optscale.configSecretName" -}}
{{- .Values.configurator.existingConfigSecret | default "optscale-config" -}}
{{- end -}}

{{- define "optscale.thanos.secretName" -}}
{{- .Values.thanos.existingObjstoreSecret | default "thanos-secret" -}}
{{- end -}}

{{/*
Dependency wait init containers.
Input: dict with "root" and "waitFor" (list of well-known dependency names).
Dependencies on disabled/external components are skipped automatically.
*/}}
{{- define "optscale.waitFor" -}}
{{- $root := .root -}}
{{- $v := $root.Values -}}
{{- range (.waitFor | default list) }}
{{- if eq . "etcd" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "etcd" "host" $v.etcd.serviceName "port" $v.etcd.port) }}
{{- else if eq . "mariadb" }}
{{ include "optscale.waitMariadb" $root }}
{{- else if eq . "mongo" }}
{{- if not $v.mongo.external.enabled }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "mongo" "host" $v.mongo.name "port" $v.mongo.servicePort) }}
{{- end }}
{{- else if eq . "clickhouse" }}
{{- if not $v.clickhouse.external.enabled }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "clickhouse" "host" $v.clickhouse.name "port" $v.clickhouse.tcpPort) }}
{{- end }}
{{- else if eq . "rabbitmq" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "rabbitmq" "host" $v.rabbitmq.name "port" $v.rabbitmq.port) }}
{{- else if eq . "redis" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "redis" "host" $v.redis.name "port" $v.redis.servicePort) }}
{{- else if eq . "influxdb" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "influxdb" "host" $v.influxdb.name "port" $v.influxdb.servicePort) }}
{{- else if eq . "minio" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "minio" "host" $v.minio.name "port" $v.minio.servicePort) }}
{{- else if eq . "restapi" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "restapi" "host" $v.apis.restapi.name "port" $v.apis.restapi.servicePort) }}
{{- else if eq . "auth" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "auth" "host" $v.apis.auth.name "port" $v.apis.auth.servicePort) }}
{{- else if eq . "keeper" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "keeper" "host" $v.apis.keeper.name "port" $v.apis.keeper.servicePort) }}
{{- else if eq . "insider" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "insider" "host" $v.apis.insider.name "port" $v.apis.insider.servicePort) }}
{{- else if eq . "slacker" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "slacker" "host" $v.apis.slacker.name "port" $v.apis.slacker.servicePort) }}
{{- else if eq . "metroculus" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "metroculus" "host" $v.apis.metroculus.name "port" $v.apis.metroculus.servicePort) }}
{{- else if eq . "jirabus" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "jirabus" "host" $v.apis.jirabus.name "port" $v.apis.jirabus.servicePort) }}
{{- else if eq . "subspector" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "subspector" "host" $v.apis.subspector.name "port" $v.apis.subspector.servicePort) }}
{{- else if eq . "herald" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "herald" "host" $v.herald.name "port" $v.herald.servicePort) }}
{{- else if eq . "katara" }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "katara" "host" $v.katara.name "port" $v.katara.servicePort) }}
{{- else if eq . "thanosReceive" }}
{{- if $v.thanos.enabled }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "thanos-receive" "host" $v.thanos.receive.name "port" $v.thanos.receive.httpPort) }}
{{- end }}
{{- else if eq . "tempo" }}
{{- if $v.tempo.enabled }}
{{ include "optscale.waitTcp" (dict "root" $root "name" "tempo" "host" $v.tempo.name "port" $v.tempo.queryPort) }}
{{- end }}
{{- else }}
{{- fail (printf "unknown waitFor dependency %q" .) }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Boolean field lookup that treats an explicit `false` as false (plain
`default` would replace it). Prints "true" or "false".
Input: dict with "map", "key" and "default".
*/}}
{{- define "optscale.flag" -}}
{{- if hasKey .map .key -}}{{- get .map .key -}}{{- else -}}{{- .default -}}{{- end -}}
{{- end -}}

{{/*
Standard CronJob job-template policy fields. Input: chart root.
*/}}
{{- define "optscale.cronPolicy" -}}
concurrencyPolicy: Forbid
startingDeadlineSeconds: {{ .Values.cronDefaults.startingDeadlineSeconds }}
successfulJobsHistoryLimit: {{ .Values.cronDefaults.successfulJobsHistoryLimit }}
failedJobsHistoryLimit: {{ .Values.cronDefaults.failedJobsHistoryLimit }}
{{- end -}}

{{/*
OpenTelemetry exporter connection string with in-release tempo default.
Input: chart root.
*/}}
{{- define "optscale.otelConnectionString" -}}
{{- if .Values.config.opentelemetry.exporter.connectionString -}}
{{- .Values.config.opentelemetry.exporter.connectionString -}}
{{- else -}}
{{- printf "http://%s.%s.svc.%s:%v" .Values.tempo.name .Release.Namespace .Values.global.clusterDomain .Values.tempo.otlpGrpcPort -}}
{{- end -}}
{{- end -}}

{{/*
Public IP / hostname written to etcd. Input: chart root.
*/}}
{{- define "optscale.publicIp" -}}
{{- .Values.config.publicIp | default .Values.ingress.host -}}
{{- end -}}
