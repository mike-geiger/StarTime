import * as path from 'node:path';
import { Aws, CfnOutput, Duration, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
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
  /** Only needed for the `prod` stage -- see backend/cdk/lambda/auth/migrate-user.ts. */
  firebaseWebApiKey?: string;
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

    const migrateUser = new RestLambda(this, 'MigrateUser', {
      entry: path.join(__dirname, '../lambda/auth/migrate-user.ts'),
      timeout: Duration.seconds(10),
      environment: props.firebaseWebApiKey
        ? { FIREBASE_WEB_API_KEY: props.firebaseWebApiKey }
        : {},
    });

    this.userPool = new UserPool(this, 'UserPool', {
      userPoolName: `startime-users-${props.stage}`,
      selfSignUpEnabled: true,
      signInAliases: { email: true },
      standardAttributes: { email: { required: true, mutable: true } },
      // Canonical app-level user id -- set by postConfirmation for fresh
      // sign-ups and by migrateUser for accounts carried over from Firebase.
      // Deliberately not Cognito's own `sub`, which is always a fresh UUID
      // and can never equal a migrated user's existing Firebase UID.
      customAttributes: {
        // Mutable so postConfirmation/migrateUser can set it after the user
        // is created (a custom attribute can only be written at sign-up time
        // otherwise). The App Client's writeAttributes below deliberately
        // excludes it, so end users still can't self-edit it through the app.
        legacy_uid: new StringAttribute({ mutable: true }),
      },
      accountRecovery: AccountRecovery.EMAIL_ONLY,
      lambdaTriggers: {
        preSignUp,
        postConfirmation,
        userMigration: migrateUser,
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
      // SRP (Cognito's default) never sends the plaintext password to the
      // server, so it can't support migrate-user.ts verifying it against
      // Firebase. USER_PASSWORD_AUTH also avoids hand-implementing SRP's
      // client-side crypto in Swift without Amplify.
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
