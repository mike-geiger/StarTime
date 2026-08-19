## Why

After deploying the backend there is no cheap way to answer "is my code actually live?"

The only reliable check today is `cdk diff --all --context stage=prod` reporting zero differences. That works, but it takes around ninety seconds, needs AWS credentials and the whole CDK toolchain, and is sensitive to *how* you invoke it: synthesizing to a non-default `--output` directory re-bundles every Lambda with different absolute paths in its source maps, which changes every asset hash and reports all five stacks as changed when nothing has changed at all. That false positive is not hypothetical — it happened while verifying a real prod deploy, and briefly looked like an incomplete rollout.

A deploy either landed or it didn't. Confirming which should not require the toolchain that performed it.

## What Changes

- **`GET /health` reports what is deployed**, not just that something is: the stage it belongs to, the git commit the running code was built from, and whether that build came from a dirty working tree.
- **The commit is captured at synthesis time** from the repository being deployed, so it describes the code that was actually bundled rather than anything the running process discovers about itself.
- **`deploy-prod.sh` verifies its own deploy.** After a successful `cdk deploy --all` it reads `/health` and compares the reported commit against local `HEAD`, failing loudly on a mismatch instead of leaving the operator to infer success from scrolling CloudFormation output.
- **The marker is confined to the health Lambda.** Every value baked into a Lambda's environment appears in `cdk diff`; putting a commit on all twenty-plus functions would add a diff line to each one on every commit and bury real changes in noise.
- **No build timestamp.** A timestamp changes on every synth, which would make the health Lambda show a permanent diff even when nothing changed. The commit and dirty flag together already identify a build.

### Non-goals

- **Per-stack version reporting.** The marker proves the Health stack deployed; it is a confirmation of a deploy that already succeeded, not a replacement for the deploy's own exit code. Reporting a commit per stack would need a `CfnOutput` on each, which costs the ability to check with a plain `curl`.
- **Reporting the iOS client's version.** This is about the deployed backend. The app ships through a different pipeline entirely.
- **Deploy history, rollback tooling, or a deployments dashboard.** One endpoint answering one question.
- **Authenticating `/health`.** It stays unauthenticated, which constrains what it may disclose — see the spec.

## Capabilities

### New Capabilities

- `deployment-verification`: What a running backend reports about its own provenance, and how a deploy confirms it took effect.

### Modified Capabilities

None. No existing capability describes the health endpoint or the deploy scripts.

## Impact

**Backend** (`backend/cdk/`)

- `bin/startime.ts` — resolves the commit and dirty flag at synth and passes them to the health stack.
- `lib/health-stack.ts` — accepts them as props and sets them as Lambda environment variables.
- `lambda/health/handler.ts` — returns them alongside the existing `status`.
- No change to the other four stacks, and no change to any other Lambda.

**Scripts**

- `backend/scripts/deploy-prod.sh` — post-deploy verification gate; exits non-zero on mismatch.

**Operational consequences**

- `cdk diff` will show a changed environment variable on the health Lambda whenever `HEAD` moves. That is the intended cost, deliberately limited to one function.
- Deploying from a dirty tree is not blocked, but it becomes visible: `/health` reports `dirty: true`, and prod is then running code that exists in no commit.
