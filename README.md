# Concourse on GKE with GitHub App authentication

Production-ready Terraform module and supporting tooling to onboard **Concourse CI**
onto an **existing GKE cluster**, with **GitHub App installation tokens** for private
repository access in pipelines and an **optional GitHub OAuth App** for UI login.

> **Two different GitHub identities — do not confuse them:**
> - **GitHub OAuth App** → *only* for Concourse **UI login** (who may log into the web/`fly`).
> - **GitHub App** → for **pipeline access to repositories** via short-lived
>   **installation access tokens** (`x-access-token` / `((github-app-token))`).

---

## Contents

```
.
├── modules/concourse-gke-github-app/   # the reusable Terraform module
│   ├── main.tf  variables.tf  outputs.tf  versions.tf  README.md
├── examples/basic/                     # runnable example root module
│   ├── main.tf  terraform.tfvars.example  README.md
├── scripts/
│   ├── build-token-refresher-image.sh  # build & push the refresher image
│   └── verify-onboarding.sh            # read-only verification
├── token-refresher/                    # refresher container source
│   ├── Dockerfile  refresh_token.py  requirements.txt
└── pipelines/
    └── example-pipeline.yml            # private-repo checkout example
```

---

## Architecture

```
                         ┌──────────────────────── GKE cluster ───────────────────────┐
                         │                                                             │
  Google Secret Manager  │   ns: concourse                    ns: <prefix><team>       │
  ┌───────────────────┐  │   ┌────────────────┐               (e.g. concourse-main)    │
  │ GitHub App        │  │   │ Concourse web  │  Kubernetes    ┌───────────────────┐   │
  │ private key (PEM) │  │   │  (ATC)         │  cred manager  │ Secret            │   │
  └─────────┬─────────┘  │   │                │──────reads────▶│ github-app-token  │   │
            │            │   └────────────────┘                │  key: value       │   │
   roles/secretmanager   │                                     └─────────▲─────────┘   │
   .secretAccessor       │   ns: concourse-token-refresher               │ patch       │
   (single secret)       │   ┌──────────────────────────┐                │ (RBAC:      │
            │            │   │ CronJob (batch/v1)        │────────────────┘  1 secret) │
            ▼            │   │  reads key ─▶ JWT ─▶       │                             │
  ┌───────────────────┐  │   │  installation token       │  runs as KSA                │
  │ Google service    │◀─┼───│  github-token-refresher   │  (restricted PSA namespace) │
  │ account (GSA)     │  │   └──────────────────────────┘                             │
  └─────────▲─────────┘  │              │ ADC via metadata server                      │
            │            │              │ (Workload Identity Federation)               │
            └────────────┼──────────────┘                                              │
     roles/iam.workloadIdentityUser  (KSA ⇄ GSA)                                       │
                         └─────────────────────────────────────────────────────────────┘
```

**Flow:** the CronJob authenticates to Google Cloud through **Workload Identity
Federation** (no static keys), reads the GitHub App private key from **Secret
Manager**, mints a **GitHub App JWT**, exchanges it for a **GitHub installation
access token**, and patches that short-lived token into a Kubernetes Secret.
Concourse's **Kubernetes credential manager** exposes it to pipelines as
`((github-app-token))`.

---

## Prerequisites

- An **existing GKE cluster** with **Workload Identity enabled**
  (Autopilot clusters have it on by default; on Standard set the cluster's
  workload identity pool to `PROJECT_ID.svc.id.goog`).
  See [Use Workload Identity Federation for GKE](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity).
- Tools: `terraform >= 1.5`, `gcloud`, `kubectl`, `docker` (or `podman`),
  Concourse `fly`.
- GCP IAM to manage Secret Manager, service accounts and IAM bindings in the project.
- A **GitHub App** installed on the target repos/org, and (optionally) a
  **GitHub OAuth App** for UI login.
- An **Artifact Registry** Docker repository for the refresher image.

> **Concourse workers & Autopilot:** Concourse workers usually require
> **privileged** containers (containerd/runc). Privileged pods are **not**
> permitted on GKE **Autopilot**, so the Concourse workers themselves generally
> need **GKE Standard**. Everything this module deploys (the token refresher,
> its namespace, RBAC and manifests) is **Autopilot-compatible** and hardened.
> Configure workers via `additional_helm_values` to match your cluster.

---

## Required GCP APIs

The module enables these when `enable_apis = true`
([`google_project_service`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_project_service)):

| API | Purpose |
|-----|---------|
| `container.googleapis.com` | GKE |
| `secretmanager.googleapis.com` | Store the GitHub App private key |
| `iam.googleapis.com` | Service accounts & IAM |
| `iamcredentials.googleapis.com` | Workload Identity token exchange |
| `cloudresourcemanager.googleapis.com` | Project-level IAM management |

---

## GitHub OAuth App setup (Concourse UI login — optional)

Follow [Creating an OAuth app](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app):

1. GitHub → **Settings → Developer settings → OAuth Apps → New OAuth App**.
2. **Homepage URL** = your `concourse_external_url`.
3. **Authorization callback URL** = `https://<concourse_external_url>/sky/issuer/callback`.
4. Copy the **Client ID** and generate a **Client Secret**.
5. Provide them via environment variables (keep them out of `.tfvars`):
   ```bash
   export TF_VAR_github_oauth_client_id='Iv1.xxxxxxxx'
   export TF_VAR_github_oauth_client_secret='xxxxxxxxxxxxxxxx'
   ```
   and set `github_oauth_main_team_user` / `github_oauth_main_team_org`.

Concourse GitHub UI auth reference:
[Concourse — GitHub auth](https://concourse-ci.org/github-auth.html).

---

## GitHub App setup (repository access for pipelines)

Follow [Registering a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app)
and [Authenticating as a GitHub App installation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation):

1. GitHub → **Settings → Developer settings → GitHub Apps → New GitHub App**.
2. **Repository permissions → Contents: Read-only** (least privilege for checkout).
   Add more only if pipelines need them.
3. **Install** the App on the target org/repositories.
4. Note the **App ID** (`github_app_id`) and the **Installation ID**
   (`github_app_installation_id`; visible in the installation URL
   `.../settings/installations/<installation_id>`).
5. Generate a **private key** (PEM) and store it in Secret Manager **out-of-band**
   (recommended — keeps it out of Terraform state):
   ```bash
   # Create the secret container with Terraform (module does this), then:
   gcloud secrets versions add concourse-github-app-private-key \
     --project="$PROJECT_ID" \
     --data-file=/path/to/github-app.private-key.pem
   ```
   See [Add a secret version](https://cloud.google.com/secret-manager/docs/add-secret-version).
6. Optionally scope tokens to specific repos with `github_repositories`
   ([Create an installation access token](https://docs.github.com/en/rest/apps/apps#create-an-installation-access-token-for-an-app)).

**Token expiry:** installation tokens last **1 hour**; the CronJob refreshes on
`refresh_schedule` (default every 30 min).

---

## Terraform usage

All commands below are **safe** (read/inspect only). `apply`/`destroy` are
explicitly gated — see the warning at the end.

```bash
cd examples/basic
cp terraform.tfvars.example terraform.tfvars   # edit values; keep secrets in TF_VAR_*

# Format & validate (no cloud calls):
terraform fmt -recursive
terraform init -backend=false
terraform validate

# Preview changes (read-only; requires cloud auth for data sources):
terraform init
terraform plan
```

Build/push the refresher image **before** `apply` (the image ref is a required
input):

```bash
PROJECT_ID=my-proj REGION=europe-west1 REPO=concourse TAG=1.0.0 \
  ./scripts/build-token-refresher-image.sh --create-repo
```

> ⚠️ **Destructive commands (`terraform apply`, `terraform destroy`) are NOT run
> here and require your explicit confirmation.** Review `terraform plan` first,
> then run them yourself when you are ready.

---

## Image build / push flow

`scripts/build-token-refresher-image.sh`:

1. (Optional `--create-repo`) creates the Artifact Registry Docker repo.
2. Configures Docker auth via `gcloud auth configure-docker`.
3. Builds `token-refresher/` for `linux/amd64` and pushes it.
4. Prints the `token_refresher_image` value to set in `terraform.tfvars`.

Docs: [Artifact Registry — pushing & pulling](https://cloud.google.com/artifact-registry/docs/docker/pushing-and-pulling).

---

## Verification steps

After `apply` (which you run yourself):

```bash
PROJECT_ID=my-proj \
GSA_EMAIL="$(terraform -chdir=examples/basic output -raw google_service_account_email)" \
TEAM_NS="$(terraform -chdir=examples/basic output -raw team_namespace)" \
TOKEN_REFRESHER_NS="$(terraform -chdir=examples/basic output -raw token_refresher_namespace)" \
  ./scripts/verify-onboarding.sh
```

It checks (read-only): the Secret Manager secret + enabled version, the
least-privilege IAM binding, the Workload Identity binding, the KSA annotation,
the namespace PSA label, the namespace-scoped RBAC role, the CronJob, and whether
the token secret has been populated. It offers to trigger the CronJob once
(with confirmation).

Then set a pipeline:

```bash
fly -t main login -c "$CONCOURSE_URL"
fly -t main set-pipeline -p example -c pipelines/example-pipeline.yml
fly -t main unpause-pipeline -p example
fly -t main trigger-job -j example/build -w
```

---

## Security model

- **No static service-account keys.** The refresher authenticates to Google Cloud
  via **Workload Identity Federation** (KSA ⇄ GSA), the recommended GKE pattern.
  ([WIF for GKE](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity))
- **Least-privilege IAM.** The GSA holds `roles/secretmanager.secretAccessor` on
  the **single** GitHub App key secret only
  ([`google_secret_manager_secret_iam_member`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam)).
- **Namespace-scoped RBAC with `resourceNames`.** The CronJob may only `get`/`patch`
  the **one** token secret
  ([`kubernetes_role_v1`](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_v1)).
- **Short-lived tokens.** GitHub installation tokens expire in 1 hour; JWTs are
  capped at 10 minutes.
- **Hardened, Autopilot-compatible pods.** Non-root (`runAsNonRoot`, UID 10001),
  `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, all capabilities
  dropped, `seccompProfile: RuntimeDefault`, resource requests/limits — in a
  namespace labelled with **restricted Pod Security Admission**
  ([PSA](https://kubernetes.io/docs/concepts/security/pod-security-admission/)).
- **No hard-coded secrets.** Secret values come from variables/`TF_VAR_*`; the
  private key is added out-of-band by default and never enters Terraform state.
- **Secrets stay sensitive in plan.** OAuth client id/secret and local users are
  passed with Helm `set_sensitive`.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| CronJob pod: `PermissionDenied` on Secret Manager | GSA missing `secretAccessor`, or WIF not wired. Check `verify-onboarding.sh` steps 2–4; confirm cluster Workload Identity is enabled. |
| Pod cannot reach GCP metadata / ADC fails | KSA annotation `iam.gke.io/gcp-service-account` missing/incorrect, or `workloadIdentityUser` member wrong. Member must be `serviceAccount:PROJECT_ID.svc.id.goog[NS/KSA]`. |
| `403` creating installation token | Wrong `github_app_installation_id`, App lacks **Contents: Read** permission, or the App is not installed on the repo. |
| `((github-app-token))` unresolved in pipeline | Secret must be named `github-app-token` (key `value`) in the **team** namespace `<prefix><team>`; ensure the CronJob has run and Concourse `kubernetes.enabled` is true. |
| Secret exists but empty `value` | CronJob hasn't run yet — trigger once: `kubectl -n <refresher-ns> create job manual --from=cronjob/github-token-refresher`. |
| Concourse workers `CrashLoopBackOff` / privileged denied | Likely Autopilot rejecting privileged workers. Use GKE Standard for workers, or adjust worker config in `additional_helm_values`. |
| RBAC `cannot patch resource "secrets"` | The token secret name must match the RBAC `resourceNames`; keep `token_secret_name` consistent. |
| Git checkout `Authentication failed` | Token expired (refresh interval too long) or username not `x-access-token`. |

---

## References (official documentation)

- Terraform **Google** provider — <https://registry.terraform.io/providers/hashicorp/google/latest/docs>
- Terraform **Kubernetes** provider — <https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs>
- Terraform **Helm** provider — <https://registry.terraform.io/providers/hashicorp/helm/latest/docs>
- GKE **Workload Identity Federation** — <https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity>
- Google **Secret Manager** — <https://cloud.google.com/secret-manager/docs>
- **GitHub App** authentication (JWT + installation tokens) — <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app>
- **GitHub OAuth App** — <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app>
- Concourse **Kubernetes credential manager** — <https://concourse-ci.org/kubernetes-credential-manager.html>
- Concourse **GitHub auth** — <https://concourse-ci.org/github-auth.html>
- Concourse **Helm chart** — <https://github.com/concourse/concourse-chart>
- Kubernetes **Pod Security Admission** — <https://kubernetes.io/docs/concepts/security/pod-security-admission/>
