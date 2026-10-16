import Foundation

/// Checks a value written under a reserved key prefix. Returns an error message, or nil if valid.
typealias ReservedRecordValidator = @MainActor (JSONValue) -> String?

/// The local channel between a Sidekick and the shell. A Sidekick POSTs JSON to
/// `sidekick://<its id>/_midas/store` with plain fetch; the shell's scheme handler passes the
/// body here. No script message handler, no injected script: the Sidekick sees an ordinary
/// same-origin HTTP endpoint, and the shell knows which Sidekick is calling from the origin.
///
/// Requests: {"op":"set","key":k,"value":v} | {"op":"get","key":k} | {"op":"delete","key":k}
///           | {"op":"query","prefix":p} | {"op":"update","key":k,"patch":p} (JSON Merge Patch)
/// Replies:  {"ok":true} plus "value" (get, update) or "records":[{"key","value"}] (query);
///           {"ok":false,"error":message} with status 400 on a bad request or a value that does
///           not fit its record type (the store's write gate refused it; nothing was written).
@MainActor
final class SidekickStoreChannel {
    static let path = "/_midas/store"
    /// Files: POST the bytes (Content-Type their type) to get {"ok":true,"ref":"file:<id>"};
    /// GET <filesPath>/<id> gives the bytes back (plan section 7; shell/sdk/midas-store.js
    /// `store.putFile` and `store.fileUrl`).
    static let filesPath = "/_midas/files"
    /// The server keeps values up to this size (backend/src/sync.ts MAX_VALUE_BYTES); a larger
    /// one is refused at write time so every record on the phone can be backed up.
    static let maxValueBytes = 64 * 1024

    private let store: LocalRecordStore
    private let reservedValidators: [String: ReservedRecordValidator]
    /// Where files go (and where a `data:` URL in an oversize record is moved to); nil in a
    /// channel without files.
    var fileStore: FileStore?
    /// Fetches a file the phone does not have (a reinstall); nil means local files only.
    var fileTransfer: FileTransfer?
    /// Told about every `request:` record a Sidekick writes (shell requests, e.g. importing Apple
    /// Reminders). The Sidekick id comes from the origin, so a request can only ask for itself.
    var requestObserver: (@MainActor (_ sidekickId: String, _ key: String, _ value: JSONValue) -> Void)?

    struct Reply: Equatable {
        let statusCode: Int
        let body: JSONValue
    }

    init(store: LocalRecordStore, reservedValidators: [String: ReservedRecordValidator] = [:]) {
        self.store = store
        self.reservedValidators = reservedValidators
    }

    func handle(sidekickId: String, requestBody: Data) -> Reply {
        guard let request = try? JSONDecoder().decode(JSONValue.self, from: requestBody) else {
            return Self.failure("body is not JSON")
        }
        guard let operation = request["op"]?.stringValue else {
            return Self.failure("missing op")
        }
        switch operation {
        case "set":
            return handleSet(sidekickId: sidekickId, request: request)
        case "get":
            return handleGet(sidekickId: sidekickId, request: request)
        case "delete":
            return handleDelete(sidekickId: sidekickId, request: request)
        case "query":
            return handleQuery(sidekickId: sidekickId, request: request)
        case "update":
            return handleUpdate(sidekickId: sidekickId, request: request)
        default:
            return Self.failure("unknown op \(operation)")
        }
    }

    private func handleSet(sidekickId: String, request: JSONValue) -> Reply {
        guard let key = Self.validKey(in: request) else {
            return Self.failure("missing key")
        }
        guard let rawValue = request["value"] else {
            return Self.failure("missing value")
        }
        let value: JSONValue
        do {
            value = try withDataURLsMovedToFiles(rawValue)
        } catch {
            return Self.failure("could not save the file")
        }
        if let validationError = reservedValidationError(key: key, value: value) {
            return Self.failure(validationError)
        }
        if RecordSync.valueByteCount(value) > Self.maxValueBytes {
            return Self.failure("value is over \(Self.maxValueBytes) bytes")
        }
        return write(sidekickId: sidekickId, key: key, value: value, replyFields: [:])
    }

    /// The safety net (plan section 7): a value over the record limit because it holds a `data:`
    /// URL gets that data moved to a file and keeps the `file:<id>` reference instead.
    private func withDataURLsMovedToFiles(_ value: JSONValue) throws -> JSONValue {
        guard let fileStore, RecordSync.valueByteCount(value) > Self.maxValueBytes else {
            return value
        }
        return try fileStore.replacingDataURLs(in: value)
    }

    // MARK: Files

    /// A file the page sends (POST to the files path): saved on the phone and queued for upload;
    /// the reply carries the reference to put in a record.
    func handleFilePut(sidekickId: String, body: Data, contentType: String?) -> Reply {
        guard let fileStore else {
            return Self.failure("files are not available")
        }
        guard !body.isEmpty else {
            return Self.failure("file is empty")
        }
        guard body.count <= FileStore.maxFileBytes else {
            return Self.failure("file is over \(FileStore.maxFileBytes) bytes")
        }
        let cleanContentType = contentType?.isEmpty == false ? contentType! : "application/octet-stream"
        do {
            let fileId = try fileStore.save(body, contentType: cleanContentType)
            return Self.success(["ref": .string(FileStore.reference(for: fileId))])
        } catch {
            return Reply(statusCode: 500, body: .object(["ok": .bool(false), "error": .string("could not save the file")]))
        }
    }

    /// The bytes of a file (GET on the files path): from the phone, else fetched from the server
    /// and kept. Nil when there is no such file.
    func fileData(fileId: String) async -> (data: Data, contentType: String)? {
        guard let fileStore, FileStore.isValidFileId(fileId) else {
            return nil
        }
        if let local = fileStore.data(for: fileId) {
            return local
        }
        guard let fileTransfer, let downloaded = try? await fileTransfer.download(fileId: fileId) else {
            return nil
        }
        try? fileStore.saveDownloaded(fileId: fileId, data: downloaded.data, contentType: downloaded.contentType)
        return downloaded
    }

    /// store.update(key, patch): the stored record merged with the patch (RFC 7396), checked and
    /// stored like a set. Replies with the record as stored. A record that does not exist yet is
    /// built from the patch alone.
    private func handleUpdate(sidekickId: String, request: JSONValue) -> Reply {
        guard let key = Self.validKey(in: request) else {
            return Self.failure("missing key")
        }
        guard let patch = request["patch"], case .object = patch else {
            return Self.failure("patch must be an object")
        }
        let currentValue = store.get(sidekickId: sidekickId, key: key)
        let mergedValue: JSONValue
        do {
            mergedValue = try withDataURLsMovedToFiles(JSONMergePatch.apply(patch, to: currentValue))
        } catch {
            return Self.failure("could not save the file")
        }
        if let validationError = reservedValidationError(key: key, value: mergedValue) {
            return Self.failure(validationError)
        }
        if RecordSync.valueByteCount(mergedValue) > Self.maxValueBytes {
            return Self.failure("value is over \(Self.maxValueBytes) bytes")
        }
        return write(sidekickId: sidekickId, key: key, value: mergedValue, replyFields: nil)
    }

    // Stores the value; replies with `replyFields`, or with the value as stored when nil.
    private func write(sidekickId: String, key: String, value: JSONValue, replyFields: [String: JSONValue]?) -> Reply {
        do {
            try store.set(sidekickId: sidekickId, key: key, value: value)
        } catch let refusal as RecordRefusal {
            return Self.failure(refusal.reason)
        } catch {
            return Reply(statusCode: 500, body: .object(["ok": .bool(false), "error": .string("could not save")]))
        }
        let storedValue = store.get(sidekickId: sidekickId, key: key) ?? value
        if key.hasPrefix(ShellRequests.keyPrefix) {
            requestObserver?(sidekickId, key, storedValue)
        }
        return Self.success(replyFields ?? ["value": storedValue])
    }

    private func handleGet(sidekickId: String, request: JSONValue) -> Reply {
        guard let key = Self.validKey(in: request) else {
            return Self.failure("missing key")
        }
        let storedValue = store.get(sidekickId: sidekickId, key: key) ?? .null
        return Self.success(["value": storedValue])
    }

    private func handleDelete(sidekickId: String, request: JSONValue) -> Reply {
        guard let key = Self.validKey(in: request) else {
            return Self.failure("missing key")
        }
        do {
            try store.delete(sidekickId: sidekickId, key: key)
        } catch {
            return Reply(statusCode: 500, body: .object(["ok": .bool(false), "error": .string("could not save")]))
        }
        return Self.success([:])
    }

    private func handleQuery(sidekickId: String, request: JSONValue) -> Reply {
        let keyPrefix = request["prefix"]?.stringValue ?? ""
        let matchingRecords = store.query(sidekickId: sidekickId, keyPrefix: keyPrefix)
        var encodedRecords: [JSONValue] = []
        for record in matchingRecords {
            let encodedRecord = JSONValue.object(["key": .string(record.key), "value": record.value])
            encodedRecords.append(encodedRecord)
        }
        return Self.success(["records": .array(encodedRecords)])
    }

    private func reservedValidationError(key: String, value: JSONValue) -> String? {
        for (reservedPrefix, validator) in reservedValidators where key.hasPrefix(reservedPrefix) {
            if let validationError = validator(value) {
                return validationError
            }
        }
        return nil
    }

    private static func validKey(in request: JSONValue) -> String? {
        guard let key = request["key"]?.stringValue, !key.isEmpty else {
            return nil
        }
        return key
    }

    private static func success(_ fields: [String: JSONValue]) -> Reply {
        var replyFields = fields
        replyFields["ok"] = .bool(true)
        return Reply(statusCode: 200, body: .object(replyFields))
    }

    private static func failure(_ message: String) -> Reply {
        let replyFields: [String: JSONValue] = ["ok": .bool(false), "error": .string(message)]
        return Reply(statusCode: 400, body: .object(replyFields))
    }
}
