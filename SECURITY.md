# Security Policy

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue for
anything exploitable.

- Preferred: use GitHub **Private vulnerability reporting**
  (repo → **Security** → **Report a vulnerability**).
  See <https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability>.

Please include affected files/versions, reproduction steps, and impact. We aim
to acknowledge within a few business days.

## Scope

This repository is infrastructure-as-code (Terraform), a small Python token
refresher, and CI configuration. Relevant concerns include:

- IAM / Workload Identity Federation bindings and least-privilege scoping
- Kubernetes RBAC and Pod Security Admission posture
- Secret handling (Secret Manager, Kubernetes Secrets, Terraform state)
- Supply chain (pinned providers, images, GitHub Actions)

## Security model

See the **Security model** section of the [README](./README.md#security-model)
for the design (no static keys, single-secret accessor, namespace-scoped RBAC,
short-lived tokens, hardened non-root containers).

## Automated checks

Every push/PR runs (see `.github/workflows/`):

- **Correctness gates (blocking):** `terraform fmt`, `terraform validate`,
  `actionlint`, `gitleaks`, `bandit`.
- **Advisory scanners (surfaced in the Security tab via SARIF):** `checkov`,
  `trivy`, `tflint`.
- **Supply chain:** `dependabot`, **OpenSSF Scorecard**.

## Handling secrets

- Never commit private keys, tokens, or real `*.tfvars`. `.gitignore` and
  `gitleaks` enforce this.
- The GitHub App private key is stored in Google Secret Manager and, by default,
  added out-of-band so it never enters Terraform state.
