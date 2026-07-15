###############################################################################
# concourse-gke-github-app
#
# Deploys Concourse CI onto an existing GKE cluster (official Helm chart) and
# onboards GitHub App installation-token access for pipelines:
#
#   Secret Manager (GitHub App private key)
#        |  roles/secretmanager.secretAccessor (single secret, least privilege)
#        v
#   Google service account  <--- roles/iam.workloadIdentityUser ---  KSA
#        ^                        (Workload Identity Federation)       |
#        |  ADC via GKE metadata server                               | runs as
#        |                                                            v
#   CronJob (token refresher) --patch--> K8s Secret (team ns) <--read-- Concourse
#                                        ((github-app-token))         (k8s creds)
#
# Docs:
#  - Helm provider:        https://registry.terraform.io/providers/hashicorp/helm/latest/docs
#  - Kubernetes provider:  https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
#  - Google provider:      https://registry.terraform.io/providers/hashicorp/google/latest/docs
#  - GKE Workload Identity: https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
#  - Secret Manager:       https://cloud.google.com/secret-manager/docs
#  - Concourse k8s creds:  https://concourse-ci.org/kubernetes-credential-manager.html
###############################################################################

locals {
  # Concourse team namespace managed by the chart's Kubernetes credential
  # manager. Must equal "<namespacePrefix><team>".
  team_namespace = "${var.namespace_prefix}${var.team_name}"

  github_oauth_enabled = var.github_oauth_client_id != "" && var.github_oauth_client_secret != ""

  # Required Google Cloud APIs.
  required_apis = var.enable_apis ? toset([
    "container.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]) : toset([])

  # Workload Identity member binding the KSA to the Google service account.
  # Format: serviceAccount:PROJECT_ID.svc.id.goog[NAMESPACE/KSA_NAME]
  workload_identity_member = "serviceAccount:${var.project_id}.svc.id.goog[${var.token_refresher_namespace}/${var.kubernetes_service_account_name}]"

  # Non-sensitive Helm values rendered as YAML.
  concourse_values = {
    concourse = {
      web = {
        externalUrl = var.concourse_external_url

        auth = merge(
          {
            mainTeam = merge(
              var.concourse_main_team_local_user != "" ? { localUser = var.concourse_main_team_local_user } : {},
              local.github_oauth_enabled ? {
                github = merge(
                  var.github_oauth_main_team_user != "" ? { user = var.github_oauth_main_team_user } : {},
                  var.github_oauth_main_team_org != "" ? { org = var.github_oauth_main_team_org } : {},
                )
              } : {},
            )
          },
          local.github_oauth_enabled ? { github = { enabled = true } } : {},
        )

        # Kubernetes credential manager: Concourse reads pipeline credentials
        # from Secrets in per-team namespaces.
        kubernetes = {
          enabled              = true
          namespacePrefix      = var.namespace_prefix
          teams                = [var.team_name]
          createTeamNamespaces = true
          keepNamespaces       = true
        }
      }
    }
  }

  # Sensitive Helm values passed via set_sensitive so they are masked in plan
  # output. Helm provider v3 uses list-of-object attribute syntax.
  sensitive_sets = concat(
    var.github_oauth_client_id != "" ? [{ name = "secrets.githubClientId", value = var.github_oauth_client_id }] : [],
    var.github_oauth_client_secret != "" ? [{ name = "secrets.githubClientSecret", value = var.github_oauth_client_secret }] : [],
    var.concourse_local_users != "" ? [{ name = "secrets.localUsers", value = var.concourse_local_users }] : [],
  )
}

###############################################################################
# Google Cloud APIs
###############################################################################

resource "google_project_service" "required" {
  for_each = local.required_apis

  project = var.project_id
  service = each.value

  # Do not disable APIs on destroy: other workloads may depend on them.
  disable_on_destroy         = false
  disable_dependent_services = false
}

###############################################################################
# Secret Manager: GitHub App private key
###############################################################################

resource "google_secret_manager_secret" "github_app_key" {
  project   = var.project_id
  secret_id = var.github_app_secret_id
  labels    = var.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

# Optional: create the secret version from Terraform. RECOMMENDED to leave
# github_app_private_key_pem empty and add the version out-of-band with
# `gcloud secrets versions add` so the key never enters Terraform state.
resource "google_secret_manager_secret_version" "github_app_key" {
  count = var.github_app_private_key_pem != "" ? 1 : 0

  secret      = google_secret_manager_secret.github_app_key.id
  secret_data = var.github_app_private_key_pem
}

###############################################################################
# Google service account for the token refresher + least-privilege IAM
###############################################################################

resource "google_service_account" "token_refresher" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "Concourse GitHub App token refresher"
  description  = "Reads the GitHub App private key from Secret Manager for cluster ${var.cluster_name} (${var.region}). Managed by Terraform."

  depends_on = [google_project_service.required]
}

# Least privilege: accessor on the SINGLE GitHub App key secret only.
resource "google_secret_manager_secret_iam_member" "token_refresher_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.github_app_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.token_refresher.email}"
}

# Workload Identity Federation: allow the KSA to impersonate the GSA.
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.token_refresher.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.workload_identity_member
}

###############################################################################
# Concourse via the official Helm chart
###############################################################################

resource "helm_release" "concourse" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = true

  repository = "https://concourse-charts.storage.googleapis.com/"
  chart      = "concourse"
  version    = var.chart_version

  # Module-computed values first, optional caller YAML last (higher precedence).
  values = compact([
    yamlencode(local.concourse_values),
    var.additional_helm_values,
  ])

  set_sensitive = local.sensitive_sets

  wait    = true
  timeout = 600

  lifecycle {
    precondition {
      condition     = local.github_oauth_enabled || var.concourse_main_team_local_user != ""
      error_message = "Configure at least one Concourse auth method: GitHub OAuth (github_oauth_client_id + github_oauth_client_secret) or a main-team local user (concourse_local_users + concourse_main_team_local_user)."
    }
  }
}

###############################################################################
# Token refresher namespace (restricted Pod Security Admission) + KSA
###############################################################################

resource "kubernetes_namespace_v1" "token_refresher" {
  metadata {
    name = var.token_refresher_namespace

    labels = merge(var.labels, {
      # Pod Security Admission (current stable labels).
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    })
  }
}

resource "kubernetes_service_account_v1" "token_refresher" {
  metadata {
    name      = var.kubernetes_service_account_name
    namespace = kubernetes_namespace_v1.token_refresher.metadata[0].name
    labels    = var.labels

    annotations = {
      # Links this KSA to the Google service account (Workload Identity).
      "iam.gke.io/gcp-service-account" = google_service_account.token_refresher.email
    }
  }
}

###############################################################################
# Token Secret + namespace-scoped RBAC (patch ONE secret only)
#
# These live in the chart-managed team namespace, hence depend on the release.
###############################################################################

resource "kubernetes_secret_v1" "github_app_token" {
  metadata {
    name      = var.token_secret_name
    namespace = local.team_namespace
    labels    = var.labels
  }

  type = "Opaque"

  # Placeholder so the secret always exists and RBAC patch works; the CronJob
  # populates the real short-lived token. Ignore data changes so Terraform does
  # not fight the CronJob.
  data = {
    (var.token_secret_key) = ""
  }

  lifecycle {
    ignore_changes = [data]
  }

  depends_on = [helm_release.concourse]
}

resource "kubernetes_role_v1" "token_writer" {
  metadata {
    name      = "${var.token_secret_name}-writer"
    namespace = local.team_namespace
    labels    = var.labels
  }

  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = [var.token_secret_name] # only this secret
    verbs          = ["get", "patch"]
  }

  depends_on = [helm_release.concourse]
}

resource "kubernetes_role_binding_v1" "token_writer" {
  metadata {
    name      = "${var.token_secret_name}-writer"
    namespace = local.team_namespace
    labels    = var.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.token_writer.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.token_refresher.metadata[0].name
    namespace = kubernetes_namespace_v1.token_refresher.metadata[0].name
  }

  depends_on = [helm_release.concourse]
}

###############################################################################
# Token refresher CronJob (batch/v1) -- hardened, Autopilot-compatible
###############################################################################

resource "kubernetes_cron_job_v1" "token_refresher" {
  metadata {
    name      = "github-token-refresher"
    namespace = kubernetes_namespace_v1.token_refresher.metadata[0].name
    labels    = var.labels
  }

  spec {
    schedule                      = var.refresh_schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3
    starting_deadline_seconds     = 120

    job_template {
      metadata {
        labels = var.labels
      }

      spec {
        backoff_limit              = 3
        active_deadline_seconds    = 300
        ttl_seconds_after_finished = 600

        template {
          metadata {
            labels = var.labels
          }

          spec {
            service_account_name            = kubernetes_service_account_v1.token_refresher.metadata[0].name
            automount_service_account_token = true
            restart_policy                  = "Never"

            security_context {
              run_as_non_root = true
              run_as_user     = var.run_as_user
              fs_group        = var.run_as_user

              seccomp_profile {
                type = "RuntimeDefault"
              }
            }

            container {
              name  = "refresher"
              image = var.token_refresher_image

              security_context {
                allow_privilege_escalation = false
                read_only_root_filesystem  = true
                run_as_non_root            = true
                run_as_user                = var.run_as_user

                capabilities {
                  drop = ["ALL"]
                }
              }

              env {
                name  = "GCP_PROJECT"
                value = var.project_id
              }
              env {
                name  = "SECRET_ID"
                value = google_secret_manager_secret.github_app_key.secret_id
              }
              env {
                name  = "SECRET_VERSION"
                value = var.github_app_secret_version
              }
              env {
                name  = "GITHUB_APP_ID"
                value = var.github_app_id
              }
              env {
                name  = "GITHUB_INSTALLATION_ID"
                value = var.github_app_installation_id
              }
              env {
                name  = "GITHUB_API_URL"
                value = var.github_api_url
              }
              env {
                name  = "GITHUB_REPOSITORIES"
                value = join(",", var.github_repositories)
              }
              env {
                name  = "TARGET_NAMESPACE"
                value = local.team_namespace
              }
              env {
                name  = "TARGET_SECRET_NAME"
                value = var.token_secret_name
              }
              env {
                name  = "TARGET_SECRET_KEY"
                value = var.token_secret_key
              }

              resources {
                requests = {
                  cpu    = var.token_refresher_resources.requests.cpu
                  memory = var.token_refresher_resources.requests.memory
                }
                limits = {
                  cpu    = var.token_refresher_resources.limits.cpu
                  memory = var.token_refresher_resources.limits.memory
                }
              }

              # Writable scratch for a read-only root filesystem.
              volume_mount {
                name       = "tmp"
                mount_path = "/tmp"
              }
            }

            volume {
              name = "tmp"
              empty_dir {}
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_role_binding_v1.token_writer,
    kubernetes_secret_v1.github_app_token,
    google_service_account_iam_member.workload_identity,
    google_secret_manager_secret_iam_member.token_refresher_accessor,
  ]
}
