## 1. Capture the revision at synth time

- [x] 1.1 In `backend/cdk/bin/startime.ts`, resolve the short commit via `git rev-parse --short HEAD` and the dirty flag via a non-empty `git status --porcelain`, both run from the CDK directory.
- [x] 1.2 Wrap both in a helper that returns `'unknown'` / `false` if git is unavailable or exits non-zero, so synthesis can never fail because of it.
- [x] 1.3 Pass `commit` and `dirty` into `HealthStack`'s props alongside the existing `stage`. Leave the other four stack constructions untouched.

## 2. Surface it on the health endpoint

- [x] 2.1 Extend `HealthStackProps` with `commit: string` and `dirty: boolean`, and set them (plus `stage`) as environment variables on the health `RestLambda`. Do not add them to any other Lambda.
- [x] 2.2 Update `backend/cdk/lambda/health/handler.ts` to return `{ status, stage, commit, dirty }`, reading the three new values from the environment and defaulting to `'unknown'` / `false` when absent.
- [x] 2.3 Confirm the response carries exactly those four fields — no paths, env dumps, account or resource ids.
- [x] 2.4 Run `npx tsc --noEmit` in `backend/cdk`.

## 3. Verify the deploy in `deploy-prod.sh`

- [x] 3.1 After the `cdk deploy --all` step, read `HealthApiUrl` for the prod stage out of `outputs/prod.json` rather than hardcoding it.
- [x] 3.2 Curl `<HealthApiUrl>health` and parse the `commit` field, retrying a few times a couple of seconds apart to cover the gap between CloudFormation completing and the API Gateway stage serving the new integration.
- [x] 3.3 Compare against the same `git rev-parse --short HEAD` used at synth: on match print a clear verified line; on mismatch print expected vs actual and `exit 1`.
- [x] 3.4 Treat an unreachable, non-2xx, or unparseable response as a failure and `exit 1` — never as a pass.
- [x] 3.5 When `HEAD` is dirty, print a plain warning that prod will be running code that exists in no commit, and continue rather than refusing.
- [x] 3.6 Keep verification strictly after the deploy and inside `set -e`, so a failed deploy aborts before it and can never be reported as verified.
- [x] 3.7 Shellcheck-clean the script by inspection: quote the URL and the parsed values, and don't let a failing `curl` in a pipeline be swallowed.

## 4. Verify against a real stack

- [x] 4.1 Through `backend/scripts/with-ephemeral-stack.sh`, curl `$STARTIME_HEALTH_API_URL/health` and assert it reports the current `HEAD` short commit and `dirty` matching the tree's actual state.
- [x] 4.2 In the same run, assert the endpoint still answers without any credentials.
- [x] 4.3 Prove the gate fails as designed: run the comparison against a deliberately wrong expected commit and confirm a non-zero exit; and point it at an unreachable URL and confirm it also exits non-zero rather than passing.
- [x] 4.4 Confirm the blast radius: `npx cdk diff --all --context stage=prod` (default `cdk.out`, no `--output`) shows the environment change on the health Lambda only, and no other function.

## 5. Documentation

- [x] 5.1 Update CLAUDE.md: `/health` now reports `{status, stage, commit, dirty}`; the commit is resolved at synth in `bin/startime.ts` and carried only by the health Lambda to keep `cdk diff` readable; no timestamp, deliberately; and `deploy-prod.sh` fails if the deployed commit doesn't match `HEAD`.
- [x] 5.2 Record the `--output` trap next to the diff guidance: `cdk diff` must run against the default `cdk.out`, because `sourceMap: true` bakes absolute paths into every bundle and a different output directory reports all five stacks as changed when nothing has.
