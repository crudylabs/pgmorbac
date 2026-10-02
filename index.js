import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = dirname(fileURLToPath(import.meta.url));

export const controlFile = join(root, 'pgmorbac.control');
export const sqlDir = join(root, 'sql');

const control = readFileSync(controlFile, 'utf8').match(/default_version\s*=\s*'([^']+)'/);
if (!control) throw new Error('[pgmorbac] pgmorbac.control has no default_version');
export const version = control[1];

/** The install script pgmorbac--<version>.sql, as CREATE EXTENSION would run it. */
export function extensionSql() {
    return readFileSync(join(sqlDir, `pgmorbac--${version}.sql`), 'utf8');
}

const semver = (v) => v.split('.').map(Number);
const byFrom = (a, b) => {
    const [x, y] = [semver(a.from), semver(b.from)];
    return x[0] - y[0] || x[1] - y[1] || x[2] - y[2];
};

/** Upgrade scripts pgmorbac--<from>--<to>.sql, in version order. */
export function upgradeScripts() {
    return readdirSync(sqlDir)
        .map((filename) => ({ filename, m: /^pgmorbac--(\d+\.\d+\.\d+)--(\d+\.\d+\.\d+)\.sql$/.exec(filename) }))
        .filter(({ m }) => m)
        .map(({ filename, m }) => ({ from: m[1], to: m[2], filename, sql: readFileSync(join(sqlDir, filename), 'utf8') }))
        .sort(byFrom);
}
