#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const { resolve } = require('node:path');

// pnpm preserves the separator in `pnpm test -- --coverage`; Jest treats the
// second `--coverage` as a test-name pattern. Remove only that leading
// separator so focused paths and every subsequent Jest option stay unchanged.
const forwardedArguments = process.argv.slice(2);
if (forwardedArguments[0] === '--') {
  forwardedArguments.shift();
}

const result = spawnSync(
  resolve('node_modules', '.bin', process.platform === 'win32' ? 'jest.cmd' : 'jest'),
  ['--runInBand', ...forwardedArguments],
  { stdio: 'inherit' },
);

if (result.error !== undefined) {
  throw result.error;
}
if (result.signal !== null) {
  process.kill(process.pid, result.signal);
} else {
  process.exitCode = result.status ?? 1;
}
