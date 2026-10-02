import Foundation

/// Error returned by the Agora backend; the message is usually German and can be shown as is.
struct APIError: LocalizedError, Sendable {
    let status: Int
    let message: String

    var errorDescription: String? { message }

    static let generic = "Etwas ist schiefgelaufen. Bitte erneut versuchen."

    /// Text for the user: the server's message, else a generic one.
    static func text(_ error: Error) -> String {
        if let api = error as? APIError, !api.message.trimmingCharacters(in: .whitespaces).isEmpty { return api.message }
        return generic
    }
}

enum HTTPMethod: String, Sendable { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

/// Thin URLSession wrapper around the Agora REST API. Auth is a long-lived JWT sent as Bearer token, and only to
/// the own server (event covers may be external URLs).
final class APIClient: @unchecked Sendable {
    private let lock = NSLock()
    private var _baseURL = ""
    private var _token: String?
    private let userAgent: String
    private let session: URLSession
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    /// Called when the server rejects the token (password changed elsewhere, account deleted ...).
    var onUnauthorized: (@Sendable () -> Void)?

    init(userAgent: String) {
        self.userAgent = userAgent
        let configuration = URLSessionConfiguration.default
        // Unchanged answers come back as "304 Not Modified" (ETag), pictures are reused while the server allows
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 40 * 1024 * 1024, diskPath: "agora-http")
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    var baseURL: String {
        get { lock.withLock { _baseURL } }
        set { lock.withLock { _baseURL = newValue.trimmingCharacters(in: .whitespaces).droppingSuffix("/") } }
    }

    var token: String? {
        get { lock.withLock { _token } }
        set { lock.withLock { _token = newValue } }
    }

    func clearHTTPCache() {
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    // MARK: URLs

    func url(_ path: String, query: [String: String] = [:]) throws -> URL {
        guard var components = URLComponents(string: baseURL + path) else { throw APIError(status: 0, message: "Ungültige Server-Adresse") }
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            // "+" must not stay literal in values (e.g. search text)
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url, url.scheme == "https" || url.scheme == "http" else { throw APIError(status: 0, message: "Ungültige Server-Adresse") }
        return url
    }

    /// Resolves relative asset paths like `/api/events/images/x.jpg` against the server.
    func absolute(_ pathOrURL: String) -> URL? {
        if pathOrURL.hasPrefix("http://") || pathOrURL.hasPrefix("https://") { return URL(string: pathOrURL) }
        guard !pathOrURL.isEmpty else { return nil }
        return URL(string: baseURL + "/" + pathOrURL.droppingPrefix("/"))
    }

    private func isOwnHost(_ url: URL) -> Bool {
        guard let base = URL(string: baseURL) else { return false }
        return base.host == url.host && base.port == url.port
    }

    /// Request with user agent and (for the own server) the token.
    func request(_ url: URL, method: HTTPMethod = .get) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let token, isOwnHost(url) { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    // MARK: JSON calls

    func send<T: Decodable>(_ method: HTTPMethod, _ path: String, query: [String: String] = [:], body: JSONValue? = nil,
                            reportUnauthorized: Bool = true, as type: T.Type = T.self) async throws -> T {
        var request = self.request(try url(path, query: query), method: method)
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        } else if method != .get && method != .delete {
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        let data = try await execute(request, reportUnauthorized: reportUnauthorized)
        return try decode(T.self, data)
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type = T.self) async throws -> T {
        try await send(.get, path, query: query, as: type)
    }

    /// Calls whose answer does not matter.
    func perform(_ method: HTTPMethod, _ path: String, body: JSONValue? = nil) async throws {
        _ = try await send(method, path, body: body, as: JSONValue.self)
    }

    func text(_ path: String) async throws -> String {
        let data = try await execute(request(try url(path)), reportUnauthorized: true)
        return String(decoding: data, as: UTF8.self)
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let payload = data.isEmpty || data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D }) ? Data("{}".utf8) : data
        do {
            return try decoder.decode(T.self, from: payload)
        } catch {
            throw APIError(status: 0, message: "Unerwartete Antwort vom Server")
        }
    }

    // MARK: Uploads

    struct FilePart: Sendable {
        let field: String
        let fileName: String
        let mimeType: String
        let data: Data
    }

    /// Multipart form post; text fields go first (the server builds receipt names from them).
    func upload<T: Decodable>(_ path: String, fields: [(String, String)] = [], file: FilePart, as type: T.Type = T.self) async throws -> T {
        let boundary = "agora-\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in fields {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.fileName)\"\r\nContent-Type: \(file.mimeType)\r\n\r\n")
        body.append(file.data)
        append("\r\n--\(boundary)--\r\n")
        var request = self.request(try url(path), method: .post)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120
        return try decode(T.self, try await execute(request, reportUnauthorized: true))
    }

    // MARK: Execution

    func execute(_ request: URLRequest, reportUnauthorized: Bool) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await load(request)
        } catch let error as APIError {
            throw error
        } catch {
            if (error as NSError).code == NSURLErrorCancelled { throw CancellationError() }
            throw APIError(status: 0, message: Self.networkMessage(error))
        }
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 304 else {
            if http.statusCode == 401 && reportUnauthorized { onUnauthorized?() }
            throw Self.error(status: http.statusCode, body: data)
        }
        return data
    }

    private func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: (data ?? Data(), response))
                } else {
                    continuation.resume(throwing: APIError(status: 0, message: "Keine Antwort vom Server"))
                }
            }
            task.resume()
        }
    }

    static func networkMessage(_ error: Error) -> String {
        let code = (error as NSError).code
        switch code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return "Keine Internetverbindung"
        case NSURLErrorTimedOut: return "Der Server antwortet nicht"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed: return "Server nicht erreichbar"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate:
            return "Keine sichere Verbindung zum Server möglich"
        default: return "Netzwerkfehler"
        }
    }

    /// Route handlers answer `{error}` JSON, the auth middleware answers plain text.
    static func error(status: Int, body: Data) -> APIError {
        if let object = try? JSONDecoder().decode([String: JSONValue].self, from: body),
           let message = object["error"]?.text ?? object["message"]?.text, !message.isEmpty {
            return APIError(status: status, message: message)
        }
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, !text.hasPrefix("<") { return APIError(status: status, message: String(text.prefix(200))) }
        return APIError(status: status, message: "HTTP \(status)")
    }

    // MARK: Streams

    /// Lines of a long-running response (server-sent events). Cancelling the consuming task ends the request.
    func lines(_ request: URLRequest, reportUnauthorized: Bool = true) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let reader = LineReader(continuation: continuation) { [weak self] status in
                if status == 401 && reportUnauthorized { self?.onUnauthorized?() }
            }
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 3600
            configuration.timeoutIntervalForResource = 24 * 3600
            let streamSession = URLSession(configuration: configuration, delegate: reader, delegateQueue: nil)
            var streaming = request
            streaming.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            streaming.timeoutInterval = 3600
            let task = streamSession.dataTask(with: streaming)
            continuation.onTermination = { _ in
                task.cancel()
                streamSession.invalidateAndCancel()
            }
            task.resume()
        }
    }
}

/// Splits a streamed response into lines; a non-2xx status ends the stream with the server's error.
private final class LineReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let onStatus: (Int) -> Void
    private var buffer = Data()
    private var status = 200
    private var errorBody = Data()

    init(continuation: AsyncThrowingStream<String, Error>.Continuation, onStatus: @escaping (Int) -> Void) {
        self.continuation = continuation
        self.onStatus = onStatus
    }

    private var statusRead = false

    /// The status of the response, read once when the first bytes (or the end) arrive.
    private func readStatus(_ task: URLSessionTask) {
        guard !statusRead, let response = task.response as? HTTPURLResponse else { return }
        statusRead = true
        status = response.statusCode
        if !(200..<300).contains(status) { onStatus(status) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        readStatus(dataTask)
        guard (200..<300).contains(status) else {
            errorBody.append(data)
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.last == 0x0D { line.removeLast() }
            continuation.yield(String(decoding: line, as: UTF8.self))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        readStatus(task)
        if !(200..<300).contains(status) {
            continuation.finish(throwing: APIClient.error(status: status, body: errorBody))
        } else if let error, (error as NSError).code != NSURLErrorCancelled {
            continuation.finish(throwing: APIError(status: 0, message: APIClient.networkMessage(error)))
        } else {
            if !buffer.isEmpty { continuation.yield(String(decoding: buffer, as: UTF8.self)) }
            continuation.finish()
        }
        session.finishTasksAndInvalidate()
    }
}

extension String {
    func droppingSuffix(_ suffix: String) -> String {
        var result = self
        while result.hasSuffix(suffix) { result.removeLast(suffix.count) }
        return result
    }

    func droppingPrefix(_ prefix: String) -> String {
        var result = self
        while result.hasPrefix(prefix) { result.removeFirst(prefix.count) }
        return result
    }
}
