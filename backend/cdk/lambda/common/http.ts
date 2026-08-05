import type { APIGatewayProxyResult } from 'aws-lambda';
import { HttpError } from './auth';

export function json(statusCode: number, body: unknown): APIGatewayProxyResult {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

export function errorResponse(error: unknown): APIGatewayProxyResult {
  if (error instanceof HttpError) {
    return json(error.statusCode, { message: error.message });
  }
  console.error(error);
  return json(500, { message: 'Internal server error' });
}
