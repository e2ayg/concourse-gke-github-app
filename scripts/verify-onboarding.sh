#!/usr/bin/env bash
#
# Read-only verification of the Concourse + GitHub App onboarding.
#
# This script ONLY inspects resources. The single optional action (triggering
# the CronJob once) requires explicit interactive confirmation.
#
# Prerequisites: gcloud + kubectl authenticated against the target project/cluster.
#
# Usage:
#   PROJECT_ID=my-proj \
#   TOKEN_REFRESHER_NS=concourse-token-refresher \
#   TEAM_NS=concourse-main \
#   SECRET_ID=concourse-github-app-private-key \
#   GSA_EMAIL=concourse-token-refresher@my-proj.iam.gserviceaccount.com \
#   KSA_NAME=github-token-refresher \
#   TOKEN_SECRET=github-app-token \
#     scripts/verify-onboarding.sh

set -euo pipefail

PROJECT_ID="${PROJECT_ID:?Set PROJECT_ID}"
TOKEN_REFRESHER_NS="${TOKEN_REFRESHER_NS:-concourse-token-refresher}"
TEAM_NS="${TEAM_NS:-concourse-main}"
SECRET_ID="${SECRET_ID:-concourse-github-app-private-key}"
GSA_EMAIL="${GSA_EMAIL:?Set GSA_EMAIL (google_service_account_email output)}"
KSA_NAME="${KSA_NAME:-github-token-refresher}"
TOKEN_SECRET="${TOKEN_SECRET:-github-app-token}"
TOKEN_SECRET_KEY="${TOKEN_SECRET_KEY:-value}"
CRONJOB_NAME="${CRONJOB_NAME:-github-token-refresher}"

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
info() { printf '  \033[36mINFO\033[0m %s\n' "$1"; }

echo "== 1. Secret Manager secret exists =="
if gcloud secrets describe "${SECRET_ID}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  pass "secret '${SECRET_ID}' exists"
  if gcloud secrets versions list "${SECRET_ID}" --project="${PROJECT_ID}" \
      --filter="state=ENABLED" --format="value(name)" | grep -q .; then
    pass "secret has an ENABLED version"
  else
    fail "secret has NO enabled version -- add one with: gcloud secrets versions add ${SECRET_ID} --data-file=key.pem"
  fi
else
  fail "secret '${SECRET_ID}' not found"
fi

echo "== 2. IAM: least-privilege accessor on the secret =="
if gcloud secrets get-iam-policy "${SECRET_ID}" --project="${PROJECT_ID}" \
    --format=json | grep -q "serviceAccount:${GSA_EMAIL}"; then
  pass "GSA has an IAM binding on the secret"
else
  fail "GSA '${GSA_EMAIL}' not bound on secret IAM policy"
fi

echo "== 3. Workload Identity binding (KSA -> GSA) =="
EXPECTED_MEMBER="serviceAccount:${PROJECT_ID}.svc.id.goog[${TOKEN_REFRESHER_NS}/${KSA_NAME}]"
if gcloud iam service-accounts get-iam-policy "${GSA_EMAIL}" --project="${PROJECT_ID}" \
    --format=json | grep -q "${EXPECTED_MEMBER}"; then
  pass "workloadIdentityUser binding present for ${EXPECTED_MEMBER}"
else
  fail "missing workloadIdentityUser binding for ${EXPECTED_MEMBER}"
fi

echo "== 4. KSA annotation =="
ANNOTATION=$(kubectl -n "${TOKEN_REFRESHER_NS}" get serviceaccount "${KSA_NAME}" \
  -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null || true)
if [[ "${ANNOTATION}" == "${GSA_EMAIL}" ]]; then
  pass "KSA annotated with ${GSA_EMAIL}"
else
  fail "KSA annotation mismatch (got: '${ANNOTATION:-<none>}')"
fi

echo "== 5. Namespace Pod Security Admission =="
PSA=$(kubectl get namespace "${TOKEN_REFRESHER_NS}" \
  -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || true)
if [[ "${PSA}" == "restricted" ]]; then
  pass "namespace enforces restricted PSA"
else
  info "namespace PSA enforce label = '${PSA:-<none>}'"
fi

echo "== 6. RBAC: role scoped to the single token secret =="
if kubectl -n "${TEAM_NS}" get role "${TOKEN_SECRET}-writer" >/dev/null 2>&1; then
  pass "role '${TOKEN_SECRET}-writer' exists in ${TEAM_NS}"
else
  fail "role '${TOKEN_SECRET}-writer' not found in ${TEAM_NS}"
fi

echo "== 7. CronJob present =="
if kubectl -n "${TOKEN_REFRESHER_NS}" get cronjob "${CRONJOB_NAME}" >/dev/null 2>&1; then
  pass "cronjob '${CRONJOB_NAME}' exists"
else
  fail "cronjob '${CRONJOB_NAME}' not found"
fi

echo "== 8. Token secret present in team namespace =="
if kubectl -n "${TEAM_NS}" get secret "${TOKEN_SECRET}" >/dev/null 2>&1; then
  pass "secret '${TOKEN_SECRET}' exists in ${TEAM_NS}"
  LEN=$(kubectl -n "${TEAM_NS}" get secret "${TOKEN_SECRET}" \
    -o jsonpath="{.data.${TOKEN_SECRET_KEY}}" 2>/dev/null | wc -c | tr -d ' ')
  if [[ "${LEN}" -gt 1 ]]; then
    pass "token secret has been populated (non-empty '${TOKEN_SECRET_KEY}')"
  else
    info "token secret is still empty -- run the CronJob once (see below)"
  fi
else
  fail "secret '${TOKEN_SECRET}' not found in ${TEAM_NS}"
fi

echo ""
echo "== Optional: trigger the CronJob once (creates a Job) =="
read -r -p "Create a one-off Job from ${CRONJOB_NAME} now? [y/N] " REPLY
if [[ "${REPLY}" == "y" || "${REPLY}" == "Y" ]]; then
  JOB="manual-refresh-$(date +%s)"
  kubectl -n "${TOKEN_REFRESHER_NS}" create job "${JOB}" --from="cronjob/${CRONJOB_NAME}"
  echo "Created job ${JOB}. Follow logs with:"
  echo "  kubectl -n ${TOKEN_REFRESHER_NS} logs job/${JOB} -f"
else
  echo "Skipped. To trigger manually later:"
  echo "  kubectl -n ${TOKEN_REFRESHER_NS} create job manual-refresh --from=cronjob/${CRONJOB_NAME}"
fi
