# TFLint — https://github.com/terraform-linters/tflint
#   tflint --init        # install plugins
#   tflint --recursive   # lint all modules
config {
  # Lint locally-referenced child modules too.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Google ruleset — https://github.com/terraform-linters/tflint-ruleset-google
plugin "google" {
  enabled = true
  version = "0.31.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
