import * as path from 'node:path';
import { CfnOutput, Stack, StackProps } from 'aws-cdk-lib';
import {
  AuthorizationType,
  CognitoUserPoolsAuthorizer,
  LambdaIntegration,
  RestApi,
} from 'aws-cdk-lib/aws-apigateway';
import { IUserPool } from 'aws-cdk-lib/aws-cognito';
import { ITable } from 'aws-cdk-lib/aws-dynamodb';
import { Construct } from 'constructs';
import { RestLambda } from './constructs/rest-lambda';

export interface ApiStackProps extends StackProps {
  stage: string;
  userPool: IUserPool;
  table: ITable;
}

export class ApiStack extends Stack {
  public readonly api: RestApi;

  constructor(scope: Construct, id: string, props: ApiStackProps) {
    super(scope, id, props);

    this.api = new RestApi(this, 'Api', {
      restApiName: `startime-api-${props.stage}`,
      deployOptions: { stageName: props.stage },
    });

    const authorizer = new CognitoUserPoolsAuthorizer(this, 'CognitoAuthorizer', {
      cognitoUserPools: [props.userPool],
    });

    const lambda = (id: string, entry: string) => {
      const fn = new RestLambda(this, id, {
        entry: path.join(__dirname, entry),
        environment: { TABLE_NAME: props.table.tableName },
      });
      props.table.grantReadWriteData(fn);
      return fn;
    };

    // Every route requires a valid Cognito ID token; handlers read the
    // caller's uid from the authorizer-validated claims (see common/auth.ts)
    // rather than trusting anything client-supplied.
    const authed = {
      authorizer,
      authorizationType: AuthorizationType.COGNITO,
    };

    const households = this.api.root.addResource('households');
    households.addResource('me').addMethod(
      'GET',
      new LambdaIntegration(lambda('GetHousehold', '../lambda/household/get-household.ts')),
      authed
    );
    households.addMethod(
      'POST',
      new LambdaIntegration(lambda('CreateHousehold', '../lambda/household/create-household.ts')),
      authed
    );
    households.addResource('join').addMethod(
      'POST',
      new LambdaIntegration(lambda('JoinHousehold', '../lambda/household/join-household.ts')),
      authed
    );
    households.addResource('invite-codes').addMethod(
      'POST',
      new LambdaIntegration(
        lambda('GenerateInviteCode', '../lambda/household/generate-invite-code.ts')
      ),
      authed
    );

    this.api.root.addResource('account').addMethod(
      'DELETE',
      new LambdaIntegration(lambda('DeleteAccount', '../lambda/household/delete-account.ts')),
      authed
    );

    // Chores. Create and update share one handler (both are whole-item
    // overwrites, matching the Firestore `setData(from:)` they replace).
    const saveChore = new LambdaIntegration(lambda('SaveChore', '../lambda/chores/save-chore.ts'));
    const chores = this.api.root.addResource('chores');
    chores.addMethod(
      'GET',
      new LambdaIntegration(lambda('ListChores', '../lambda/chores/list-chores.ts')),
      authed
    );
    chores.addMethod('POST', saveChore, authed);
    // A literal sibling of {choreId}; API Gateway matches the exact
    // segment before falling back to the parameterized resource.
    chores.addResource('checklist').addMethod(
      'GET',
      new LambdaIntegration(
        lambda('ListChecklistProgress', '../lambda/chores/list-checklist-progress.ts')
      ),
      authed
    );
    const chore = chores.addResource('{choreId}');
    chore.addMethod('PUT', saveChore, authed);
    chore.addMethod(
      'DELETE',
      new LambdaIntegration(lambda('DeleteChore', '../lambda/chores/delete-chore.ts')),
      authed
    );

    // Checklist chores: items are checked/unchecked individually, and the
    // day closes out (crediting points) once every item is checked. The
    // explicit complete route covers the case where editing the item list
    // already satisfies the checked set, with no new item check to trigger it.
    const choreChecklist = chore.addResource('checklist');
    const checklistItem = choreChecklist.addResource('items').addResource('{itemId}');
    checklistItem.addResource('check').addMethod(
      'POST',
      new LambdaIntegration(lambda('CheckChecklistItem', '../lambda/chores/check-checklist-item.ts')),
      authed
    );
    checklistItem.addResource('uncheck').addMethod(
      'POST',
      new LambdaIntegration(lambda('UncheckChecklistItem', '../lambda/chores/uncheck-checklist-item.ts')),
      authed
    );
    choreChecklist.addResource('complete').addMethod(
      'POST',
      new LambdaIntegration(lambda('CompleteChecklist', '../lambda/chores/complete-checklist.ts')),
      authed
    );

    const completions = this.api.root.addResource('completions');
    completions.addMethod(
      'GET',
      new LambdaIntegration(lambda('ListCompletions', '../lambda/chores/list-completions.ts')),
      authed
    );
    completions.addMethod(
      'POST',
      new LambdaIntegration(lambda('RecordCompletion', '../lambda/chores/record-completion.ts')),
      authed
    );

    // Rewards.
    const saveReward = new LambdaIntegration(lambda('SaveReward', '../lambda/rewards/save-reward.ts'));
    const rewards = this.api.root.addResource('rewards');
    rewards.addMethod(
      'GET',
      new LambdaIntegration(lambda('ListRewards', '../lambda/rewards/list-rewards.ts')),
      authed
    );
    rewards.addMethod('POST', saveReward, authed);
    const reward = rewards.addResource('{rewardId}');
    reward.addMethod('PUT', saveReward, authed);
    reward.addMethod(
      'DELETE',
      new LambdaIntegration(lambda('DeleteReward', '../lambda/rewards/delete-reward.ts')),
      authed
    );

    const redemptions = this.api.root.addResource('redemptions');
    redemptions.addMethod(
      'GET',
      new LambdaIntegration(lambda('ListRedemptions', '../lambda/rewards/list-redemptions.ts')),
      authed
    );
    redemptions.addMethod(
      'POST',
      new LambdaIntegration(lambda('RedeemReward', '../lambda/rewards/redeem-reward.ts')),
      authed
    );
    // Fulfillment lifecycle. Parent-only, enforced inside the handler.
    redemptions.addResource('{redemptionId}').addMethod(
      'PATCH',
      new LambdaIntegration(
        lambda('UpdateRedemptionStatus', '../lambda/rewards/update-redemption-status.ts')
      ),
      authed
    );

    this.api.root.addResource('balances').addMethod(
      'GET',
      new LambdaIntegration(lambda('GetBalances', '../lambda/rewards/get-balances.ts')),
      authed
    );

    new CfnOutput(this, 'ApiBaseUrl', { value: this.api.url });
  }
}
