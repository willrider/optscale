"""Create missing OptScale credential Secrets from /spec/spec.json.

Secrets that already exist keep every existing key; only keys missing from
them are added. Nothing is ever overwritten. Uses the pod's service account
and the Kubernetes API directly (stdlib only).
"""
import base64
import json
import os
import secrets
import ssl
import string
import sys
import urllib.error
import urllib.request

SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"
SPEC = "/spec/spec.json"
ALNUM = string.ascii_letters + string.digits


def generate(field):
    if "value" in field:
        return field["value"]
    kind = field["generate"]
    if kind == "alnum":
        return "".join(secrets.choice(ALNUM) for _ in range(field["length"]))
    if kind == "fernet":
        return base64.urlsafe_b64encode(secrets.token_bytes(32)).decode()
    raise ValueError("unknown generator %r" % kind)


def b64(text):
    return base64.b64encode(text.encode()).decode()


class Api:
    def __init__(self):
        with open(os.path.join(SA_DIR, "token")) as f:
            self.token = f.read().strip()
        with open(os.path.join(SA_DIR, "namespace")) as f:
            namespace = f.read().strip()
        self.base = "https://%s:%s/api/v1/namespaces/%s/secrets" % (
            os.environ["KUBERNETES_SERVICE_HOST"],
            os.environ["KUBERNETES_SERVICE_PORT"], namespace)
        self.ctx = ssl.create_default_context(
            cafile=os.path.join(SA_DIR, "ca.crt"))

    def call(self, method, path="", body=None,
             content_type="application/json"):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            self.base + path, data=data, method=method,
            headers={"Authorization": "Bearer " + self.token,
                     "Content-Type": content_type,
                     "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, context=self.ctx,
                                        timeout=30) as resp:
                return resp.status, json.load(resp)
        except urllib.error.HTTPError as exc:
            return exc.code, None


def ensure(api, item, labels):
    name = item["name"]
    status, current = api.call("GET", "/" + name)
    if status == 404:
        body = {"apiVersion": "v1", "kind": "Secret", "type": "Opaque",
                "metadata": {"name": name, "labels": labels},
                "data": {key: b64(generate(field))
                         for key, field in item["data"].items()}}
        status, _ = api.call("POST", body=body)
        if status != 201:
            sys.exit("creating %s failed: HTTP %s" % (name, status))
        print("created %s (%s)" % (name, ", ".join(sorted(item["data"]))))
        return
    if status != 200:
        sys.exit("reading %s failed: HTTP %s" % (name, status))
    present = (current.get("data") or {}).keys()
    missing = {key: b64(generate(field))
               for key, field in item["data"].items() if key not in present}
    if not missing:
        print("%s: present" % name)
        return
    status, _ = api.call("PATCH", "/" + name, {"data": missing},
                         "application/merge-patch+json")
    if status != 200:
        sys.exit("updating %s failed: HTTP %s" % (name, status))
    print("%s: added missing keys %s" % (name, ", ".join(sorted(missing))))


def main():
    with open(SPEC) as f:
        spec = json.load(f)
    api = Api()
    for item in spec["secrets"]:
        ensure(api, item, spec.get("labels", {}))


if __name__ == "__main__":
    main()
