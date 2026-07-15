# Example: basic

A runnable root module that configures the `google`, `kubernetes` and `helm`
providers against an **existing** GKE cluster and invokes
[`../../modules/concourse-gke-github-app`](../../modules/concourse-gke-github-app).

Provider auth uses a short-lived OAuth2 token from
`data.google_client_config` — no kubeconfig or static keys.

## Steps

```bash
# 1. Authenticate to GCP (interactive; run yourself):
#    ! gcloud auth application-default login
#    ! gcloud config set project <PROJECT_ID>

# 2. Configure inputs
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars. Keep secrets OUT of the file — use env vars:
export TF_VAR_github_oauth_client_id='...'      # optional (UI login)
export TF_VAR_github_oauth_client_secret='...'  # optional (UI login)
export TF_VAR_concourse_local_users='admin:...' # optional (local login)

# 3. Build & push the token refresher image, then set token_refresher_image
PROJECT_ID=my-proj REGION=europe-west1 REPO=concourse TAG=1.0.0 \
  ../../scripts/build-token-refresher-image.sh --create-repo

# 4. Store the GitHub App private key out-of-band (after first apply creates the
#    secret container), so it never lands in Terraform state:
#    ! gcloud secrets versions add concourse-github-app-private-key \
#        --project="$PROJECT_ID" --data-file=github-app.private-key.pem

# 5. Safe checks
terraform fmt -recursive
terraform init -backend=false
terraform validate

# 6. Preview (read-only)
terraform init
terraform plan
```

> ⚠️ `terraform apply` and `terraform destroy` are **not** run for you and
> require your explicit confirmation. Review `terraform plan` first.

## After apply

```bash
PROJECT_ID=my-proj \
GSA_EMAIL="$(terraform output -raw google_service_account_email)" \
TEAM_NS="$(terraform output -raw team_namespace)" \
TOKEN_REFRESHER_NS="$(terraform output -raw token_refresher_namespace)" \
  ../../scripts/verify-onboarding.sh
```

## Notes

- `region` must be the cluster's **location** (region for regional clusters,
  zone for zonal — adjust the `location` in the `google_container_cluster` data
  source accordingly).
- The GitHub App private key is intentionally **not** passed through Terraform in
  this example; add it out-of-band (step 4).
