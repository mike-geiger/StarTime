## Context

See proposal.md — Why.

The relevant existing shape:

- **`GET /health` already exists** as an unauthenticated Lambda in its own stack, described in the code as proving the deploy pipeline end to end. It currently returns `{"status":"ok"}` and nothing else. `HealthStack` publishes a `HealthApiUrl` output, which `with-ephemeral-stack.sh` exports as `STARTIME_HEALTH_API_URL`.
- **`bin/startime.ts` is the only place that knows the stage**, read from `--context stage=`. Every stack is constructed there.
- **`deploy-prod.sh` already ends by printing the outputs file**, which contains `HealthApiUrl` for the stage just deployed. It runs under `set -euo pipefail`, so any failing command aborts it.
- **`RestLambda` bundles with `minify: true, sourceMap: true`.** Source maps embed absolute paths, which is why a synth to a different `--output` directory changes every asset hash — the false positive that motivated this change.

## Goals / Non-Goals

**Goals:**

- One `curl` answers "what revision is live", with no AWS credentials and no CDK.
- The value cannot drift from reality: it is whatever was bundled, not whatever the runtime can infer.
- A prod deploy that silently fails to take effect becomes a loud failure.
- Diff noise stays bounded to a single function.

**Non-Goals:**

- Reporting per-stack revisions. One marker, on the stack whose stated job is proving the pipeline.
- Blocking dirty deploys. Making them visible is the goal; refusing them is a policy decision this change does not make.
- Any change to the other four stacks or the twenty-plus Lambdas in them.

## Decisions

### The revision is resolved at synth time in `bin/startime.ts`

`git rev-parse --short HEAD` and `git status --porcelain` run during synthesis, and the results are passed into `HealthStack` as props, which sets them as environment variables on the health Lambda.

Synthesis is the only moment that sees both the repository and the deployment. The Lambda cannot see the repository at all, and CloudFormation cannot see it either — so anything resolved later would describe the runtime rather than the source.

*Alternative — a runtime lookup.* There is nothing to look up: a bundled, minified Lambda carries no git metadata.

*Alternative — read `CODEBUILD_*`/CI environment variables.* There is no CI here; deploys run from a developer machine via `deploy-prod.sh`.

**Git must not be able to break synthesis.** If either command fails — no git, a tarball checkout, a detached worktree — the value falls back to `unknown` rather than throwing. A synth that cannot run because git hiccuped would be a worse failure than an unlabelled deploy. `unknown` never equals a real `HEAD`, so the verification gate treats it as a mismatch and fails loudly, which is the correct outcome.

### Only the health Lambda carries the marker

The commit lands in exactly one function's environment. Every other Lambda is untouched.

This is the whole reason the marker lives on `/health` rather than being attached to the API. A Lambda environment variable is part of the CloudFormation template, so a commit SHA on every function would add a diff line per function on every commit — turning `cdk diff`, the review step `deploy-prod.sh` prints before asking for confirmation, into noise that hides real changes. One noisy function is an acceptable price; twenty is not.

**A build timestamp is deliberately excluded** for the same reason, only worse: it changes on every synth, so the health Lambda would show a diff even when re-deploying the identical commit. Commit plus dirty flag identifies a build without that.

### The marker's guarantee is deliberately narrow, and the script covers the rest

`/health` reporting the expected commit proves the Health stack deployed. It does not prove the API stack did.

That gap is closed by ordering rather than by more markers: `deploy-prod.sh` runs `set -e`, and `cdk deploy --all` exits non-zero if any stack fails, so verification only ever runs after every stack succeeded. The check confirms a deploy that already reported success — it is a second opinion, not the primary guard.

*Alternative — a `CfnOutput` carrying the commit on every stack.* More precise, but reading outputs requires AWS credentials and the CLI, which forfeits the one property that makes this useful: checkable from anywhere, by anything that can make an HTTP request.

### Verification is a step in `deploy-prod.sh`, after the deploy

The script already writes `--outputs-file outputs/prod.json`; the health URL is read from there rather than hardcoded, so the check follows whatever was just deployed.

The comparison is against the same `git rev-parse --short HEAD` the synth used. Three outcomes: match → report verified; mismatch → report the expected and actual values and exit non-zero; unreachable or unparseable → exit non-zero. **An unreachable endpoint must never read as a pass** — the common cause would be a deploy that did not produce a working API, which is precisely what this is meant to catch.

A short retry with a delay covers the gap between CloudFormation reporting complete and the API Gateway stage serving the new integration. A handful of attempts a couple of seconds apart, then failure.

**Dirty deploys are reported, not refused.** If `HEAD` is dirty the script says so plainly — prod would be running code that exists in no commit — but proceeds. Refusing would be a policy this change has no mandate to impose, and the endpoint records the fact either way.

## Risks / Trade-offs

- **The health Lambda now shows a diff on every commit.** → Intended and bounded to one function. If it ever becomes annoying, the escape hatch is to drop the marker to `HEAD`'s tree hash, which changes only when tracked content changes — but that is less useful to a human reading it.
- **A commit SHA becomes publicly readable.** → The endpoint is already public and the repository is private; a short hash identifies a build without describing it. The spec pins the response to exactly four fields so this does not quietly grow into a description of the deployment's internals.
- **`git` invoked during synthesis couples synth to the working tree.** → Bounded by the `unknown` fallback: synthesis never fails because of it, and the gate turns `unknown` into a visible failure rather than a silent pass.
- **Verification could pass while a later-deploying stack failed.** → Not possible in the current script, because `set -e` aborts before verification. Worth preserving deliberately: verification must stay *after* the deploy and must not be reachable when the deploy failed.
- **Ephemeral test stacks also carry the marker.** → Harmless, and mildly useful: `with-ephemeral-stack.sh` already exports `STARTIME_HEALTH_API_URL`, so a test run can assert it is exercising the code it just built.

## Migration Plan

No data or API compatibility concerns. `/health` gains fields; nothing consumes it today except the example in `with-ephemeral-stack.sh`, which checks only that the request succeeds.

1. Verify on an ephemeral stage: `/health` reports the current commit, and a deliberately wrong expected value makes the gate fail.
2. Deploy to prod. The first run is also the first real exercise of the gate.

**Rollback:** revert the three backend files and the script and redeploy. The endpoint returns to `{"status":"ok"}`; nothing depends on the added fields.
