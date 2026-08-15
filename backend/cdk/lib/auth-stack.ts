import * as path from 'node:path';
import { Aws, CfnOutput, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import {
  AccountRecovery,
  ClientAttributes,
  StringAttribute,
  UserPool,
  UserPoolClient,
} from 'aws-cdk-lib/aws-cognito';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { RestLambda } from './constructs/rest-lambda';

export interface AuthStackProps extends StackProps {
  stage: string;
}

export class AuthStack extends Stack {
  public readonly userPool: UserPool;
  public readonly userPoolClient: UserPoolClient;

  constructor(scope: Construct, id: string, props: AuthStackProps) {
    super(scope, id, props);

    const preSignUp = new RestLambda(this, 'PreSignUpAutoConfirm', {
      entry: path.join(__dirname, '../lambda/auth/pre-signup-auto-confirm.ts'),
    });

    const postConfirmation = new RestLambda(this, 'PostConfirmationSetLegacyUid', {
      entry: path.join(__dirname, '../lambda/auth/post-confirmation-set-legacy-uid.ts'),
    });

    this.userPool = new UserPool(this, 'UserPool', {
      userPoolName: `startime-users-${props.stage}`,
      selfSignUpEnabled: true,
      signInAliases: { email: true },
      standardAttributes: { email: { required: true, mutable: true } },
      // The canonical app-level user id every handler keys on -- set by
      // postConfirmation at sign-up. Deliberately not Cognito's own `sub`:
      // `sub` is regenerated per user pool, so keying data on it would have
      // made the accounts migrated from Firebase unreachable. The name is
      // historical; it applies to every account, not just migrated ones.
      customAttributes: {
        // Mutable so postConfirmation can set it after the user exists (a
        // custom attribute is otherwise only writable at sign-up time). The
        // App Client's writeAttributes below excludes it, so end users still
        // can't self-edit it through the app.
        legacy_uid: new StringAttribute({ mutable: true }),
      },
      accountRecovery: AccountRecovery.EMAIL_ONLY,
      lambdaTriggers: {
        preSignUp,
        postConfirmation,
      },
      // CDK's default for UserPool is RETAIN, which silently orphans a pool
      // on every `cdk destroy` -- exactly what with-ephemeral-stack.sh does
      // on every test run. DESTROY except for the one stage where retaining
      // real user data on stack deletion is actually the point.
      removalPolicy: props.stage === 'prod' ? RemovalPolicy.RETAIN : RemovalPolicy.DESTROY,
    });

    // Built from pseudo-parameters rather than `this.userPool.userPoolArn` --
    // referencing the pool resource directly here creates a circular
    // CloudFormation dependency, since the pool's `lambdaTriggers` wiring
    // already depends on this Lambda's invoke permission. Safe to scope to
    // "all pools in this account/region" since this is a single-purpose
    // personal AWS account.
    const anyUserPoolArn = `arn:${Aws.PARTITION}:cognito-idp:${Aws.REGION}:${Aws.ACCOUNT_ID}:userpool/*`;
    postConfirmation.addToRolePolicy(
      new PolicyStatement({
        actions: ['cognito-idp:AdminUpdateUserAttributes'],
        resources: [anyUserPoolArn],
      })
    );

    this.userPoolClient = new UserPoolClient(this, 'UserPoolClient', {
      userPool: this.userPool,
      generateSecret: false,
      // USER_PASSWORD_AUTH is load-bearing, not leftover: AuthService.signIn
      // calls InitiateAuth with .userPasswordAuth, and aws-sdk-swift ships no
      // SRP implementation (that lives in Amplify, which this app doesn't
      // use). Turning SRP on and this off would break sign-in outright.
      authFlows: { userPassword: true, userSrp: false },
      readAttributes: new ClientAttributes()
        .withStandardAttributes({ email: true })
        .withCustomAttributes('legacy_uid'),
      writeAttributes: new ClientAttributes().withStandardAttributes({ email: true }),
    });

    new CfnOutput(this, 'UserPoolId', { value: this.userPool.userPoolId });
    new CfnOutput(this, 'UserPoolClientId', { value: this.userPoolClient.userPoolClientId });
  }
}
