import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasShellTypes from "../../shell/sdk/shell-types.js";

// Server-side record checks (unified data plan, section 5, "Server"). /sync/push runs the same
// validator the phone runs, against the schemas in the manifest of the Sidekick version that
// wrote the op. Versions are immutable in R2, so a copy the runner moved later never makes an
// older phone's op fail. An op from a shell that does not say its version is checked against
// the user's current version (their copy, else the base). Founder, 2026-10-20 (docs/PRODUCT.md,
// "Old formats retired"): a save from a version whose manifest has no
// "types" block (the bundles from before the unified data rework, build 2 and older) is refused
// with its reason; the phone keeps the op queued. A version that is not stored, or a Sidekick with
// no deployed version, has no manifest to check against and is not content-checked.

const VERSION_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$/;
const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

type BucketLike = {
  get(key: string): Promise<{ json(): Promise<unknown> } | null>;
};

type TypesLookup = Map<string, VersionTypes>;

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

// What a version's manifest says about its records: the user's copy of the version first (a
// repair may have changed the schemas), else the base version.
type VersionTypes = { types: Record<string, unknown> } | { refusal: string } | { unchecked: true };

function isTypesBlock(types: unknown): types is Record<string, unknown> {
  return typeof types === "object" && types !== null && !Array.isArray(types);
}

async function typesOfVersion(bucket: BucketLike, sidekickId: string, userId: string, version: string): Promise<VersionTypes> {
  const prefixes = [userPrefix(sidekickId, userId), basePrefix(sidekickId)];
  for (const prefix of prefixes) {
    const manifest = (await readJson(bucket, `${prefix}/${version}/manifest.json`)) as { types?: unknown } | null;
    if (manifest !== null && typeof manifest === "object") {
      if (!isTypesBlock(manifest.types)) {
        return { refusal: `${sidekickId} version ${version} has no record schema types` };
      }
      return { types: manifest.types };
    }
  }
  return { unchecked: true };
}

// The checker for one push: manifests are read once per Sidekick version.
export function makeRecordChecker(bucket: unknown, userId: string) {
  const typesByVersion: TypesLookup = new Map();
  const bucketLike = bucket as BucketLike;
  // Tests without R2 pass a plain object; content checks need a bucket to read manifests from.
  const canReadManifests = typeof bucketLike?.get === "function";

  async function typesFor(sidekickId: string, version: string | null): Promise<VersionTypes> {
    const resolvedVersion = version ?? (await currentVersion(bucketLike, sidekickId, userId));
    if (resolvedVersion === null) {
      return { unchecked: true };
    }
    const cacheKey = `${sidekickId}\u0000${resolvedVersion}`;
    const cached = typesByVersion.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    const versionTypes = await typesOfVersion(bucketLike, sidekickId, userId, resolvedVersion);
    typesByVersion.set(cacheKey, versionTypes);
    return versionTypes;
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
    const versionTypes = await typesFor(sidekickId, version);
    if ("refusal" in versionTypes) {
      return versionTypes.refusal;
    }
    if ("unchecked" in versionTypes) {
      return null;
    }
    return MidasRecordSchema.checkRecord(versionTypes.types, key, value);
  }

  return { recordProblem };
}

export const shellTypes = MidasShellTypes;
export const recordSchema = MidasRecordSchema;
