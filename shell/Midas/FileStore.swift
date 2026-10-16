import Foundation

/// Files on the phone (unified data plan, section 7): screenshots, images and other things
/// larger than a record. A file is saved here first and queued for upload; `RecordSync` sends
/// every queued file before it pushes records, so a record's `file:<id>` reference never reaches
/// the server before the file does. Files are never changed once saved. One folder per server.
@MainActor
final class FileStore {
    struct Meta: Codable, Equatable, Sendable {
        let contentType: String
        let size: Int
        var uploaded: Bool
    }

    static let referencePrefix = "file:"
    /// The server's limit (backend/src/files.ts MAX_FILE_BYTES).
    static let maxFileBytes = 20 * 1024 * 1024
    static let fileIdPattern = #"^[A-Za-z0-9_-]{8,64}$"#
    private static let pendingFileName = "pending.json"

    let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    /// Application Support/midas-files[-<host>]/, one per server like the record store.
    static func defaultDirectoryURL(platformOrigin: URL = PlatformConfig.platformOrigin) -> URL {
        let host = platformOrigin.host() ?? "unknown"
        let folderName = host == PlatformConfig.liveHost ? "midas-files" : "midas-files-\(host)"
        return URL.applicationSupportDirectory.appending(path: folderName)
    }

    // MARK: References

    static func newFileId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func isValidFileId(_ fileId: String) -> Bool {
        fileId.range(of: fileIdPattern, options: .regularExpression) != nil
    }

    static func reference(for fileId: String) -> String {
        referencePrefix + fileId
    }

    /// "file:abc" -> "abc"; nil for anything that is not a file reference.
    static func fileId(fromReference reference: String) -> String? {
        guard reference.hasPrefix(referencePrefix) else {
            return nil
        }
        let fileId = String(reference.dropFirst(referencePrefix.count))
        return isValidFileId(fileId) ? fileId : nil
    }

    // MARK: Saving and reading

    /// Saves a new file and queues it for upload. Returns its id.
    func save(_ data: Data, contentType: String) throws -> String {
        let fileId = Self.newFileId()
        try write(fileId: fileId, data: data, meta: Meta(contentType: contentType, size: data.count, uploaded: false))
        var pending = pendingUploads()
        pending.append(fileId)
        try writePending(pending)
        return fileId
    }

    /// Keeps a file fetched from the server, so the next read is local.
    func saveDownloaded(fileId: String, data: Data, contentType: String) throws {
        guard Self.isValidFileId(fileId) else {
            throw FileStoreError.badFileId
        }
        try write(fileId: fileId, data: data, meta: Meta(contentType: contentType, size: data.count, uploaded: true))
    }

    func data(for fileId: String) -> (data: Data, contentType: String)? {
        guard Self.isValidFileId(fileId), let meta = meta(for: fileId), let data = try? Data(contentsOf: fileURL(fileId)) else {
            return nil
        }
        return (data, meta.contentType)
    }

    func meta(for fileId: String) -> Meta? {
        guard let metaData = try? Data(contentsOf: metaURL(fileId)) else {
            return nil
        }
        return try? JSONDecoder().decode(Meta.self, from: metaData)
    }

    // MARK: Uploads

    /// The files not yet on the server, oldest first.
    func pendingUploads() -> [String] {
        guard let pendingData = try? Data(contentsOf: directoryURL.appending(path: Self.pendingFileName)) else {
            return []
        }
        return (try? JSONDecoder().decode([String].self, from: pendingData)) ?? []
    }

    func markUploaded(_ fileId: String) throws {
        if var meta = meta(for: fileId) {
            meta.uploaded = true
            let encodedMeta = try JSONEncoder().encode(meta)
            try encodedMeta.write(to: metaURL(fileId), options: [.atomic])
        }
        var pending = pendingUploads()
        pending.removeAll(where: { pendingId in pendingId == fileId })
        try writePending(pending)
    }

    // MARK: The safety net

    /// A record over the size limit because a string field holds a `data:` URL (an image pasted
    /// in as base64): the data moves to a file and the field holds the reference instead (plan
    /// section 7). Nested objects and lists are walked too. Anything else is left as it is.
    func replacingDataURLs(in value: JSONValue) throws -> JSONValue {
        switch value {
        case .string(let text):
            guard let decoded = Self.decodeDataURL(text) else {
                return value
            }
            let fileId = try save(decoded.data, contentType: decoded.contentType)
            return .string(Self.reference(for: fileId))
        case .array(let items):
            var replacedItems: [JSONValue] = []
            for item in items {
                replacedItems.append(try replacingDataURLs(in: item))
            }
            return .array(replacedItems)
        case .object(let fields):
            var replacedFields: [String: JSONValue] = [:]
            for (fieldName, fieldValue) in fields {
                replacedFields[fieldName] = try replacingDataURLs(in: fieldValue)
            }
            return .object(replacedFields)
        default:
            return value
        }
    }

    /// "data:image/png;base64,...." -> the bytes and their type; nil for any other string.
    static func decodeDataURL(_ text: String) -> (data: Data, contentType: String)? {
        guard text.hasPrefix("data:"), let commaIndex = text.firstIndex(of: ",") else {
            return nil
        }
        let header = String(text[text.index(text.startIndex, offsetBy: 5)..<commaIndex])
        guard header.hasSuffix(";base64") else {
            return nil
        }
        let contentType = String(header.dropLast(";base64".count))
        let encoded = String(text[text.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]), !data.isEmpty else {
            return nil
        }
        return (data, contentType.isEmpty ? "application/octet-stream" : contentType)
    }

    // MARK: Files on disk

    private func fileURL(_ fileId: String) -> URL {
        directoryURL.appending(path: fileId)
    }

    private func metaURL(_ fileId: String) -> URL {
        directoryURL.appending(path: "\(fileId).json")
    }

    private func write(fileId: String, data: Data, meta: Meta) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL(fileId), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let encodedMeta = try JSONEncoder().encode(meta)
        try encodedMeta.write(to: metaURL(fileId), options: [.atomic])
    }

    private func writePending(_ pending: [String]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encodedPending = try JSONEncoder().encode(pending)
        try encodedPending.write(to: directoryURL.appending(path: Self.pendingFileName), options: [.atomic])
    }
}

enum FileStoreError: Error, Equatable {
    case badFileId
    case tooLarge
}

/// Moves files between the phone and the server.
protocol FileTransfer: Sendable {
    /// Stores the file on the server under its id (a repeat of the same id is fine). Throws when
    /// the server could not be reached or refused; the file stays queued.
    func upload(fileId: String, data: Data, contentType: String) async throws
    /// The owner's file, or nil when the server has no such file.
    func download(fileId: String) async throws -> (data: Data, contentType: String)?
}

enum FileTransferError: Error, Equatable {
    case signInRequired
    case refused(statusCode: Int)
    case serverError(statusCode: Int)
}

/// POST /files and GET /files/<id> with the user's session.
struct RemoteFileTransfer: FileTransfer {
    static let fileIdHeader = "X-Midas-File-Id"

    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func upload(fileId: String, data: Data, contentType: String) async throws {
        guard let token = sessionToken() else {
            throw FileTransferError.signInRequired
        }
        var request = URLRequest(url: platformOrigin.appending(path: "files"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(fileId, forHTTPHeaderField: Self.fileIdHeader)
        request.httpBody = data
        let (_, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch statusCode {
        case 200...299:
            return
        case 401:
            throw FileTransferError.signInRequired
        case 400, 413:
            throw FileTransferError.refused(statusCode: statusCode)
        default:
            throw FileTransferError.serverError(statusCode: statusCode)
        }
    }

    func download(fileId: String) async throws -> (data: Data, contentType: String)? {
        guard let token = sessionToken() else {
            throw FileTransferError.signInRequired
        }
        var request = URLRequest(url: platformOrigin.appending(path: "files/\(fileId)"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        if statusCode == 404 {
            return nil
        }
        if statusCode == 401 {
            throw FileTransferError.signInRequired
        }
        guard statusCode == 200 else {
            throw FileTransferError.serverError(statusCode: statusCode)
        }
        let contentType = httpResponse?.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
        return (data, contentType)
    }
}
