#!/usr/bin/env node
// Builds the PGXN-compatible pgmorbac source distribution from src/:
//   dist/pgmorbac-<version>.zip            extension files + META.json
//   dist/pgmorbac-<version>.zip.sha256     checksum (sha256sum -c format)
//   dist/pgmorbac-<version>.manifest.jwt   Ed25519-signed release manifest
//   dist/pgmorbac-<version>.pub.pem        the verification public key
// PGMORBAC_RELEASE_KEY must point to the Ed25519 private key (PKCS8 PEM).
// The build self-verifies before exiting.

import { createHash, createPublicKey } from 'crypto';
import { execFileSync } from 'child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { SignJWT, jwtVerify, importPKCS8, importSPKI } from 'jose';

const AUDIENCE = 'pgmorbac-release';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');

function fail(msg) {
    console.error(`[pgmorbac-dist] ${msg}`);
    process.exit(1);
}

function controlVersion() {
    const m = readFileSync(join(root, 'pgmorbac.control'), 'utf8').match(/default_version\s*=\s*'([^']+)'/);
    if (!m) fail('pgmorbac.control has no default_version');
    return m[1];
}

const version = controlVersion();
const meta = JSON.parse(readFileSync(join(root, 'META.json'), 'utf8'));
const baseScript = `pgmorbac--${version}.sql`;
if (meta.version !== version || meta.provides?.pgmorbac?.file !== baseScript) {
    fail(`META.json version/provides out of sync with control ${version}`);
}

const keyPath = process.env.PGMORBAC_RELEASE_KEY;
if (!keyPath) fail('PGMORBAC_RELEASE_KEY is not set (path to the Ed25519 private key PEM)');
if (!existsSync(keyPath)) fail(`PGMORBAC_RELEASE_KEY points to a missing file: ${keyPath}`);
const privatePem = readFileSync(keyPath, 'utf8');

const distDir = join(root, 'dist');
const stageName = `pgmorbac-${version}`;
const stageDir = join(distDir, stageName);
rmSync(distDir, { recursive: true, force: true });
mkdirSync(stageDir, { recursive: true });

execFileSync(join(root, 'tools', 'build.sh'), ['src', join(stageDir, baseScript)], { cwd: root, stdio: 'inherit' });
copyFileSync(join(root, 'pgmorbac.control'), join(stageDir, 'pgmorbac.control'));
copyFileSync(join(root, 'META.json'), join(stageDir, 'META.json'));
copyFileSync(join(root, 'LICENSE'), join(stageDir, 'LICENSE'));
const upgradesDir = join(root, 'src', 'upgrades');
if (existsSync(upgradesDir)) {
    for (const f of readdirSync(upgradesDir).filter(n => n.endsWith('.sql'))) {
        copyFileSync(join(upgradesDir, f), join(stageDir, f));
    }
}

writeFileSync(join(stageDir, 'Makefile'), `EXTENSION = pgmorbac
DATA = $(wildcard pgmorbac--*.sql)
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
`);

writeFileSync(join(stageDir, 'README-INSTALL.md'), `# Installing pgmorbac ${version}

Full documentation: ${meta.resources.homepage}

## As a PostgreSQL extension (recommended)

    make install                      # uses pg_config / PGXS
    psql -d mydb -c 'CREATE EXTENSION pgmorbac'

## Plain SQL (no filesystem access to the server)

    psql -v ON_ERROR_STOP=1 -d mydb -f ${baseScript}

## Verifying this distribution

    sha256sum -c pgmorbac-${version}.zip.sha256

The signed manifest (pgmorbac-${version}.manifest.jwt) is an Ed25519 JWT
(audience \`${AUDIENCE}\`) carrying the artifact sha256, verifiable against
pgmorbac-${version}.pub.pem published on the same release.
`);

const zipName = `${stageName}.zip`;
try {
    execFileSync('zip', ['-r', '-X', '-q', zipName, stageName], { cwd: distDir });
} catch (err) {
    fail(`zip failed (is the zip CLI installed?): ${err instanceof Error ? err.message : err}`);
}

const zipBytes = readFileSync(join(distDir, zipName));
const sha256 = createHash('sha256').update(zipBytes).digest('hex');
writeFileSync(join(distDir, `${zipName}.sha256`), `${sha256}  ${zipName}\n`);

const manifest = { name: 'pgmorbac', version, artifacts: [{ name: zipName, sha256 }] };
const signingKey = await importPKCS8(privatePem.trim(), 'EdDSA');
const token = await new SignJWT({ manifest })
    .setProtectedHeader({ alg: 'EdDSA', typ: 'JWT' })
    .setIssuedAt()
    .setAudience(AUDIENCE)
    .sign(signingKey);
writeFileSync(join(distDir, `${stageName}.manifest.jwt`), `${token}\n`);

const publicPem = createPublicKey(privatePem).export({ type: 'spki', format: 'pem' }).toString();
writeFileSync(join(distDir, `${stageName}.pub.pem`), publicPem);

const verifyKey = await importSPKI(publicPem, 'EdDSA');
const { payload } = await jwtVerify(token, verifyKey, { algorithms: ['EdDSA'], audience: AUDIENCE });
const rehash = createHash('sha256').update(readFileSync(join(distDir, zipName))).digest('hex');
if (payload.manifest.artifacts[0].sha256 !== rehash || payload.manifest.version !== version) {
    fail('self-verification failed: manifest does not match the built artifact');
}

console.log(`[pgmorbac-dist] Built ${zipName}`);
console.log(`[pgmorbac-dist] sha256 ${sha256}`);
console.log('[pgmorbac-dist] Manifest signed and self-verified');
