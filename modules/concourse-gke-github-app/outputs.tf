###############################################################################
# Outputs
###############################################################################

output "concourse_namespace" {
  description = "Namespace where Concourse (web/worker) is installed."
  value       = var.namespace
}

output "team_namespace" {
  description = "Concourse team namespace (Kubernetes credential manager) that holds the GitHub App token secret."
  value       = local.team_namespace
}

output "token_refresher_namespace" {
  description = "Namespace running the token refresher CronJob and its service account."
  value       = kubernetes_namespace_v1.token_refresher.metadata[0].name
}

output "google_service_account_email" {
  description = "Email of the Google service account used by the token refresher (Workload Identity)."
  value       = google_service_account.token_refresher.email
}

output "google_service_account_id" {
  description = "Fully-qualified resource name of the Google service account."
  value       = google_service_account.token_refresher.name
}

output "kubernetes_service_account_name" {
  description = "Kubernetes service account the CronJob runs as."
  value       = kubernetes_service_account_v1.token_refresher.metadata[0].name
}

output "secret_manager_secret_id" {
  description = "Short secret ID of the GitHub App private key in Secret Manager."
  value       = google_secret_manager_secret.github_app_key.secret_id
}

output "secret_manager_secret_name" {
  description = "Fully-qualified Secret Manager resource name (projects/PROJECT/secrets/ID)."
  value       = google_secret_manager_secret.github_app_key.id
}

output "helm_release_name" {
  description = "Name of the Concourse Helm release."
  value       = helm_release.concourse.name
}

output "helm_release_version" {
  description = "Chart version of the deployed Concourse Helm release."
  value       = helm_release.concourse.version
}

output "token_secret_name" {
  description = "Name of the Kubernetes Secret (in the team namespace) holding the short-lived GitHub App token. Reference it in pipelines as ((<name>))."
  value       = kubernetes_secret_v1.github_app_token.metadata[0].name
}

output "github_app_private_key_version_created" {
  description = "Whether Terraform created a Secret Manager version for the GitHub App private key (false means it must be added out-of-band)."
  value       = length(google_secret_manager_secret_version.github_app_key) > 0
}
