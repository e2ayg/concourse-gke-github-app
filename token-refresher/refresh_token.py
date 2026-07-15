#!/usr/bin/env python3
"""GitHub App installation-token refresher for Concourse on GKE.

Flow (per run):
  1. Read the GitHub App private key (PEM) from Google Secret Manager. Auth to
     GCP uses Application Default Credentials served by the GKE metadata server
     via Workload Identity Federation -- no static service-account key.
  2. Build a short-lived GitHub App JWT (RS256).
  3. Exchange the JWT for an installation access token (optionally scoped to a
     subset of repositories).
  4. Patch the token into a Kubernetes Secret that Concourse's Kubernetes
     credential manager exposes to pipelines as ((github-app-token)).

References (official docs only):
  - GitHub App JWT:        https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app
  - Installation tokens:   https://docs.github.com/en/rest/apps/apps#create-an-installation-access-token-for-an-app
  - Using the token (git): https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation
  - Secret Manager client: https://cloud.google.com/secret-manager/docs/access-secret-version
  - Workload Identity:     https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
"""

from __future__ import annotations

import base64
import logging
import os
import sys
import time

import jwt
import requests
from google.cloud import secretmanager
from kubernetes import client as k8s_client
from kubernetes import config as k8s_config

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("token-refresher")

# GitHub caps App JWTs at 10 minutes. Backdate iat by 60s to tolerate clock
# drift; keep exp - iat <= 600s.
JWT_BACKDATE_SECONDS = 60
JWT_EXPIRY_SECONDS = 540
HTTP_TIMEOUT_SECONDS = 30


def _require_env(name: str) -> str:
    """Read a required environment variable or exit with a clear error."""
    value = os.environ.get(name, "").strip()
    if not value:
        log.error("Missing required environment variable: %s", name)
        sys.exit(2)
    return value


def read_private_key(project: str, secret_id: str, version: str) -> str:
    """Fetch the GitHub App private key (PEM) from Secret Manager."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project}/secrets/{secret_id}/versions/{version}"
    log.info("Accessing Secret Manager version: %s", name)
    response = client.access_secret_version(request={"name": name})
    pem = response.payload.data.decode("utf-8")
    if "PRIVATE KEY" not in pem:
        log.error("Secret payload does not look like a PEM private key.")
        sys.exit(3)
    return pem


def build_app_jwt(app_id: str, private_key_pem: str) -> str:
    """Create a signed GitHub App JWT (RS256)."""
    now = int(time.time())
    payload = {
        "iat": now - JWT_BACKDATE_SECONDS,
        "exp": now + JWT_EXPIRY_SECONDS,
        "iss": app_id,
    }
    return jwt.encode(payload, private_key_pem, algorithm="RS256")


def create_installation_token(
    api_url: str,
    app_jwt: str,
    installation_id: str,
    repositories: list[str],
) -> str:
    """Exchange the App JWT for an installation access token."""
    url = f"{api_url.rstrip('/')}/app/installations/{installation_id}/access_tokens"
    headers = {
        "Authorization": f"Bearer {app_jwt}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    body: dict[str, object] = {}
    if repositories:
        # Scope the token to specific repositories (least privilege).
        body["repositories"] = repositories
        log.info("Scoping installation token to repositories: %s", repositories)

    response = requests.post(
        url, headers=headers, json=body, timeout=HTTP_TIMEOUT_SECONDS
    )
    if response.status_code != 201:
        log.error(
            "GitHub token request failed: %s %s", response.status_code, response.text
        )
        response.raise_for_status()

    data = response.json()
    log.info("Installation token created; expires_at=%s", data.get("expires_at"))
    return data["token"]


def patch_k8s_secret(
    namespace: str, secret_name: str, key: str, token: str
) -> None:
    """Patch the short-lived token into the target Kubernetes Secret."""
    k8s_config.load_incluster_config()
    core = k8s_client.CoreV1Api()
    encoded = base64.b64encode(token.encode("utf-8")).decode("utf-8")
    patch = {"data": {key: encoded}}
    core.patch_namespaced_secret(name=secret_name, namespace=namespace, body=patch)
    log.info(
        "Patched secret %s/%s (key=%s) with a fresh token.",
        namespace,
        secret_name,
        key,
    )


def main() -> int:
    project = _require_env("GCP_PROJECT")
    secret_id = _require_env("SECRET_ID")
    secret_version = os.environ.get("SECRET_VERSION", "latest").strip() or "latest"
    app_id = _require_env("GITHUB_APP_ID")
    installation_id = _require_env("GITHUB_INSTALLATION_ID")
    api_url = os.environ.get("GITHUB_API_URL", "https://api.github.com").strip()
    repositories = [
        r.strip()
        for r in os.environ.get("GITHUB_REPOSITORIES", "").split(",")
        if r.strip()
    ]
    target_namespace = _require_env("TARGET_NAMESPACE")
    target_secret = _require_env("TARGET_SECRET_NAME")
    target_key = os.environ.get("TARGET_SECRET_KEY", "value").strip() or "value"

    private_key = read_private_key(project, secret_id, secret_version)
    app_jwt = build_app_jwt(app_id, private_key)
    token = create_installation_token(api_url, app_jwt, installation_id, repositories)
    patch_k8s_secret(target_namespace, target_secret, target_key, token)
    log.info("Token refresh complete.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # noqa: BLE001 - surface any failure with a non-zero exit
        log.exception("Token refresh failed.")
        sys.exit(1)
