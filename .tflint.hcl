# TFLint — https://github.com/terraform-linters/tflint
#   tflint --init        # (no-op: only the bundled terraform ruleset is used)
#   tflint --recursive   # lint all modules
config {
  # Lint locally-referenced child modules too.
  call_module_type = "local"
}

# Bundled Terraform ruleset (no external download/signature verification).
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# NOTE: the external tflint-ruleset-google plugin was intentionally removed.
# `tflint --init` currently crashes verifying external-plugin attestations
# (sigstore VerifyTransparencyLogInclusion nil deref) across tflint versions,
# and its value for this IAM/Secret/K8s-focused module is marginal. Re-add once
# the upstream signature-verification crash is fixed:
#   plugin "google" {
#     enabled = true
#     version = "0.31.0"
#     source  = "github.com/terraform-linters/tflint-ruleset-google"
#   }
