#!/usr/bin/env bash
set -euo pipefail

# Deploys a stable, reusable stack set and runs the given command against it
# -- unlike with-ephemeral-stack.sh, it does NOT tear down on exit. Built for
# the "edit code, re-run one failing test, repeat a dozen times" debugging
# loop, where with-ephemeral-stack.sh's create-then-always-destroy cycle pays
# a full ~1-3min AWS deploy *and* a full teardown on every single attempt.
#
# Because the stage name is stable across invocations, every re-run after the
# first is an incremental `cdk deploy` -- CloudFormation only touches what
# actually changed -- instead of standing up all five stacks from scratch.
# The stack is left running between invocations; destroy it yourself when
# you're done debugging (this script prints the exact command every time).
#
# Usage:
#   backend/scripts/with-dev-stack.sh -- <command...>
#
# Example debugging loop:
#   backend/scripts/with-dev-stack.sh -- node backend/cdk/scripts/verify-checklist-completion.mjs
#   # edit a Lambda handler
#   backend/scripts/with-dev-stack.sh -- node backend/cdk/scripts/verify-checklist-completion.mjs
#   # ...repeat as needed...
#   (cd backend/cdk && npx cdk destroy --all --context stage="dev-$(whoami)")
#
# Override the stage (e.g. to keep two debug sessions separate) with
# STARTIME_DEV_STAGE.

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
STAGE="${STARTIME_DEV_STAGE:-dev-$(whoami)}"
OUTPUTS_FILE="$CDK_DIR/outputs/$STAGE.json"

mkdir -p "$CDK_DIR/outputs"

echo "==> Deploying stack(s) for stage '$STAGE' (incremental after the first run)..."
(cd "$CDK_DIR" && npx cdk deploy --all --require-approval never --context stage="$STAGE" --outputs-file "$OUTPUTS_FILE")

echo "==> Stack outputs (from $OUTPUTS_FILE):"
cat "$OUTPUTS_FILE"

# Flatten every stack's CfnOutputs into STARTIME_<OUTPUT_KEY_UPPER_SNAKE> env
# vars (e.g. HealthApiUrl -> STARTIME_HEALTH_API_URL) -- same convention as
# with-ephemeral-stack.sh, kept in sync deliberately.
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

if [[ -n "${STARTIME_API_BASE_URL:-}" ]]; then
  export STARTIME_API_HOST="${STARTIME_API_BASE_URL#https://}"
  export STARTIME_API_SCHEME="https"
fi
if [[ -n "${STARTIME_WEB_SOCKET_URL:-}" ]]; then
  export STARTIME_WS_HOST="${STARTIME_WEB_SOCKET_URL#wss://}"
  export STARTIME_WS_SCHEME="wss"
fi

echo "==> Running: $*"
set +e
"$@"
STATUS=$?
set -e

echo
echo "==> Stack for stage '$STAGE' left running -- re-run this script to iterate quickly."
echo "==> When done debugging, tear it down:"
echo "      (cd \"$CDK_DIR\" && npx cdk destroy --all --context stage=\"$STAGE\")"

exit $STATUS
