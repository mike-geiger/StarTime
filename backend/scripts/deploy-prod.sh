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
