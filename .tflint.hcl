# TFLint — https://github.com/terraform-linters/tflint
#   tflint --init        # downloads + verifies the google ruleset (needs tflint >= 0.64.0)
#   tflint --recursive   # lint all modules
config {
  # Lint locally-referenced child modules too.
  call_module_type = "local"
}

# Bundled Terraform ruleset.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Google ruleset. Requires tflint >= 0.64.0: earlier versions crash in
# `tflint --init` while verifying the plugin's sigstore attestation
# (nil deref in bundle.TlogEntries; fixed in terraform-linters/tflint#2597).
plugin "google" {
  enabled = true
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
