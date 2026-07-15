output "concourse_namespace" {
  description = "Namespace where Concourse is installed."
  value       = module.concourse.concourse_namespace
}

output "team_namespace" {
  description = "Team namespace holding the GitHub App token secret."
  value       = module.concourse.team_namespace
}

output "token_refresher_namespace" {
  description = "Namespace running the token refresher CronJob."
  value       = module.concourse.token_refresher_namespace
}

output "google_service_account_email" {
  description = "Email of the token refresher Google service account."
  value       = module.concourse.google_service_account_email
}

output "kubernetes_service_account_name" {
  description = "Kubernetes service account the CronJob runs as."
  value       = module.concourse.kubernetes_service_account_name
}

output "secret_manager_secret_id" {
  description = "Secret Manager secret ID storing the GitHub App private key."
  value       = module.concourse.secret_manager_secret_id
}

output "helm_release_name" {
  description = "Concourse Helm release name."
  value       = module.concourse.helm_release_name
}

output "token_secret_name" {
  description = "Kubernetes Secret name holding the short-lived token (reference as ((name)))."
  value       = module.concourse.token_secret_name
}
