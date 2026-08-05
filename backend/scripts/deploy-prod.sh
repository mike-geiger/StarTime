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
# The Firebase Web API key is needed by the migrate-user Lambda to verify
# existing passwords at first sign-in. It isn't a privileged secret -- it's
# already embedded in the shipped GoogleService-Info.plist -- but it's passed
# in rather than committed.
#
# Usage:
#   FIREBASE_WEB_API_KEY=... backend/scripts/deploy-prod.sh
#   backend/scripts/deploy-prod.sh --from-plist          # read the key locally
#   backend/scripts/deploy-prod.sh --from-plist --yes    # skip the prompt
#
# --yes exists for non-interactive runs. It skips the confirmation, not the
# diff: the diff is still printed so there's always a record of what changed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDK_DIR="$SCRIPT_DIR/../cdk"
PLIST="$SCRIPT_DIR/../../StarTime/GoogleService-Info.plist"

FROM_PLIST=false
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --from-plist) FROM_PLIST=true ;;
    --yes) ASSUME_YES=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$FROM_PLIST" == true ]]; then
  if [[ ! -f "$PLIST" ]]; then
    echo "No GoogleService-Info.plist at $PLIST" >&2
    exit 1
  fi
  FIREBASE_WEB_API_KEY="$(/usr/libexec/PlistBuddy -c 'Print :API_KEY' "$PLIST")"
fi

if [[ -z "${FIREBASE_WEB_API_KEY:-}" ]]; then
  echo "FIREBASE_WEB_API_KEY is required (or pass --from-plist)." >&2
  exit 1
fi

echo "==> Diffing prod (review before confirming)..."
(cd "$CDK_DIR" && npx cdk diff --all --context stage=prod --context firebaseWebApiKey="$FIREBASE_WEB_API_KEY") || true

if [[ "$ASSUME_YES" != true ]]; then
  read -r -p "Deploy these changes to PROD? [y/N] " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "Aborted."; exit 1; }
fi

(cd "$CDK_DIR" && npx cdk deploy --all \
  --require-approval never \
  --context stage=prod \
  --context firebaseWebApiKey="$FIREBASE_WEB_API_KEY" \
  --outputs-file "$CDK_DIR/outputs/prod.json")

echo
echo "==> Prod outputs (needed for the app build):"
cat "$CDK_DIR/outputs/prod.json"
