import { CfnOutput, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import { AttributeType, BillingMode, StreamViewType, Table } from 'aws-cdk-lib/aws-dynamodb';
import { Construct } from 'constructs';

export interface DataStackProps extends StackProps {
  stage: string;
}

/**
 * Single-table design -- see the "Target architecture" section of the
 * migration plan for the full key schema:
 *
 *   Household metadata   PK=HOUSEHOLD#{id}      SK=METADATA
 *   User profile          PK=USER#{uid}          SK=PROFILE
 *   Chore                  PK=HOUSEHOLD#{id}      SK=CHORE#{choreId}
 *   Reward                 PK=HOUSEHOLD#{id}      SK=REWARD#{rewardId}
 *   Completion              PK=HOUSEHOLD#{id}      SK=COMPLETION#{completedAtISO}#{id}
 *   Redemption              PK=HOUSEHOLD#{id}      SK=REDEMPTION#{redeemedAtISO}#{id}
 *   Balance                PK=HOUSEHOLD#{id}      SK=BALANCE#{uid}
 *   Invite code             PK=INVITECODE#{code}   SK=METADATA   GSI1PK=HOUSEHOLD#{id}  GSI1SK=INVITECODE#{code}
 *
 * GSI1 exists specifically for the cascade-delete Lambda's "all invite codes
 * for this household" lookup (Firestore's `whereField("householdId", ...)`
 * equivalent).
 */
export class DataStack extends Stack {
  public readonly table: Table;

  constructor(scope: Construct, id: string, props: DataStackProps) {
    super(scope, id, props);

    this.table = new Table(this, 'Table', {
      tableName: `startime-${props.stage}`,
      partitionKey: { name: 'PK', type: AttributeType.STRING },
      sortKey: { name: 'SK', type: AttributeType.STRING },
      billingMode: BillingMode.PAY_PER_REQUEST,
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      stream: StreamViewType.NEW_IMAGE,
      // CDK's default for Table is RETAIN, which would silently orphan a
      // table on every `cdk destroy` -- exactly what with-ephemeral-stack.sh
      // does on every test run (see the identical Cognito UserPool gotcha
      // in auth-stack.ts). DESTROY except for the one stage where retaining
      // real data on stack deletion is actually the point.
      removalPolicy: props.stage === 'prod' ? RemovalPolicy.RETAIN : RemovalPolicy.DESTROY,
    });

    this.table.addGlobalSecondaryIndex({
      indexName: 'GSI1',
      partitionKey: { name: 'GSI1PK', type: AttributeType.STRING },
      sortKey: { name: 'GSI1SK', type: AttributeType.STRING },
    });

    new CfnOutput(this, 'TableName', { value: this.table.tableName });
  }
}
