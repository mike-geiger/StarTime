#!/usr/bin/env bash
set -euo pipefail

# Deploys the persistent `prod` stack set -- the one holding real family data.
#
# Deliberately NOT with-ephemeral-stack.sh: that script always tears down on
# exit, and generates its own stage name so it can never target prod. This one
# has no teardown path at all. `prod` is also the only stage where the Cognito
# User Pool and DynamoDB table use RemovalPolicy.RETAIN (see auth-stack.ts /
# data-stack.ts), so even `cdk destroy` leaves the data behind.
#
# Usage:
#   backend/scripts/deploy-prod.sh          # diff, then confirm
#   backend/scripts/deploy-prod.sh --yes    # skip the prompt (non-interactive)
#
# --yes skips the confirmation, not the diff: the diff is still printed so
# there is always a record of what changed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDK_DIR="$SCRIPT_DIR/../cdk"

ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

EXPECTED_COMMIT="$(git -C "$CDK_DIR" rev-parse --short HEAD)"

# Not a blocker -- just refuses to be quiet about it. Deploying a dirty tree
# means prod ends up running code that exists in no commit, and /health will
# say so afterwards (dirty: true).
if [[ -n "$(git -C "$CDK_DIR" status --porcelain)" ]]; then
  echo "!! WARNING: uncommitted changes in the working tree."
  echo "!! Prod would run code that exists in no commit. /health will report dirty:true."
  echo
fi

# Run against the default cdk.out on purpose. Passing --output elsewhere
# re-bundles every Lambda, and because RestLambda builds with sourceMap:true
# the absolute paths baked into each bundle change -- which reports all five
# stacks as changed when nothing has.
echo "==> Diffing prod (review before confirming)..."
(cd "$CDK_DIR" && npx cdk diff --all --context stage=prod) || true

if [[ "$ASSUME_YES" != true ]]; then
  read -r -p "Deploy these changes to PROD? [y/N] " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "Aborted."; exit 1; }
fi

(cd "$CDK_DIR" && npx cdk deploy --all \
  --require-approval never \
  --context stage=prod \
  --outputs-file "$CDK_DIR/outputs/prod.json")

echo
echo "==> Prod outputs (needed for the app build):"
cat "$CDK_DIR/outputs/prod.json"

# --- Verify the deploy actually took effect ---------------------------------
#
# `cdk deploy` exiting 0 and the new code actually serving traffic are two
# different claims. This checks the second one by asking the deployment what
# revision it is running.
#
# It runs here, after the deploy, and inside `set -e` on purpose: a failed
# deploy aborts the script before reaching this point, so a deploy that failed
# can never be reported as verified. This confirms a deploy that already
# succeeded -- it is a second opinion, not the primary guard.

HEALTH_URL="$(node -e '
  const data = require(process.argv[1]);
  for (const outputs of Object.values(data)) {
    if (outputs.HealthApiUrl) { console.log(outputs.HealthApiUrl); break; }
  }
' "$CDK_DIR/outputs/prod.json")"

if [[ -z "$HEALTH_URL" ]]; then
  echo "!! No HealthApiUrl among the prod outputs -- cannot verify the deploy." >&2
  exit 1
fi

echo
echo "==> Verifying prod is serving $EXPECTED_COMMIT..."

ACTUAL_COMMIT=""
for _ in 1 2 3 4 5; do
  # API Gateway can briefly serve the previous integration after
  # CloudFormation reports complete, so one miss isn't yet a failure.
  # `|| true` keeps a failed curl from tripping `set -e` mid-retry.
  response="$(curl -fsS --max-time 10 "${HEALTH_URL%/}/health" 2>/dev/null || true)"
  if [[ -n "$response" ]]; then
    ACTUAL_COMMIT="$(node -e '
      try {
        process.stdout.write(String(JSON.parse(process.argv[1]).commit ?? ""));
      } catch {
        process.stdout.write("");
      }
    ' "$response")"
  fi
  [[ -n "$ACTUAL_COMMIT" ]] && break
  sleep 2
done

if [[ -z "$ACTUAL_COMMIT" ]]; then
  echo "!! Could not read a commit from ${HEALTH_URL%/}/health after 5 attempts." >&2
  echo "!! Treating this as a FAILED deploy: an unreachable or unparseable health" >&2
  echo "!! endpoint is exactly what a broken deploy looks like, so it must never" >&2
  echo "!! be read as a pass." >&2
  exit 1
fi

if [[ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]]; then
  echo "!! DEPLOY DID NOT TAKE EFFECT" >&2
  echo "!!   expected: $EXPECTED_COMMIT" >&2
  echo "!!   serving:  $ACTUAL_COMMIT" >&2
  exit 1
fi

echo "==> Verified: prod is serving $ACTUAL_COMMIT."
