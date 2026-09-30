"""Assemble the configurator input and hand over to configurator.py.

Inputs:
  /config/base/config.yaml  non-secret config (ConfigMap optscale-config)
  /config/overlays/*.yaml   secret-bearing etcd config (optional Secret),
                            deep-merged over the `etcd:` branch
  environment               credentials from the component Secrets

The merged file only ever exists on a memory-backed volume.
"""
import glob
import os
import sys
from urllib.parse import quote

import etcd
import yaml
from optscale_client.config_client.client import Client

BASE = "/config/base/config.yaml"
OVERLAYS = "/config/overlays/*.yaml"
OUTPUT = "/work/config.yaml"

MARIADB_BRANCHES = ("authdb", "heralddb", "restdb", "kataradb", "slackerdb",
                    "jirabusdb", "subspectordb")

# Released configurator images cannot replace etcd keys that changed between
# leaf and directory, so these rewritable branches are dropped first
# (mirrors optscale-deploy/compose/docker-compose.yml).
TELEMETRY_KEYS = ("/opentelemetry", "/auth/opentelemetry",
                  "/restapi/opentelemetry", "/diworker/opentelemetry")


def merge(dst, src):
    for key, value in src.items():
        if isinstance(value, dict) and isinstance(dst.get(key), dict):
            merge(dst[key], value)
        else:
            dst[key] = value


def main():
    env = os.environ
    with open(BASE) as f:
        config = yaml.safe_load(f)
    conf = config["etcd"]
    for path in sorted(glob.glob(OVERLAYS)):
        with open(path) as f:
            merge(conf, yaml.safe_load(f) or {})

    for branch in MARIADB_BRANCHES:
        conf[branch]["password"] = env["MARIADB_PASSWORD"]
    if env.get("MONGO_URL"):
        conf["mongo"]["url"] = env["MONGO_URL"]
    else:
        creds = "%s:%s@" % (quote(env["MONGO_USERNAME"], safe=""),
                            quote(env["MONGO_PASSWORD"], safe=""))
        conf["mongo"]["url"] = conf["mongo"]["url"].replace(
            "mongodb://", "mongodb://" + creds, 1)
    conf["rabbit"]["user"] = env["RABBITMQ_USERNAME"]
    conf["rabbit"]["pass"] = env["RABBITMQ_PASSWORD"]
    conf["minio"]["access"] = env["MINIO_ACCESS_KEY"]
    conf["minio"]["secret"] = env["MINIO_SECRET_KEY"]
    conf["clickhouse"]["password"] = env["CLICKHOUSE_PASSWORD"]
    conf["secret"]["cluster"] = env["CLUSTER_SECRET"]
    conf["encryption_key"] = env["ENCRYPTION_KEY"]
    conf["encryption_salt"] = env["ENCRYPTION_SALT"]
    conf["encryption_salt_auth"] = env["ENCRYPTION_SALT_AUTH"]
    conf["bi_settings"]["encryption_key"] = env["BI_ENCRYPTION_KEY"]

    client = Client(host=env["HX_ETCD_HOST"], port=int(env["HX_ETCD_PORT"]))
    for key in TELEMETRY_KEYS:
        try:
            client.delete(key, recursive=True)
        except etcd.EtcdKeyNotFound:
            pass

    fd = os.open(OUTPUT, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        yaml.safe_dump(config, f, default_flow_style=False)
    os.execv(sys.executable, [sys.executable,
                              "docker_images/configurator/configurator.py",
                              OUTPUT])


if __name__ == "__main__":
    main()
