#!/usr/bin/env node
// Creates (or reuses) release v<version> on Gitea and attaches the dist assets.
// Run after build-dist.mjs. Requires GITEA_URL, GITEA_REPO, GITEA_TOKEN.

import { readFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const version = readFileSync(join(root, 'pgmorbac.control'), 'utf8').match(/default_version\s*=\s*'([^']+)'/)?.[1];
if (!version) {
    console.error('[gitea-release] could not read default_version from pgmorbac.control');
    process.exit(1);
}

const base = process.env.GITEA_URL;
const repo = process.env.GITEA_REPO;
const token = process.env.GITEA_TOKEN;
if (!base || !repo || !token) {
    console.error('[gitea-release] GITEA_URL, GITEA_REPO and GITEA_TOKEN are required');
    process.exit(1);
}

const distDir = join(root, 'dist');
const files = [
    `pgmorbac-${version}.zip`,
    `pgmorbac-${version}.zip.sha256`,
    `pgmorbac-${version}.manifest.jwt`,
    `pgmorbac-${version}.pub.pem`,
];
for (const f of files) {
    if (!existsSync(join(distDir, f))) {
        console.error(`[gitea-release] Missing artifact ${f} - run build-dist.mjs first`);
        process.exit(1);
    }
}

const api = (path) => `${base}/api/v1/repos/${repo}${path}`;
const headers = { Authorization: `token ${token}` };

async function ensureRelease() {
    const create = await fetch(api('/releases'), {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({
            tag_name: `v${version}`,
            name: `pgmorbac ${version}`,
            body: `PGXN-compatible SQL distribution. Verify with sha256sum -c and the signed manifest (public key attached; see https://pgmorbac.villains.fr/download).`,
            draft: false,
            prerelease: false,
        }),
    });
    if (create.ok) return (await create.json()).id;
    if (create.status !== 409) {
        console.error(`[gitea-release] Release creation failed: ${create.status} ${await create.text()}`);
        process.exit(1);
    }
    const existing = await fetch(api(`/releases/tags/v${version}`), { headers });
    if (!existing.ok) {
        console.error(`[gitea-release] Release exists but lookup failed: ${existing.status}`);
        process.exit(1);
    }
    return (await existing.json()).id;
}

const releaseId = await ensureRelease();
for (const f of files) {
    const form = new FormData();
    form.set('attachment', new Blob([readFileSync(join(distDir, f))]), f);
    const res = await fetch(api(`/releases/${releaseId}/assets?name=${encodeURIComponent(f)}`), {
        method: 'POST', headers, body: form,
    });
    if (!res.ok) {
        const text = await res.text();
        if (res.status === 409 || text.includes('already exist')) {
            console.log(`[gitea-release] ${f} already attached - skipping`);
            continue;
        }
        console.error(`[gitea-release] Upload of ${f} failed: ${res.status} ${text}`);
        process.exit(1);
    }
    console.log(`[gitea-release] Attached ${f}`);
}
console.log(`[gitea-release] Release v${version} ready on ${repo}`);
