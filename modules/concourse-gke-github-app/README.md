# Module: `concourse-gke-github-app`

Deploys Concourse (official Helm chart) onto an existing GKE cluster and onboards
GitHub App installation-token access for pipelines, using Workload Identity
Federation, Secret Manager, least-privilege IAM, namespace-scoped RBAC, and a
hardened refresher CronJob.

This module **requires but does not configure** the `google`, `kubernetes` and
`helm` providers — configure them in the root module (see
[`examples/basic`](../../examples/basic)).

## Usage

```hcl
module "concourse" {
  source = "path/to/modules/concourse-gke-github-app"

  project_id             = "my-proj"
  region                 = "europe-west1"
  cluster_name           = "my-cluster"
  concourse_external_url = "https://concourse.example.com"

  github_app_id              = "123456"
  github_app_installation_id = "78901234"
  github_repositories        = ["my-private-repo"]

  token_refresher_image = "europe-west1-docker.pkg.dev/my-proj/concourse/concourse-token-refresher:1.0.0"

  # Optional UI login (GitHub OAuth App) — pass secrets via TF_VAR_*:
  github_oauth_client_id      = var.github_oauth_client_id
  github_oauth_client_secret  = var.github_oauth_client_secret
  github_oauth_main_team_user = "my-username"
}
```

## Provider requirements

| Provider | Version | Verified with |
|----------|---------|---------------|
| `hashicorp/google` | `~> 7.0` | 7.40.0 |
| `hashicorp/kubernetes` | `~> 3.2` | 3.2.1 |
| `hashicorp/helm` | `~> 3.0` | 3.2.0 |
| Terraform | `>= 1.5.0` | 1.14.0 |

## Inputs (selected)

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project_id` | string | — | GCP project ID (required) |
| `region` | string | — | Cluster location (required) |
| `cluster_name` | string | — | Existing GKE cluster name (required) |
| `concourse_external_url` | string | — | External Concourse URL (required) |
| `github_app_id` | string | — | GitHub App ID (required) |
| `github_app_installation_id` | string | — | GitHub App installation ID (required) |
| `token_refresher_image` | string | — | Refresher container image (required) |
| `github_repositories` | list(string) | `[]` | Repo names to scope the token (empty = all) |
| `github_api_url` | string | `https://api.github.com` | GitHub REST base URL (GHES supported) |
| `chart_version` | string | `20.2.3` | Concourse Helm chart version |
| `namespace` | string | `concourse` | Concourse install namespace |
| `namespace_prefix` | string | `concourse-` | Team namespace prefix |
| `team_name` | string | `main` | Concourse team |
| `github_app_secret_id` | string | `concourse-github-app-private-key` | Secret Manager secret ID |
| `github_app_private_key_pem` | string (sensitive) | `""` | Optional; empty = add version out-of-band |
| `github_app_secret_version` | string | `latest` | Secret version the refresher reads |
| `service_account_id` | string | `concourse-token-refresher` | GSA account ID |
| `token_refresher_namespace` | string | `concourse-token-refresher` | Refresher namespace (restricted PSA) |
| `kubernetes_service_account_name` | string | `github-token-refresher` | KSA name |
| `refresh_schedule` | string | `*/30 * * * *` | CronJob schedule |
| `token_secret_name` | string | `github-app-token` | Token secret name (`((...))`) |
| `token_secret_key` | string | `value` | Key inside the token secret |
| `token_refresher_resources` | object | 50m/128Mi → 250m/256Mi | Requests/limits |
| `github_oauth_client_id` | string (sensitive) | `""` | UI login (optional) |
| `github_oauth_client_secret` | string (sensitive) | `""` | UI login (optional) |
| `github_oauth_main_team_user` | string | `""` | main-team admin user (OAuth) |
| `github_oauth_main_team_org` | string | `""` | main-team org (OAuth) |
| `concourse_local_users` | string (sensitive) | `""` | `user:pass` local login (optional) |
| `concourse_main_team_local_user` | string | `""` | main-team admin (local user) |
| `additional_helm_values` | string | `""` | Extra raw YAML for the chart (e.g. workers) |
| `labels` | map(string) | `{managed-by, component}` | Resource labels |
| `enable_apis` | bool | `true` | Enable required GCP APIs |
| `run_as_user` | number | `10001` | Container UID (matches image) |

See [`variables.tf`](./variables.tf) for the full set, validations and descriptions.

## Outputs

| Name | Description |
|------|-------------|
| `concourse_namespace` | Concourse install namespace |
| `team_namespace` | Team namespace holding the token secret |
| `token_refresher_namespace` | Refresher CronJob namespace |
| `google_service_account_email` | Refresher GSA email |
| `google_service_account_id` | Refresher GSA resource name |
| `kubernetes_service_account_name` | Refresher KSA name |
| `secret_manager_secret_id` | GitHub App key secret ID |
| `secret_manager_secret_name` | Fully-qualified secret resource name |
| `helm_release_name` | Concourse Helm release name |
| `helm_release_version` | Deployed chart version |
| `token_secret_name` | Token secret name for `((...))` |
| `github_app_private_key_version_created` | Whether TF created the key version |

## Notes

- At least one Concourse auth method must be configured (GitHub OAuth **or** a
  main-team local user) — enforced by a `precondition` on the Helm release.
- The token secret uses `lifecycle { ignore_changes = [data] }` so Terraform does
  not revert the CronJob's writes.
- Team-namespace resources (token secret + RBAC) `depend_on` the Helm release,
  which creates the team namespace via the chart's Kubernetes credential manager.

## Validate

```bash
terraform fmt -recursive
terraform init -backend=false
terraform validate
```
