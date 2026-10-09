import { webcrypto } from "node:crypto";

// A software passkey: a P-256 key pair that produces the same registration and assertion JSON
// an iPhone sends, so the server's real WebAuthn verification runs in tests.

const subtle = webcrypto.subtle;

function base64url(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("base64url");
}

function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const totalLength = parts.reduce(addLength, 0);
  const joined = new Uint8Array(totalLength);
  let offset = 0;
  for (const part of parts) {
    joined.set(part, offset);
    offset += part.length;
  }
  return joined;
}

function addLength(sum: number, part: Uint8Array): number {
  return sum + part.length;
}

async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  const digest = await subtle.digest("SHA-256", bytes);
  return new Uint8Array(digest);
}

// Minimal CBOR encoder: integers, byte strings, text strings and maps, which is all that
// attestation objects and COSE keys use.
type CborValue = number | string | Uint8Array | Map<CborValue, CborValue>;

function cborHead(majorType: number, length: number): Uint8Array {
  if (length < 24) {
    return Uint8Array.of((majorType << 5) | length);
  }
  if (length < 256) {
    return Uint8Array.of((majorType << 5) | 24, length);
  }
  return Uint8Array.of((majorType << 5) | 25, length >> 8, length & 0xff);
}

function cborEncode(value: CborValue): Uint8Array {
  if (typeof value === "number") {
    return value >= 0 ? cborHead(0, value) : cborHead(1, -1 - value);
  }
  if (typeof value === "string") {
    const textBytes = new TextEncoder().encode(value);
    return concatBytes(cborHead(3, textBytes.length), textBytes);
  }
  if (value instanceof Uint8Array) {
    return concatBytes(cborHead(2, value.length), value);
  }
  const encodedEntries: Uint8Array[] = [cborHead(5, value.size)];
  for (const [entryKey, entryValue] of value) {
    encodedEntries.push(cborEncode(entryKey), cborEncode(entryValue));
  }
  return concatBytes(...encodedEntries);
}

// WebCrypto signs as raw r||s; WebAuthn carries an ASN.1 DER signature.
function rawSignatureToDer(rawSignature: Uint8Array): Uint8Array {
  const r = derInteger(rawSignature.slice(0, 32));
  const s = derInteger(rawSignature.slice(32, 64));
  return concatBytes(Uint8Array.of(0x30, r.length + s.length), r, s);
}

function derInteger(unsignedBytes: Uint8Array): Uint8Array {
  let start = 0;
  while (start < unsignedBytes.length - 1 && unsignedBytes[start] === 0) {
    start += 1;
  }
  let body = unsignedBytes.slice(start);
  if (body[0] & 0x80) {
    body = concatBytes(Uint8Array.of(0), body);
  }
  return concatBytes(Uint8Array.of(0x02, body.length), body);
}

const FLAG_USER_PRESENT = 0x01;
const FLAG_USER_VERIFIED = 0x04;
const FLAG_ATTESTED_DATA = 0x40;

export type SoftAuthenticatorOptions = {
  rpId: string;
  origin: string;
};

export async function makeSoftAuthenticator(options: SoftAuthenticatorOptions) {
  const keyPair = await subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const rawPublicKey = new Uint8Array(await subtle.exportKey("raw", keyPair.publicKey));
  const credentialId = webcrypto.getRandomValues(new Uint8Array(16));
  const credentialIdText = base64url(credentialId);
  let userHandle: Uint8Array = new Uint8Array();
  let signCount = 0;

  const coseKey = new Map<CborValue, CborValue>([
    [1, 2], // kty: EC2
    [3, -7], // alg: ES256
    [-1, 1], // crv: P-256
    [-2, rawPublicKey.slice(1, 33)],
    [-3, rawPublicKey.slice(33, 65)],
  ]);

  async function authenticatorData(flags: number, attestedData: Uint8Array): Promise<Uint8Array> {
    const rpIdHash = await sha256(new TextEncoder().encode(options.rpId));
    const counterBytes = new Uint8Array(4);
    new DataView(counterBytes.buffer).setUint32(0, signCount);
    return concatBytes(rpIdHash, Uint8Array.of(flags), counterBytes, attestedData);
  }

  function clientData(type: string, challenge: string, origin: string): Uint8Array {
    const clientDataJson = JSON.stringify({ type, challenge, origin, crossOrigin: false });
    return new TextEncoder().encode(clientDataJson);
  }

  // registrationOptions is the `options` object the server returned.
  async function register(
    registrationOptions: { challenge: string; user: { id: string } },
    overrides: { origin?: string; flags?: number } = {},
  ) {
    userHandle = Buffer.from(registrationOptions.user.id, "base64url");
    const credentialIdLength = Uint8Array.of(credentialId.length >> 8, credentialId.length & 0xff);
    const attestedData = concatBytes(new Uint8Array(16), credentialIdLength, credentialId, cborEncode(coseKey));
    const flags = overrides.flags ?? FLAG_USER_PRESENT | FLAG_USER_VERIFIED | FLAG_ATTESTED_DATA;
    const authData = await authenticatorData(flags, attestedData);
    const attestationObject = cborEncode(
      new Map<CborValue, CborValue>([
        ["fmt", "none"],
        ["attStmt", new Map()],
        ["authData", authData],
      ]),
    );
    const clientDataJSON = clientData("webauthn.create", registrationOptions.challenge, overrides.origin ?? options.origin);
    return {
      id: credentialIdText,
      rawId: credentialIdText,
      type: "public-key",
      clientExtensionResults: {},
      response: {
        clientDataJSON: base64url(clientDataJSON),
        attestationObject: base64url(attestationObject),
        transports: ["internal", "hybrid"],
      },
    };
  }

  // signingKey lets a test sign with a different key than the registered one.
  async function assert(
    authenticationOptions: { challenge: string },
    overrides: { signingKey?: webcrypto.CryptoKey; signCount?: number } = {},
  ) {
    if (overrides.signCount !== undefined) {
      signCount = overrides.signCount;
    }
    const authData = await authenticatorData(FLAG_USER_PRESENT | FLAG_USER_VERIFIED, new Uint8Array());
    const clientDataJSON = clientData("webauthn.get", authenticationOptions.challenge, options.origin);
    const signedBytes = concatBytes(authData, await sha256(clientDataJSON));
    const signingKey = overrides.signingKey ?? keyPair.privateKey;
    const rawSignature = await subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signingKey, signedBytes);
    return {
      id: credentialIdText,
      rawId: credentialIdText,
      type: "public-key",
      clientExtensionResults: {},
      response: {
        clientDataJSON: base64url(clientDataJSON),
        authenticatorData: base64url(authData),
        signature: base64url(rawSignatureToDer(new Uint8Array(rawSignature))),
        userHandle: base64url(userHandle),
      },
    };
  }

  return { credentialId: credentialIdText, register, assert };
}

export async function makeStrayPrivateKey(): Promise<webcrypto.CryptoKey> {
  const keyPair = await subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  return keyPair.privateKey;
}

export const SOFT_AUTHENTICATOR_FLAGS = {
  userPresent: FLAG_USER_PRESENT,
  userVerified: FLAG_USER_VERIFIED,
  attestedData: FLAG_ATTESTED_DATA,
};
