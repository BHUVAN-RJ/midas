import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasShellTypes from "../../shell/sdk/shell-types.js";

// Server-side record checks (unified data plan, section 5, "Server"). /sync/push runs the same
// validator the phone runs, against the schemas in the manifest of the Sidekick version that
// wrote the op. Versions are immutable in R2, so a copy the runner moved later never makes an
// older phone's op fail. An op from a shell that does not say its version is checked against
// the user's current version (their copy, else the base). A version whose manifest has no
// "types" block, or a Sidekick with no deployed version, is not content-checked, as before.

const VERSION_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$/;
const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

type BucketLike = {
  get(key: string): Promise<{ json(): Promise<unknown> } | null>;
};

type TypesLookup = Map<string, unknown>;

export function isValidSidekickVersion(version: unknown): version is string {
  return typeof version === "string" && VERSION_PATTERN.test(version);
}

function userPrefix(sidekickId: string, userId: string): string {
  if (!USER_ID_PATTERN.test(userId)) {
    throw new Error("bad user id");
  }
  return `sidekicks/${sidekickId}/users/${userId}`;
}

function basePrefix(sidekickId: string): string {
  return `sidekicks/${sidekickId}`;
}

async function readJson(bucket: BucketLike, key: string): Promise<unknown> {
  const object = await bucket.get(key);
  if (object === null) {
    return null;
  }
  return object.json();
}

// The version the user runs now: their own pointer, else the base pointer. Null without either.
async function currentVersion(bucket: BucketLike, sidekickId: string, userId: string): Promise<string | null> {
  const ownPointer = (await readJson(bucket, `${userPrefix(sidekickId, userId)}/current.json`)) as { version?: unknown } | null;
  if (ownPointer !== null && typeof ownPointer.version === "string") {
    return ownPointer.version;
  }
  const basePointer = (await readJson(bucket, `${basePrefix(sidekickId)}/current.json`)) as { version?: unknown } | null;
  if (basePointer !== null && typeof basePointer.version === "string") {
    return basePointer.version;
  }
  return null;
}

// The "types" block of that version's manifest: the user's copy of the version first (a repair
// may have changed the schemas), else the base version. Undefined when the version is not stored.
async function typesOfVersion(bucket: BucketLike, sidekickId: string, userId: string, version: string): Promise<unknown> {
  const prefixes = [userPrefix(sidekickId, userId), basePrefix(sidekickId)];
  for (const prefix of prefixes) {
    const manifest = (await readJson(bucket, `${prefix}/${version}/manifest.json`)) as { types?: unknown } | null;
    if (manifest !== null && typeof manifest === "object") {
      return manifest.types;
    }
  }
  return undefined;
}

// The checker for one push: manifests are read once per Sidekick version.
export function makeRecordChecker(bucket: unknown, userId: string) {
  const typesByVersion: TypesLookup = new Map();
  const bucketLike = bucket as BucketLike;
  // Tests without R2 pass a plain object; content checks need a bucket to read manifests from.
  const canReadManifests = typeof bucketLike?.get === "function";

  async function typesFor(sidekickId: string, version: string | null): Promise<unknown> {
    const resolvedVersion = version ?? (await currentVersion(bucketLike, sidekickId, userId));
    if (resolvedVersion === null) {
      return undefined;
    }
    const cacheKey = `${sidekickId}\u0000${resolvedVersion}`;
    if (typesByVersion.has(cacheKey)) {
      return typesByVersion.get(cacheKey);
    }
    const types = await typesOfVersion(bucketLike, sidekickId, userId, resolvedVersion);
    typesByVersion.set(cacheKey, types);
    return types;
  }

  // Why the value cannot be stored under the key for this Sidekick, or null.
  async function recordProblem(sidekickId: string, version: string | null, key: string, value: unknown): Promise<string | null> {
    const shellType = MidasRecordSchema.typeForKey(MidasShellTypes, key);
    if (shellType !== null) {
      return MidasRecordSchema.checkRecord(MidasShellTypes, key, value);
    }
    if (!canReadManifests) {
      return null;
    }
    const types = await typesFor(sidekickId, version);
    if (types === undefined || types === null) {
      return null;
    }
    return MidasRecordSchema.checkRecord(types, key, value);
  }

  return { recordProblem };
}

export const shellTypes = MidasShellTypes;
export const recordSchema = MidasRecordSchema;
