#!/usr/bin/env node
import { App } from 'aws-cdk-lib';
import { HealthStack } from '../lib/health-stack';
import { AuthStack } from '../lib/auth-stack';
import { DataStack } from '../lib/data-stack';
import { ApiStack } from '../lib/api-stack';
import { RealtimeStack } from '../lib/realtime-stack';

const app = new App();
const stage = (app.node.tryGetContext('stage') as string | undefined) ?? 'dev';
const firebaseWebApiKey = app.node.tryGetContext('firebaseWebApiKey') as string | undefined;

new HealthStack(app, `StarTime-Health-${stage}`, { stage });
const auth = new AuthStack(app, `StarTime-Auth-${stage}`, { stage, firebaseWebApiKey });
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
