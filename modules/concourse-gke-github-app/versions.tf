###############################################################################
# Provider & Terraform version constraints
#
# Versions are pinned with conservative `~>` constraints. Verify the latest
# stable releases before use:
#   - hashicorp/google:     https://registry.terraform.io/providers/hashicorp/google/latest
#   - hashicorp/kubernetes: https://registry.terraform.io/providers/hashicorp/kubernetes/latest
#   - hashicorp/helm:       https://registry.terraform.io/providers/hashicorp/helm/latest
#
# NOTE: This module declares the providers it REQUIRES but does not configure
# them. Provider configuration (cluster endpoint, auth token, CA cert) must be
# supplied by the root module (see examples/basic). This keeps the module
# reusable across clusters and environments.
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
      version = "~> 2.30"
    }

    # Helm provider v3 uses the terraform-plugin-framework. `set`/`set_sensitive`
    # are LIST-OF-OBJECT attributes (not nested blocks) and the provider
    # `kubernetes` config is an attribute. See the example root module.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}
