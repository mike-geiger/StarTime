import * as path from 'node:path';
import { CfnOutput, Duration, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import { WebSocketApi, WebSocketStage } from 'aws-cdk-lib/aws-apigatewayv2';
import { WebSocketLambdaAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import { WebSocketLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import { IUserPool, IUserPoolClient } from 'aws-cdk-lib/aws-cognito';
import { AttributeType, BillingMode, ITable, Table } from 'aws-cdk-lib/aws-dynamodb';
import { StartingPosition } from 'aws-cdk-lib/aws-lambda';
import { DynamoEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';
import { Construct } from 'constructs';
import { RestLambda } from './constructs/rest-lambda';

export interface RealtimeStackProps extends StackProps {
  stage: string;
  userPool: IUserPool;
  userPoolClient: IUserPoolClient;
  table: Table;
}

export class RealtimeStack extends Stack {
  constructor(scope: Construct, id: string, props: RealtimeStackProps) {
    super(scope, id, props);

    // Deliberately separate from the main table: connection rows are
    // ephemeral and high-churn, and mixing them in would mean every domain
    // stream consumer had to filter them back out.
    const connections = new Table(this, 'ConnectionsTable', {
      tableName: `startime-connections-${props.stage}`,
      partitionKey: { name: 'connectionId', type: AttributeType.STRING },
      billingMode: BillingMode.PAY_PER_REQUEST,
      timeToLiveAttribute: 'expiresAt',
      // Ephemeral by nature -- nothing here is worth retaining even in prod.
      removalPolicy: RemovalPolicy.DESTROY,
    });
    connections.addGlobalSecondaryIndex({
      indexName: 'GSI1',
      partitionKey: { name: 'GSI1PK', type: AttributeType.STRING },
    });

    const authorizerFn = new RestLambda(this, 'WsAuthorizer', {
      entry: path.join(__dirname, '../lambda/realtime/ws-authorizer.ts'),
      environment: {
        USER_POOL_ID: props.userPool.userPoolId,
        USER_POOL_CLIENT_ID: props.userPoolClient.userPoolClientId,
      },
    });

    const connectFn = new RestLambda(this, 'WsConnect', {
      entry: path.join(__dirname, '../lambda/realtime/connect.ts'),
      environment: {
        TABLE_NAME: props.table.tableName,
        CONNECTIONS_TABLE: connections.tableName,
      },
    });
    props.table.grantReadData(connectFn);
    connections.grantWriteData(connectFn);

    const disconnectFn = new RestLambda(this, 'WsDisconnect', {
      entry: path.join(__dirname, '../lambda/realtime/disconnect.ts'),
      environment: { CONNECTIONS_TABLE: connections.tableName },
    });
    connections.grantWriteData(disconnectFn);

    const api = new WebSocketApi(this, 'WebSocketApi', {
      apiName: `startime-ws-${props.stage}`,
      connectRouteOptions: {
        integration: new WebSocketLambdaIntegration('ConnectIntegration', connectFn),
        authorizer: new WebSocketLambdaAuthorizer('WsAuth', authorizerFn, {
          // Native WebSocket handshakes can't send custom headers, so the
          // ID token rides in the query string (see ws-authorizer.ts).
          identitySource: ['route.request.querystring.token'],
        }),
      },
      disconnectRouteOptions: {
        integration: new WebSocketLambdaIntegration('DisconnectIntegration', disconnectFn),
      },
    });

    const wsStage = new WebSocketStage(this, 'Stage', {
      webSocketApi: api,
      stageName: props.stage,
      autoDeploy: true,
    });

    const fanoutFn = new RestLambda(this, 'StreamFanout', {
      entry: path.join(__dirname, '../lambda/realtime/stream-fanout.ts'),
      timeout: Duration.seconds(30),
      environment: {
        CONNECTIONS_TABLE: connections.tableName,
        // The management API endpoint is the stage's callback URL, which is
        // the wss:// URL over https.
        WEBSOCKET_ENDPOINT: wsStage.callbackUrl,
      },
    });
    connections.grantReadWriteData(fanoutFn);
    api.grantManageConnections(fanoutFn);

    fanoutFn.addEventSource(
      new DynamoEventSource(props.table, {
        startingPosition: StartingPosition.LATEST,
        batchSize: 25,
        // A few hundred ms of batching collapses bursts (a transaction writes
        // a completion *and* a balance) into one push per household.
        maxBatchingWindow: Duration.seconds(1),
        // A poison record shouldn't stall the whole shard -- realtime
        // invalidations are disposable, and the next write re-triggers one.
        retryAttempts: 2,
        bisectBatchOnError: true,
        // Not using reportBatchItemFailures: the handler already absorbs
        // per-connection failures itself, so there's nothing partial to
        // report back.
      })
    );

    new CfnOutput(this, 'WebSocketUrl', { value: wsStage.url });
  }
}
