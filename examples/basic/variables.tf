variable "project_id" {
  description = "GCP project ID hosting the GKE cluster and IAM/Secret Manager resources."
  type        = string
}

variable "region" {
  description = "GCP region / location of the existing GKE cluster."
  type        = string
}

variable "cluster_name" {
  description = "Name of the existing GKE cluster."
  type        = string
}

variable "labels" {
  description = "Labels applied to labelable GCP resources and Kubernetes objects."
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "component"  = "concourse-ci"
  }
}

variable "concourse_external_url" {
  description = "External URL of the Concourse web UI/ATC (e.g. https://concourse.example.com)."
  type        = string
}

variable "chart_version" {
  description = "Concourse Helm chart version."
  type        = string
  default     = "20.2.3"
}

variable "namespace" {
  description = "Namespace where Concourse is installed."
  type        = string
  default     = "concourse"
}

variable "team_name" {
  description = "Concourse team whose credential-manager namespace receives the token secret."
  type        = string
  default     = "main"
}

variable "github_app_id" {
  description = "GitHub App ID (repository access)."
  type        = string
}

variable "github_app_installation_id" {
  description = "GitHub App installation ID."
  type        = string
}

variable "github_repositories" {
  description = "Optional repo NAMES to scope installation tokens to (empty = all)."
  type        = list(string)
  default     = []
}

variable "token_refresher_image" {
  description = "Fully-qualified token refresher container image (with tag/digest)."
  type        = string
}

variable "github_oauth_client_id" {
  description = "GitHub OAuth App Client ID for Concourse UI login (optional). Prefer TF_VAR_github_oauth_client_id."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_oauth_client_secret" {
  description = "GitHub OAuth App Client Secret for Concourse UI login (optional). Prefer TF_VAR_github_oauth_client_secret."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_oauth_main_team_user" {
  description = "GitHub username granted admin on the main team (optional)."
  type        = string
  default     = ""
}

variable "github_oauth_main_team_org" {
  description = "GitHub org granted access to the main team (optional)."
  type        = string
  default     = ""
}

variable "concourse_local_users" {
  description = "Optional Concourse local users as \"user:password\" (prefer TF_VAR_concourse_local_users)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "concourse_main_team_local_user" {
  description = "Local username granted admin on the main team (optional)."
  type        = string
  default     = ""
}
