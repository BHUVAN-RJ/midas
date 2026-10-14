// An in-memory stand-in for an R2 bucket: put, get, head, list and delete, enough for routes
// that store and serve objects. Bytes and content type are kept per key.

type StoredObject = { bytes: Uint8Array; contentType: string | null };

async function toBytes(value: unknown): Promise<Uint8Array> {
  if (typeof value === "string") {
    return new TextEncoder().encode(value);
  }
  if (value instanceof ArrayBuffer) {
    return new Uint8Array(value);
  }
  if (value instanceof Uint8Array) {
    return value;
  }
  if (typeof value === "object" && value !== null && typeof (value as Blob).arrayBuffer === "function") {
    return new Uint8Array(await (value as Blob).arrayBuffer());
  }
  throw new Error("fake R2 cannot store this value");
}

export function makeFakeR2(seed: Record<string, string> = {}) {
  const objectsByKey = new Map<string, StoredObject>();
  for (const [key, text] of Object.entries(seed)) {
    objectsByKey.set(key, { bytes: new TextEncoder().encode(text), contentType: "application/json" });
  }

  async function putObject(key: string, value: unknown, options?: { httpMetadata?: { contentType?: string } }) {
    const bytes = await toBytes(value);
    objectsByKey.set(key, { bytes, contentType: options?.httpMetadata?.contentType ?? null });
    return { key, size: bytes.length };
  }

  async function getObject(key: string) {
    const stored = objectsByKey.get(key);
    if (stored === undefined) {
      return null;
    }
    const text = new TextDecoder().decode(stored.bytes);
    return {
      key,
      size: stored.bytes.length,
      body: new Response(stored.bytes).body,
      httpMetadata: { contentType: stored.contentType ?? undefined },
      text: async () => text,
      json: async () => JSON.parse(text),
      arrayBuffer: async () => stored.bytes.buffer.slice(stored.bytes.byteOffset, stored.bytes.byteOffset + stored.bytes.byteLength),
    };
  }

  async function headObject(key: string) {
    const stored = objectsByKey.get(key);
    if (stored === undefined) {
      return null;
    }
    return { key, size: stored.bytes.length };
  }

  async function listObjects(options?: { prefix?: string; limit?: number }) {
    const prefix = options?.prefix ?? "";
    const objects = [];
    for (const [key, stored] of objectsByKey) {
      if (key.startsWith(prefix)) {
        objects.push({ key, size: stored.bytes.length });
      }
    }
    objects.sort(compareByKey);
    return { objects, truncated: false };
  }

  async function deleteObject(key: string) {
    objectsByKey.delete(key);
  }

  // Direct access for tests that inspect what was stored.
  function keys(): string[] {
    const allKeys = Array.from(objectsByKey.keys());
    allKeys.sort();
    return allKeys;
  }

  return { put: putObject, get: getObject, head: headObject, list: listObjects, delete: deleteObject, keys };
}

function compareByKey(left: { key: string }, right: { key: string }): number {
  return left.key < right.key ? -1 : left.key > right.key ? 1 : 0;
}
