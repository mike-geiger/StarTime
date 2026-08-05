import type {
  APIGatewayRequestAuthorizerEvent,
  APIGatewayAuthorizerResult,
} from 'aws-lambda';
import { CognitoJwtVerifier } from 'aws-jwt-verify';

/**
 * Validates the Cognito ID token on the WebSocket handshake.
 *
 * The token arrives as a `?token=` query parameter rather than an
 * Authorization header: a native WebSocket handshake (URLSessionWebSocketTask
 * included) can't attach custom headers, so the query string is the only
 * channel available. It's TLS-encrypted in transit like any other URL, but it
 * does end up in API Gateway access logs if those are enabled -- worth knowing
 * before turning them on.
 *
 * Unlike the REST API's built-in Cognito authorizer, this verifies the
 * signature explicitly (against the pool's JWKS, cached across invocations by
 * the verifier instance).
 *
 * Must return an IAM policy document: WebSocket APIs don't support the
 * simple `{ isAuthorized }` response shape, which is HTTP-API-only.
 */
const verifier = CognitoJwtVerifier.create({
  userPoolId: process.env.USER_POOL_ID!,
  tokenUse: 'id',
  clientId: process.env.USER_POOL_CLIENT_ID!,
});

function policy(
  effect: 'Allow' | 'Deny',
  resource: string,
  uid: string
): APIGatewayAuthorizerResult {
  return {
    principalId: uid || 'anonymous',
    policyDocument: {
      Version: '2012-10-17',
      Statement: [{ Action: 'execute-api:Invoke', Effect: effect, Resource: resource }],
    },
    // Passed through to $connect so it never has to re-parse the token.
    context: { uid },
  };
}

export const handler = async (
  event: APIGatewayRequestAuthorizerEvent
): Promise<APIGatewayAuthorizerResult> => {
  const token = event.queryStringParameters?.token;
  if (!token) {
    return policy('Deny', event.methodArn, '');
  }

  try {
    const payload = await verifier.verify(token);
    const uid = payload['custom:legacy_uid'];
    if (typeof uid !== 'string' || !uid) {
      return policy('Deny', event.methodArn, '');
    }
    return policy('Allow', event.methodArn, uid);
  } catch {
    return policy('Deny', event.methodArn, '');
  }
};
