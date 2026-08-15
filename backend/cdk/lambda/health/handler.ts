import type { APIGatewayProxyHandler } from 'aws-lambda';

/**
 * Liveness plus provenance: what is running, and what it was built from.
 *
 * The values come from the environment because they were resolved at synth
 * time (bin/startime.ts) -- a bundled, minified Lambda carries no git
 * metadata, so there is nothing here to discover at request time.
 *
 * This endpoint is unauthenticated, which is the point: it can be checked
 * from anywhere by anything that can make an HTTP request. That is also why
 * the body is exactly these four fields and must stay that way -- no paths,
 * no environment dumps, no account or resource identifiers.
 */
export const handler: APIGatewayProxyHandler = async () => {
  return {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      status: 'ok',
      stage: process.env.STAGE ?? 'unknown',
      commit: process.env.BUILD_COMMIT ?? 'unknown',
      dirty: process.env.BUILD_DIRTY === 'true',
    }),
  };
};
