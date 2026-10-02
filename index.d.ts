/** Absolute path to pgmorbac.control. */
export declare const controlFile: string;
/** Absolute path to the directory holding the install and upgrade scripts. */
export declare const sqlDir: string;
/** The extension version (default_version in pgmorbac.control). */
export declare const version: string;
/** The install script pgmorbac--<version>.sql, as CREATE EXTENSION would run it. */
export declare function extensionSql(): string;
export interface UpgradeScript {
    from: string;
    to: string;
    filename: string;
    sql: string;
}
/** Upgrade scripts pgmorbac--<from>--<to>.sql, in version order. */
export declare function upgradeScripts(): UpgradeScript[];
