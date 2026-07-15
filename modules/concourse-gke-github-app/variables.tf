###############################################################################
# Core GCP / cluster identity
###############################################################################

variable "project_id" {
  description = "GCP project ID that hosts the GKE cluster, Secret Manager secret and IAM resources."
  type        = string

  validation {
    condition     = length(var.project_id) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  description = "GCP region / location of the GKE cluster (e.g. \"europe-west1\"). Used for the cluster data source in the root module and for labelling."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EXISTING GKE cluster onto which Concourse is deployed. Used for documentation, labels and root-module wiring."
  type        = string
}

variable "labels" {
  description = "Labels applied to labelable GCP resources (Secret Manager secret) and Kubernetes objects. Keys/values must satisfy GCP label rules (lowercase, <=63 chars)."
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "component"  = "concourse-ci"
  }
}

variable "enable_apis" {
  description = "Whether the module should enable the required Google Cloud APIs. Set to false if APIs are managed elsewhere."
  type        = bool
  default     = true
}

###############################################################################
# Concourse (Helm) configuration
###############################################################################

variable "release_name" {
  description = "Helm release name for Concourse."
  type        = string
  default     = "concourse"
}

variable "namespace" {
  description = "Kubernetes namespace where Concourse (web/worker) is installed. Created by the Helm release. NOTE: Concourse workers usually require privileged containers, so this namespace is intentionally NOT placed under a restricted Pod Security Admission profile."
  type        = string
  default     = "concourse"
}

variable "namespace_prefix" {
  description = "Prefix for Concourse team namespaces used by the Kubernetes credential manager. The team namespace is \"<namespace_prefix><team_name>\". Must match the chart's concourse.web.kubernetes.namespacePrefix."
  type        = string
  default     = "concourse-"
}

variable "team_name" {
  description = "Concourse team whose Kubernetes credential-manager namespace receives the GitHub App token secret."
  type        = string
  default     = "main"
}

variable "chart_version" {
  description = "Version of the official Concourse Helm chart (https://concourse-charts.storage.googleapis.com/). Verify the latest stable version on ArtifactHub before pinning."
  type        = string
  default     = "20.2.3"
}

variable "concourse_external_url" {
  description = "External URL used to reach the Concourse web UI/ATC (e.g. \"https://concourse.example.com\"). Required for correct OAuth redirects."
  type        = string

  validation {
    condition     = can(regex("^https?://", var.concourse_external_url))
    error_message = "concourse_external_url must start with http:// or https://."
  }
}

variable "additional_helm_values" {
  description = "Optional raw YAML string appended to the Helm release values (lowest precedence after module-computed values). Use to configure workers, persistence, ingress, etc. Do NOT place secrets here."
  type        = string
  default     = ""
}

###############################################################################
# GitHub OAuth App -- Concourse UI login ONLY (optional)
#
# This is DISTINCT from the GitHub App used for repository access below.
###############################################################################

variable "github_oauth_client_id" {
  description = "GitHub OAuth App Client ID for Concourse UI login (optional). Leave empty to disable GitHub UI login."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_oauth_client_secret" {
  description = "GitHub OAuth App Client Secret for Concourse UI login (optional). Leave empty to disable GitHub UI login."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_oauth_main_team_user" {
  description = "GitHub username granted admin on the Concourse main team when GitHub UI login is enabled (optional)."
  type        = string
  default     = ""
}

variable "github_oauth_main_team_org" {
  description = "GitHub org whose members are granted access to the Concourse main team when GitHub UI login is enabled (optional)."
  type        = string
  default     = ""
}

variable "concourse_local_users" {
  description = "Optional Concourse local users as \"user:password\" (or \"user:bcrypt\") comma-separated. Used for UI login without GitHub OAuth. Passed to the chart via set_sensitive."
  type        = string
  default     = ""
  sensitive   = true
}

variable "concourse_main_team_local_user" {
  description = "Local username granted admin on the Concourse main team (must exist in concourse_local_users). Optional."
  type        = string
  default     = ""
}

###############################################################################
# GitHub App -- private repository access (pipeline credentials)
###############################################################################

variable "github_app_id" {
  description = "GitHub App ID (the numeric App ID, also usable as the JWT issuer)."
  type        = string

  validation {
    condition     = length(var.github_app_id) > 0
    error_message = "github_app_id must not be empty."
  }
}

variable "github_app_installation_id" {
  description = "GitHub App installation ID (the installation on the org/repos to be accessed)."
  type        = string

  validation {
    condition     = length(var.github_app_installation_id) > 0
    error_message = "github_app_installation_id must not be empty."
  }
}

variable "github_repositories" {
  description = "Optional list of repository NAMES (not full paths) to scope the installation access token to. Empty list = all repositories the installation can access."
  type        = list(string)
  default     = []
}

variable "github_api_url" {
  description = "GitHub REST API base URL. Use https://api.github.com for github.com, or https://HOST/api/v3 for GitHub Enterprise Server."
  type        = string
  default     = "https://api.github.com"
}

variable "github_app_secret_id" {
  description = "Secret Manager secret ID that stores the GitHub App private key (PEM)."
  type        = string
  default     = "concourse-github-app-private-key"
}

variable "github_app_private_key_pem" {
  description = "PEM-encoded GitHub App private key. RECOMMENDED: leave empty and add the secret version out-of-band with `gcloud secrets versions add` so the key never enters Terraform state. If set, a secret version is created by Terraform (stored in state)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_app_secret_version" {
  description = "Secret Manager secret version the token refresher reads (e.g. \"latest\" or a pinned number)."
  type        = string
  default     = "latest"
}

###############################################################################
# Token refresher workload
###############################################################################

variable "service_account_id" {
  description = "Account ID (local part) of the Google service account used by the token refresher. 6-30 chars, lowercase letters/digits/hyphens."
  type        = string
  default     = "concourse-token-refresher"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_id))
    error_message = "service_account_id must be 6-30 chars: lowercase letters, digits, hyphens; start with a letter."
  }
}

variable "token_refresher_namespace" {
  description = "Dedicated Kubernetes namespace for the token refresher CronJob and its service account. Labelled with restricted Pod Security Admission."
  type        = string
  default     = "concourse-token-refresher"
}

variable "kubernetes_service_account_name" {
  description = "Name of the Kubernetes service account the CronJob runs as. Bound to the Google service account via Workload Identity Federation."
  type        = string
  default     = "github-token-refresher"
}

variable "token_refresher_image" {
  description = "Fully-qualified container image (with tag or digest) for the token refresher, e.g. \"REGION-docker.pkg.dev/PROJECT/REPO/concourse-token-refresher:1.0.0\". Build/push with scripts/build-token-refresher-image.sh."
  type        = string

  validation {
    condition     = length(var.token_refresher_image) > 0
    error_message = "token_refresher_image must not be empty."
  }
}

variable "refresh_schedule" {
  description = "Cron schedule for the token refresher. GitHub installation tokens expire after 1 hour; refresh well within that window."
  type        = string
  default     = "*/30 * * * *"
}

variable "token_secret_name" {
  description = "Name of the Kubernetes Secret (in the team namespace) that holds the short-lived GitHub App token. Concourse resolves ((token_secret_name)) to this secret."
  type        = string
  default     = "github-app-token"
}

variable "token_secret_key" {
  description = "Key within the token Secret that holds the token value. Concourse's Kubernetes credential manager reads the \"value\" key by default for ((name)) lookups."
  type        = string
  default     = "value"
}

variable "token_refresher_resources" {
  description = "CPU/memory requests and limits for the token refresher container."
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "250m"
      memory = "256Mi"
    }
  }
}

variable "run_as_user" {
  description = "Numeric UID the token refresher container runs as (must match the image's non-root user)."
  type        = number
  default     = 10001
}
