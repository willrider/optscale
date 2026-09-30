{{/*
Non-secret configuration consumed by the configurator Job (ConfigMap
optscale-config). The `etcd:` branch is written key-by-key into etcd;
everything else instructs the configurator itself (databases to create,
etc.). Credential fields are left empty here: files/configure.py fills them
at runtime from the component Secrets, the encryption Secret and the
secret-config overlay.
*/}}
{{- define "optscale.configYaml" -}}
{{- $v := .Values -}}
{{- $c := $v.config -}}
skip_config_update: {{ $v.configurator.skipConfigUpdate }}
drop_tasks_db: {{ $v.configurator.dropTasksDb }}
databases:
{{- range $c.databases }}
  - {{ . | quote }}
{{- end }}
etcd:
  public_ip: {{ include "optscale.publicIp" . | quote }}
  company_name: {{ $c.companyName | quote }}
  product_name: {{ $c.productName | quote }}
  encryption_key: ""
  release: {{ .Release.Name | quote }}
  katara_scheduler_timeout: {{ $c.kataraSchedulerTimeout }}
  bumi_scheduler_timeout: {{ $c.bumiSchedulerTimeout }}
  bumi_worker:
    max_retries: {{ $c.bumiWorker.maxRetries }}
    wait_timeout: {{ $c.bumiWorker.waitTimeout }}
    task_timeout: {{ $c.bumiWorker.taskTimeout }}
    run_period: {{ $c.bumiWorker.runPeriod }}
  optscale_service_emails:
    recipient: {{ $c.optscaleServiceEmails.recipient | quote }}
    enabled: {{ $c.optscaleServiceEmails.enabled }}
  optscale_error_emails:
    recipient: {{ $c.optscaleErrorEmails.recipient | quote }}
    enabled: {{ $c.optscaleErrorEmails.enabled }}
  skip_email_filters:
{{- range $template, $filters := $c.skipEmailFilters }}
    {{ $template }}:
{{- range $path, $regex := $filters }}
      {{ $path | quote }}: {{ $regex | quote }}
{{- end }}
{{- end }}
  google_calendar_service:
    enabled: {{ $c.googleCalendarService.enabled }}
    access_key:
  domains_blacklists:
    new_employee_email:
{{- range $c.domainsBlacklists.newEmployeeEmail }}
      - {{ . | quote }}
{{- end }}
    registration:
{{- range $c.domainsBlacklists.registration }}
      - {{ . | quote }}
{{- end }}
    failed_import_email:
{{- range $c.domainsBlacklists.failedImportEmail }}
      - {{ . | quote }}
{{- end }}
  domains_whitelists:
    new_employee_email:
{{- range $c.domainsWhitelists.newEmployeeEmail }}
      - {{ . | quote }}
{{- end }}
    registration:
{{- range $c.domainsWhitelists.registration }}
      - {{ . | quote }}
{{- end }}
    failed_import_email:
{{- range $c.domainsWhitelists.failedImportEmail }}
      - {{ . | quote }}
{{- end }}
  secret:
    cluster: ""
    agent: ""
  images_source:
    host: {{ printf "%s/%s" $v.global.imageRegistry $v.global.imageOrg | quote }}
    tag: {{ include "optscale.tag" . | quote }}
  restapi:
    invite_expiration_days: {{ $c.inviteExpirationDays }}
    host: {{ $v.apis.restapi.name | quote }}
    port: {{ $v.apis.restapi.servicePort }}
    demo:
      multiplier: {{ $c.demo.multiplier }}
    report_imports:
      not_processed_threshold_secs: {{ $c.importReports.notProcessedThresholdSecs }}
      message_expiration_secs: {{ $c.importReports.messageExpirationSecs }}
    opentelemetry:
      enable_asyncio: true
      enable_threading: true
      enable_tornado: true
      enable_urllib3: true
      enable_requests: true
      enable_sqlalchemy: true
      enable_mongo: true
      enable_kombu: true
      enable_clickhouse: true
  auth:
    host: {{ $v.apis.auth.name | quote }}
    port: {{ $v.apis.auth.servicePort }}
    opentelemetry:
      enable_asyncio: true
      enable_threading: true
      enable_tornado: true
      enable_urllib3: true
      enable_requests: true
      enable_sqlalchemy: true
  katara:
    host: {{ $v.katara.name | quote }}
    port: {{ $v.katara.servicePort }}
  herald:
    host: {{ $v.herald.name | quote }}
    port: {{ $v.herald.servicePort }}
  keeper:
    host: {{ $v.apis.keeper.name | quote }}
    port: {{ $v.apis.keeper.servicePort }}
  insider:
    host: {{ $v.apis.insider.name | quote }}
    port: {{ $v.apis.insider.servicePort }}
  slacker:
    host: {{ $v.apis.slacker.name | quote }}
    port: {{ $v.apis.slacker.servicePort }}
  jirabus:
    host: {{ $v.apis.jirabus.name | quote }}
    port: {{ $v.apis.jirabus.servicePort }}
  metroculus:
    host: {{ $v.apis.metroculus.name | quote }}
    port: {{ $v.apis.metroculus.servicePort }}
  thanos_query:
    host: {{ $v.thanos.query.name | quote }}
    port: {{ $v.thanos.query.httpPort }}
  thanos_receive:
    host: {{ $v.thanos.receive.name | quote }}
    port: {{ $v.thanos.receive.remoteWritePort }}
    path: {{ $v.thanos.receive.remoteWritePath | quote }}
  authdb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: ""
    db: auth-db
  heralddb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: ""
    db: herald
  restdb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: ""
    db: my-db
    port: {{ $v.mariadb.port }}
  kataradb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: ""
    db: katara
  slackerdb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: ""
    db: slacker
    port: {{ $v.mariadb.port }}
  jirabusdb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: ""
    db: jira-bus
    port: {{ $v.mariadb.port }}
  subspectordb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: ""
    db: subspector
    port: {{ $v.mariadb.port }}
  mongo:
{{- if $v.mongo.external.enabled }}
    url: ""
{{- else }}
    url: {{ printf "mongodb://%s:%v" $v.mongo.name $v.mongo.servicePort | quote }}
{{- end }}
    database: keeper
  influxdb:
    host: {{ $v.influxdb.name | quote }}
    port: {{ $v.influxdb.servicePort }}
    user: ""
    pass: ""
    database: metrics
  rabbit:
    user: ""
    pass: ""
    host: {{ $v.rabbitmq.name | quote }}
    port: {{ $v.rabbitmq.port }}
  minio:
    host: {{ $v.minio.name | quote }}
    port: {{ $v.minio.servicePort }}
    access: ""
    secret: ""
  clickhouse:
    host: {{ $v.clickhouse.name | quote }}
    port: {{ $v.clickhouse.httpPort }}
    user: {{ $v.clickhouse.user | quote }}
    password: ""
    db: {{ $v.clickhouse.db | quote }}
  cleanmongodb:
    chunk_size: {{ $c.cleanmongodb.chunkSize }}
    rows_limit: {{ $c.cleanmongodb.rowsLimit }}
    archive_enable: {{ $c.cleanmongodb.archiveEnable | quote }}
    file_max_rows: {{ $c.cleanmongodb.fileMaxRows }}
  disable_email_verification: {{ $c.disableEmailVerification }}
  force_aws_edp_strip: {{ $c.forceAwsEdpStrip | quote }}
  encryption_salt: ""
  encryption_salt_auth: ""
  certificates:
{{- range $key, $val := $c.certificates }}
    {{ $key }}: {{ $val | quote }}
{{- end }}
{{- if $v.elk.enabled }}
  logstash_host: {{ $v.elk.name | quote }}
  logstash_port: {{ $v.elk.logstashTcpPort }}
{{- else }}
  logstash_port: ""
{{- end }}
  events_queue: {{ $c.eventsQueue | quote }}
  resources_discovery_cache_time: ""
  overlay_list: ""
  token_expiration: {{ $c.tokenExpiration }}
  users_dataset_generator:
    enable: {{ $c.usersDatasetGenerator.enable }}
    bucket: {{ $c.usersDatasetGenerator.bucket | quote }}
    s3_path: {{ $c.usersDatasetGenerator.s3Path | quote }}
    filename: {{ $c.usersDatasetGenerator.filename | quote }}
    aws_access_key_id: ""
    aws_secret_access_key: ""
  service_credentials: {}
  smtp:
    server: {{ $c.smtp.server | quote }}
    email: {{ $c.smtp.email | quote }}
    login: {{ $c.smtp.login | quote }}
    port: {{ $c.smtp.port | quote }}
    password: ""
    protocol: {{ $c.smtp.protocol | quote }}
  resource_discovery_settings:
    discover_size: {{ $c.resourceDiscoverySettings.discoverSize }}
    timeout: {{ $c.resourceDiscoverySettings.timeout | quote }}
    writing_timeout: {{ $c.resourceDiscoverySettings.writingTimeout }}
    observe_timeout: {{ $c.resourceDiscoverySettings.observeTimeout }}
    debug: {{ $c.resourceDiscoverySettings.debug | quote }}
  bi_settings:
    exporter_run_period: {{ $c.biSettings.exporterRunPeriod }}
    encryption_key: ""
    task_wait_timeout: {{ $c.biSettings.taskWaitTimeout }}
  failed_imports_dataset_generator:
    enable: {{ $c.failedImportsDatasetGenerator.enable }}
    bucket: {{ $c.failedImportsDatasetGenerator.bucket | quote }}
    s3_path: {{ $c.failedImportsDatasetGenerator.s3Path | quote }}
    filename: {{ $c.failedImportsDatasetGenerator.filename | quote }}
    aws_access_key_id: ""
    aws_secret_access_key: ""
  subspector:
    host: {{ $v.apis.subspector.name | quote }}
    port: {{ $v.apis.subspector.servicePort }}
  password_strength_settings:
    min_length: {{ $c.passwordStrengthSettings.minLength | quote }}
    min_lowercase: {{ $c.passwordStrengthSettings.minLowercase | quote }}
    min_uppercase: {{ $c.passwordStrengthSettings.minUppercase | quote }}
    min_digits: {{ $c.passwordStrengthSettings.minDigits | quote }}
    min_special_chars: {{ $c.passwordStrengthSettings.minSpecialChars | quote }}
  demo_org_cleanup:
    demo_org_lifetime_hrs: {{ $c.demoOrgCleanup.demoOrgLifetimeHrs | quote }}
  diworker:
    max_report_imports_workers: {{ $c.importReports.maxWorkers }}
    csv_rewrite_days: {{ $c.importReports.csvRewriteDays }}
    opentelemetry:
      enable_threading: true
      enable_urllib3: true
      enable_requests: true
      enable_kombu: true
      enable_clickhouse: true
  exchange_rates:
{{- range $currency, $rate := $c.exchangeRates }}
    {{ $currency }}: {{ $rate }}
{{- end }}
  stripe:
    api_key: ""
    webhook_secret: ""
    enabled: {{ $c.stripe.enabled }}
  opentelemetry:
    enabled: {{ $c.opentelemetry.enabled }}
{{- if $c.opentelemetry.enabled }}
    exporter:
      type: {{ $c.opentelemetry.exporter.type }}
{{- if or (eq $c.opentelemetry.exporter.type "otlp") (eq $c.opentelemetry.exporter.type "azure_monitor") }}
      connection_string: {{ include "optscale.otelConnectionString" . | quote }}
{{- end }}
{{- else }}
    # services require an exporter key even with telemetry disabled
    exporter:
      type: console
{{- end }}
{{- with $c.extra }}
{{ toYaml . | indent 2 }}
{{- end }}
{{- end -}}

{{/*
Secret-bearing etcd configuration taken from values (only rendered into the
optscale-secret-config Secret when config.existingSecretConfig is unset).
Deep-merged over the etcd branch by files/configure.py.
*/}}
{{- define "optscale.secretConfigYaml" -}}
{{- $c := .Values.config -}}
{{- $o := dict -}}
{{- with $c.secrets.agent }}{{- $_ := set $o "secret" (dict "agent" .) }}{{- end }}
{{- with $c.smtp.password }}{{- $_ := set $o "smtp" (dict "password" .) }}{{- end }}
{{- with $c.serviceCredentials }}{{- $_ := set $o "service_credentials" . }}{{- end }}
{{- with $c.googleCalendarService.accessKey }}{{- $_ := set $o "google_calendar_service" (dict "access_key" .) }}{{- end }}
{{- $stripe := dict }}
{{- with $c.stripe.apiKey }}{{- $_ := set $stripe "api_key" . }}{{- end }}
{{- with $c.stripe.webhookSecret }}{{- $_ := set $stripe "webhook_secret" . }}{{- end }}
{{- if $stripe }}{{- $_ := set $o "stripe" $stripe }}{{- end }}
{{- with $c.zohocrm.regapp }}
{{- $_ := set $o "zohocrm" (dict "regapp_email" .email "regapp_client_id" .client_id "regapp_client_secret" .client_secret "regapp_refresh_token" .refresh_token "regapp_redirect_uri" .redirect_uri) }}
{{- end }}
{{- range $key, $gen := dict "users_dataset_generator" $c.usersDatasetGenerator "failed_imports_dataset_generator" $c.failedImportsDatasetGenerator }}
{{- $aws := dict }}
{{- with $gen.awsAccessKeyId }}{{- $_ := set $aws "aws_access_key_id" . }}{{- end }}
{{- with $gen.awsSecretAccessKey }}{{- $_ := set $aws "aws_secret_access_key" . }}{{- end }}
{{- if $aws }}{{- $_ := set $o $key $aws }}{{- end }}
{{- end }}
{{- toYaml $o }}
{{- end -}}
