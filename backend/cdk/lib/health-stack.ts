import * as path from 'node:path';
import { CfnOutput, Stack, StackProps } from 'aws-cdk-lib';
import { LambdaIntegration, RestApi } from 'aws-cdk-lib/aws-apigateway';
import { Construct } from 'constructs';
import { RestLambda } from './constructs/rest-lambda';

export interface HealthStackProps extends StackProps {
  stage: string;
  /** Short git revision this deployment was built from; see bin/startime.ts. */
  commit: string;
  /** Whether that build came from a tree with uncommitted changes. */
  dirty: boolean;
}

/**
 * Proves the deploy pipeline end to end: one unauthenticated GET /health
 * Lambda, which also reports which revision is actually serving.
 *
 * That last part is why this endpoint earns its keep. The alternative way to
 * answer "is my code live" is `cdk diff` against the stage, which needs AWS
 * credentials and the CDK toolchain and takes about a minute -- and which
 * misreports every asset as changed if you synth to a non-default --output,
 * because sourceMap bundling embeds absolute paths.
 */
export class HealthStack extends Stack {
  public readonly api: RestApi;

  constructor(scope: Construct, id: string, props: HealthStackProps) {
    super(scope, id, props);

    const handler = new RestLambda(this, 'HealthHandler', {
      entry: path.join(__dirname, '../lambda/health/handler.ts'),
      environment: {
        STAGE: props.stage,
        BUILD_COMMIT: props.commit,
        BUILD_DIRTY: String(props.dirty),
      },
    });

    this.api = new RestApi(this, 'HealthApi', {
      restApiName: `startime-health-${props.stage}`,
      deployOptions: { stageName: props.stage },
    });
    this.api.root.addResource('health').addMethod('GET', new LambdaIntegration(handler));

    new CfnOutput(this, 'HealthApiUrl', { value: this.api.url });
  }
}
