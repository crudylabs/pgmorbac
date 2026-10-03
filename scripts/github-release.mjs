#!/usr/bin/env node
// Creates (or reuses) release v<version> on GitHub and attaches the dist assets.
// Run after build-dist.mjs. Requires GITHUB_REPOSITORY (owner/name) and GITHUB_TOKEN.

import { readFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const version = readFileSync(join(root, 'pgmorbac.control'), 'utf8').match(/default_version\s*=\s*'([^']+)'/)?.[1];
if (!version) {
    console.error('[github-release] could not read default_version from pgmorbac.control');
    process.exit(1);
}
const homepage = JSON.parse(readFileSync(join(root, 'META.json'), 'utf8')).resources.homepage;

const repo = process.env.GITHUB_REPOSITORY;
const token = process.env.GITHUB_TOKEN;
if (!repo || !token) {
    console.error('[github-release] GITHUB_REPOSITORY and GITHUB_TOKEN are required');
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
        console.error(`[github-release] Missing artifact ${f} - run build-dist.mjs first`);
        process.exit(1);
    }
}

const headers = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' };
const api = (path) => `https://api.github.com/repos/${repo}${path}`;

async function ensureRelease() {
    const existing = await fetch(api(`/releases/tags/v${version}`), { headers });
    if (existing.ok) return existing.json();
    if (existing.status !== 404) {
        console.error(`[github-release] Release lookup failed: ${existing.status}`);
        process.exit(1);
    }
    const create = await fetch(api('/releases'), {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({
            tag_name: `v${version}`,
            name: `pgmorbac ${version}`,
            body: `PGXN-compatible SQL distribution. Verify with sha256sum -c and the signed manifest (public key attached; see ${homepage}/download).`,
            draft: false,
            prerelease: false,
        }),
    });
    if (!create.ok) {
        console.error(`[github-release] Release creation failed: ${create.status} ${await create.text()}`);
        process.exit(1);
    }
    return create.json();
}

const release = await ensureRelease();
const attached = new Set((release.assets ?? []).map((a) => a.name));
for (const f of files) {
    if (attached.has(f)) {
        console.log(`[github-release] ${f} already attached - skipping`);
        continue;
    }
    const res = await fetch(`https://uploads.github.com/repos/${repo}/releases/${release.id}/assets?name=${encodeURIComponent(f)}`, {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/octet-stream' },
        body: readFileSync(join(distDir, f)),
    });
    if (!res.ok) {
        console.error(`[github-release] Upload of ${f} failed: ${res.status} ${await res.text()}`);
        process.exit(1);
    }
    console.log(`[github-release] Attached ${f}`);
}
console.log(`[github-release] Release v${version} ready on ${repo}`);
