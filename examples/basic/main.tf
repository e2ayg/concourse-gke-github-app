###############################################################################
# Example: deploy Concourse + GitHub App onboarding onto an existing GKE cluster
#
# This root module configures the google/kubernetes/helm providers against an
# EXISTING GKE cluster and invokes modules/concourse-gke-github-app.
#
# Provider auth uses a short-lived OAuth2 access token from the Google provider
# (data.google_client_config) -- no static kubeconfig or service-account key.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Short-lived access token for the caller's active gcloud credentials.
data "google_client_config" "default" {}

# Read the existing cluster's endpoint and CA certificate.
data "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

locals {
  cluster_host = "https://${data.google_container_cluster.this.endpoint}"
  cluster_ca   = base64decode(data.google_container_cluster.this.master_auth[0].cluster_ca_certificate)
}

provider "kubernetes" {
  host                   = local.cluster_host
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = local.cluster_ca
}

# Helm provider v3: kubernetes access is an attribute block.
provider "helm" {
  kubernetes = {
    host                   = local.cluster_host
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = local.cluster_ca
  }
}

module "concourse" {
  source = "../../modules/concourse-gke-github-app"

  # Core identity
  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
  labels       = var.labels

  # Concourse / Helm
  concourse_external_url = var.concourse_external_url
  chart_version          = var.chart_version
  namespace              = var.namespace
  team_name              = var.team_name

  # GitHub App (repository access)
  github_app_id              = var.github_app_id
  github_app_installation_id = var.github_app_installation_id
  github_repositories        = var.github_repositories
  # Leave github_app_private_key_pem unset: add the Secret Manager version
  # out-of-band (see README) so the key never enters Terraform state.

  # Token refresher image (build/push first with scripts/build-token-refresher-image.sh)
  token_refresher_image = var.token_refresher_image

  # Optional: GitHub OAuth App for Concourse UI login
  github_oauth_client_id      = var.github_oauth_client_id
  github_oauth_client_secret  = var.github_oauth_client_secret
  github_oauth_main_team_user = var.github_oauth_main_team_user
  github_oauth_main_team_org  = var.github_oauth_main_team_org

  # Optional: local user login (alternative/addition to GitHub OAuth)
  concourse_local_users          = var.concourse_local_users
  concourse_main_team_local_user = var.concourse_main_team_local_user
}
