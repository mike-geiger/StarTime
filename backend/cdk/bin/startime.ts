#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import * as path from 'node:path';
import { App } from 'aws-cdk-lib';
import { HealthStack } from '../lib/health-stack';
import { AuthStack } from '../lib/auth-stack';
import { DataStack } from '../lib/data-stack';
import { ApiStack } from '../lib/api-stack';
import { RealtimeStack } from '../lib/realtime-stack';

/**
 * Runs a git command against this repository, or returns undefined.
 *
 * Deliberately swallows every failure -- missing git, a tarball checkout, a
 * detached worktree. A synth that dies because git hiccuped would be a worse
 * outcome than an unlabelled deploy, and `unknown` can never equal a real
 * HEAD, so deploy-prod.sh turns it into a loud verification failure rather
 * than a silent pass.
 */
function git(...args: string[]): string | undefined {
  try {
    return execFileSync('git', args, {
      cwd: path.join(__dirname, '..'),
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return undefined;
  }
}

const app = new App();
const stage = (app.node.tryGetContext('stage') as string | undefined) ?? 'dev';

// Resolved here because synthesis is the only moment that sees both the
// repository and the deployment: the Lambda can't see the repo at all, so
// anything it worked out at request time would describe the runtime rather
// than the source it was built from.
const commit = git('rev-parse', '--short', 'HEAD') ?? 'unknown';
const dirty = (git('status', '--porcelain') ?? '') !== '';

// Only the health stack gets the marker. A Lambda environment variable is
// part of the CloudFormation template, so putting the commit on all twenty-odd
// functions would add a diff line to each one on every commit and bury real
// changes in the `cdk diff` that deploy-prod.sh prints before asking for
// confirmation. A build timestamp is excluded for the same reason, only
// worse: it would change on every synth, even re-deploying the same commit.
new HealthStack(app, `StarTime-Health-${stage}`, { stage, commit, dirty });
const auth = new AuthStack(app, `StarTime-Auth-${stage}`, { stage });
const data = new DataStack(app, `StarTime-Data-${stage}`, { stage });
new ApiStack(app, `StarTime-Api-${stage}`, {
  stage,
  userPool: auth.userPool,
  table: data.table,
});
new RealtimeStack(app, `StarTime-Realtime-${stage}`, {
  stage,
  userPool: auth.userPool,
  userPoolClient: auth.userPoolClient,
  table: data.table,
});
