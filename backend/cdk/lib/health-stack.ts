import * as path from 'node:path';
import { CfnOutput, Stack, StackProps } from 'aws-cdk-lib';
import { LambdaIntegration, RestApi } from 'aws-cdk-lib/aws-apigateway';
import { Construct } from 'constructs';
import { RestLambda } from './constructs/rest-lambda';

export interface HealthStackProps extends StackProps {
  stage: string;
}

/** Proves the deploy pipeline end to end: one unauthenticated GET /health Lambda. */
export class HealthStack extends Stack {
  public readonly api: RestApi;

  constructor(scope: Construct, id: string, props: HealthStackProps) {
    super(scope, id, props);

    const handler = new RestLambda(this, 'HealthHandler', {
      entry: path.join(__dirname, '../lambda/health/handler.ts'),
    });

    this.api = new RestApi(this, 'HealthApi', {
      restApiName: `startime-health-${props.stage}`,
      deployOptions: { stageName: props.stage },
    });
    this.api.root.addResource('health').addMethod('GET', new LambdaIntegration(handler));

    new CfnOutput(this, 'HealthApiUrl', { value: this.api.url });
  }
}
