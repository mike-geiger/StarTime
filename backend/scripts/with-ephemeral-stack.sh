#!/usr/bin/env bash
set -euo pipefail

# Deploys a fresh, uniquely-named AWS stack set (all stacks in the CDK app,
# suffixed with a one-off `stage`), runs the given test command against it
# with its outputs exported as env vars, and always tears the stack(s) down
# afterward -- success or failure. Mirrors StarTimeUITests' own
# cleanup-on-failure philosophy, just at the infrastructure level.
#
# Usage:
#   backend/scripts/with-ephemeral-stack.sh -- <command...>
#
# Example:
#   backend/scripts/with-ephemeral-stack.sh -- curl -sf "$STARTIME_HEALTH_API_URL/health"

if [[ "${1:-}" != "--" ]]; then
  echo "Usage: $0 -- <command...>" >&2
  exit 1
fi
shift

if [[ $# -eq 0 ]]; then
  echo "No command given after '--'" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDK_DIR="$SCRIPT_DIR/../cdk"
RUN_ID="$(date +%Y%m%d%H%M%S)-$RANDOM"
STAGE="test-$RUN_ID"
OUTPUTS_FILE="$CDK_DIR/outputs/$STAGE.json"

mkdir -p "$CDK_DIR/outputs"

cleanup() {
  echo "==> Destroying ephemeral stack(s) for stage '$STAGE'..."
  (cd "$CDK_DIR" && npx cdk destroy --all --force --context stage="$STAGE") || \
    echo "!! cdk destroy failed for stage '$STAGE' -- check the AWS console/CloudFormation for orphaned resources under that stage." >&2
  rm -f "$OUTPUTS_FILE"
}
trap cleanup EXIT

echo "==> Deploying ephemeral stack(s) for stage '$STAGE'..."
(cd "$CDK_DIR" && npx cdk deploy --all --require-approval never --context stage="$STAGE" --outputs-file "$OUTPUTS_FILE")

echo "==> Stack outputs (from $OUTPUTS_FILE):"
cat "$OUTPUTS_FILE"

# Flatten every stack's CfnOutputs into STARTIME_<OUTPUT_KEY_UPPER_SNAKE> env
# vars (e.g. HealthApiUrl -> STARTIME_HEALTH_API_URL) so the command below --
# and, later, an xcodebuild test invocation -- can read them without this
# script needing to know about any particular phase's specific output names.
while IFS='=' read -r env_key env_value; do
  export "STARTIME_${env_key}=${env_value}"
done < <(node -e "
  const fs = require('fs');
  const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
  for (const stackOutputs of Object.values(data)) {
    for (const [key, value] of Object.entries(stackOutputs)) {
      const snake = key.replace(/([a-z0-9])([A-Z])/g, '\$1_\$2').toUpperCase();
      console.log(snake + '=' + value);
    }
  }
" "$OUTPUTS_FILE")

# The app's xcconfig stores the API scheme and host separately, because "//"
# starts a comment in xcconfig syntax -- so split the deployed base URL here
# rather than making every caller do it.
if [[ -n "${STARTIME_API_BASE_URL:-}" ]]; then
  export STARTIME_API_HOST="${STARTIME_API_BASE_URL#https://}"
  export STARTIME_API_SCHEME="https"
fi
if [[ -n "${STARTIME_WEB_SOCKET_URL:-}" ]]; then
  export STARTIME_WS_HOST="${STARTIME_WEB_SOCKET_URL#wss://}"
  export STARTIME_WS_SCHEME="wss"
fi

echo "==> Running: $*"
"$@"
