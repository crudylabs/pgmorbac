#!/usr/bin/env node
// Builds sql/ for the npm package: the install script from src/ (tools/build.sh)
// plus any upgrade scripts. Runs on prepack; sql/ is never committed.
import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const control = readFileSync(join(root, 'pgmorbac.control'), 'utf8').match(/default_version\s*=\s*'([^']+)'/);
if (!control) throw new Error('pgmorbac.control has no default_version');
const version = control[1];
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
if (pkg.version !== version) throw new Error(`package.json ${pkg.version} != pgmorbac.control ${version}`);

const sqlDir = join(root, 'sql');
rmSync(sqlDir, { recursive: true, force: true });
mkdirSync(sqlDir);
execFileSync(join(root, 'tools', 'build.sh'), ['src', join(sqlDir, `pgmorbac--${version}.sql`)], { cwd: root, stdio: 'inherit' });
const upgrades = join(root, 'src', 'upgrades');
if (existsSync(upgrades)) {
    for (const f of readdirSync(upgrades).filter((n) => n.endsWith('.sql'))) copyFileSync(join(upgrades, f), join(sqlDir, f));
}
