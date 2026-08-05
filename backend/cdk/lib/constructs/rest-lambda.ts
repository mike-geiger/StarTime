import { Duration } from 'aws-cdk-lib';
import { Runtime } from 'aws-cdk-lib/aws-lambda';
import { NodejsFunction, NodejsFunctionProps } from 'aws-cdk-lib/aws-lambda-nodejs';
import { Construct } from 'constructs';

export interface RestLambdaProps extends Partial<NodejsFunctionProps> {
  entry: string;
  environment?: Record<string, string>;
}

/** Thin wrapper around NodejsFunction with the defaults every StarTime API Lambda shares. */
export class RestLambda extends NodejsFunction {
  constructor(scope: Construct, id: string, props: RestLambdaProps) {
    super(scope, id, {
      runtime: Runtime.NODEJS_24_X,
      memorySize: 256,
      timeout: Duration.seconds(10),
      bundling: {
        minify: true,
        sourceMap: true,
      },
      ...props,
    });
  }
}
