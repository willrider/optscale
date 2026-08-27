{{/*
Configuration consumed by the configurator Job. The `etcd:` branch is
written key-by-key into etcd; everything else instructs the configurator
itself (databases to create, etc.). Keep hosts/ports in sync with the
component definitions in values.yaml — they are all referenced from there.
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
  encryption_key: {{ $c.encryptionKey | quote }}
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
{{- range $key, $value := $c.googleCalendarService.accessKey }}
      {{ $key }}: {{ $value | quote }}
{{- end }}
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
    cluster: {{ $c.secrets.cluster | quote }}
    agent: {{ $c.secrets.agent | quote }}
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
    password: {{ $v.mariadb.rootPassword | quote }}
    db: auth-db
  heralddb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: {{ $v.mariadb.rootPassword | quote }}
    db: herald
  restdb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: {{ $v.mariadb.rootPassword | quote }}
    db: my-db
    port: {{ $v.mariadb.port }}
  kataradb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: {{ $v.mariadb.rootPassword | quote }}
    db: katara
  slackerdb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: {{ $v.mariadb.rootPassword | quote }}
    db: slacker
    port: {{ $v.mariadb.port }}
  jirabusdb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: {{ $v.mariadb.rootPassword | quote }}
    db: jira-bus
    port: {{ $v.mariadb.port }}
  subspectordb:
    host: {{ $v.mariadb.name | quote }}
    user: root
    password: {{ $v.mariadb.rootPassword | quote }}
    db: subspector
    port: {{ $v.mariadb.port }}
  mongo:
{{- if $v.mongo.external.enabled }}
    url: {{ required "mongo.external.url is required when mongo.external.enabled" $v.mongo.external.url | quote }}
{{- else }}
    url: {{ printf "mongodb://%s:%s@%s:%v" $v.mongo.user $v.mongo.password $v.mongo.name $v.mongo.servicePort | quote }}
{{- end }}
    database: keeper
  influxdb:
    host: {{ $v.influxdb.name | quote }}
    port: {{ $v.influxdb.servicePort }}
    user: ""
    pass: ""
    database: metrics
  rabbit:
    user: {{ $v.rabbitmq.user | quote }}
    pass: {{ $v.rabbitmq.password | quote }}
    host: {{ $v.rabbitmq.name | quote }}
    port: {{ $v.rabbitmq.port }}
  minio:
    host: {{ $v.minio.name | quote }}
    port: {{ $v.minio.servicePort }}
    access: {{ $v.minio.accessKey | quote }}
    secret: {{ $v.minio.secretKey | quote }}
  clickhouse:
    host: {{ $v.clickhouse.name | quote }}
    port: {{ $v.clickhouse.httpPort }}
    user: {{ $v.clickhouse.user | quote }}
    password: {{ $v.clickhouse.password | quote }}
    db: {{ $v.clickhouse.db | quote }}
  cleanmongodb:
    chunk_size: {{ $c.cleanmongodb.chunkSize }}
    rows_limit: {{ $c.cleanmongodb.rowsLimit }}
    archive_enable: {{ $c.cleanmongodb.archiveEnable | quote }}
    file_max_rows: {{ $c.cleanmongodb.fileMaxRows }}
  disable_email_verification: {{ $c.disableEmailVerification }}
  force_aws_edp_strip: {{ $c.forceAwsEdpStrip | quote }}
  encryption_salt: {{ $c.encryptionSalt | quote }}
  encryption_salt_auth: {{ $c.encryptionSaltAuth | quote }}
{{- with $c.zohocrm.regapp }}
  zohocrm:
    regapp_email: {{ .email | quote }}
    regapp_client_id: {{ .client_id | quote }}
    regapp_client_secret: {{ .client_secret | quote }}
    regapp_refresh_token: {{ .refresh_token | quote }}
    regapp_redirect_uri: {{ .redirect_uri | quote }}
{{- end }}
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
    aws_access_key_id: {{ $c.usersDatasetGenerator.awsAccessKeyId | quote }}
    aws_secret_access_key: {{ $c.usersDatasetGenerator.awsSecretAccessKey | quote }}
  service_credentials:
{{ toYaml $c.serviceCredentials | indent 4 }}
  smtp:
    server: {{ $c.smtp.server | quote }}
    email: {{ $c.smtp.email | quote }}
    login: {{ $c.smtp.login | quote }}
    port: {{ $c.smtp.port | quote }}
    password: {{ $c.smtp.password | quote }}
    protocol: {{ $c.smtp.protocol | quote }}
  resource_discovery_settings:
    discover_size: {{ $c.resourceDiscoverySettings.discoverSize }}
    timeout: {{ $c.resourceDiscoverySettings.timeout | quote }}
    writing_timeout: {{ $c.resourceDiscoverySettings.writingTimeout }}
    observe_timeout: {{ $c.resourceDiscoverySettings.observeTimeout }}
    debug: {{ $c.resourceDiscoverySettings.debug | quote }}
  bi_settings:
    exporter_run_period: {{ $c.biSettings.exporterRunPeriod }}
    encryption_key: {{ $c.biSettings.encryptionKey | quote }}
    task_wait_timeout: {{ $c.biSettings.taskWaitTimeout }}
  failed_imports_dataset_generator:
    enable: {{ $c.failedImportsDatasetGenerator.enable }}
    bucket: {{ $c.failedImportsDatasetGenerator.bucket | quote }}
    s3_path: {{ $c.failedImportsDatasetGenerator.s3Path | quote }}
    filename: {{ $c.failedImportsDatasetGenerator.filename | quote }}
    aws_access_key_id: {{ $c.failedImportsDatasetGenerator.awsAccessKeyId | quote }}
    aws_secret_access_key: {{ $c.failedImportsDatasetGenerator.awsSecretAccessKey | quote }}
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
    api_key: {{ $c.stripe.apiKey | quote }}
    webhook_secret: {{ $c.stripe.webhookSecret | quote }}
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
