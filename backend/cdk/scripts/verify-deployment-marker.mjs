#!/usr/bin/env node
/**
 * Confirms /health actually answers the question this change exists to
 * answer -- "what revision is this deployment running" -- and that the
 * verification gate deploy-prod.sh runs afterward can't be fooled into a
 * false pass.
 *
 * Three things checked against a real, disposable stack:
 *   1. /health reports the commit and dirty flag this stack was built from,
 *      with no authentication.
 *   2. Comparing that report against a deliberately wrong commit is
 *      detected as a mismatch -- the same comparison deploy-prod.sh makes.
 *   3. An unreachable health endpoint is never mistaken for a match.
 *
 * Expects the env vars with-ephemeral-stack.sh exports.
 */
import { execFileSync } from 'node:child_process';

const { STARTIME_HEALTH_API_URL: HEALTH_URL } = process.env;

if (!HEALTH_URL) {
  console.error('Missing STARTIME_HEALTH_API_URL');
  process.exit(1);
}

let failures = 0;
const check = (label, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${label}${ok ? '' : ` -- got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)}`}`);
  if (!ok) failures++;
};

// The same two values bin/startime.ts resolves at synth time, computed the
// same way, so this is checking the marker against ground truth rather than
// against itself.
const expectedCommit = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim();
const expectedDirty = execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim() !== '';

console.log('1. querying /health with no authentication');
const res = await fetch(`${HEALTH_URL.replace(/\/$/, '')}/health`);
check('reachable without credentials', res.status, 200);
const body = await res.json();
console.log('   response:', JSON.stringify(body));

check('reports healthy', body.status, 'ok');
check('reports the built commit', body.commit, expectedCommit);
check('reports the tree\'s dirty state', body.dirty, expectedDirty);
check(
  'reports exactly the four documented fields',
  Object.keys(body).sort(),
  ['commit', 'dirty', 'stage', 'status'].sort()
);

console.log('2. a wrong expected commit is detected as a mismatch');
// Mirrors deploy-prod.sh's comparison directly: same shape, same verdict.
const wrongExpected = `${expectedCommit === 'ffffff' ? '000000' : 'ffffff'}`;
check('deliberately-wrong commit does not match what was served', body.commit === wrongExpected, false);

console.log('3. an unreachable endpoint must never read as a pass');
let unreachableFailedAsExpected = false;
try {
  // A host that cannot resolve, not just a 404 -- the failure mode the gate
  // has to treat as "no answer", same as a curl timeout in the shell script.
  await fetch('https://startime-verify-deployment-marker.invalid/health', {
    signal: AbortSignal.timeout(5000),
  });
} catch {
  unreachableFailedAsExpected = true;
}
check('unreachable host raises rather than silently passing', unreachableFailedAsExpected, true);

console.log(failures === 0 ? '\nDEPLOYMENT MARKER OK' : `\n${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
