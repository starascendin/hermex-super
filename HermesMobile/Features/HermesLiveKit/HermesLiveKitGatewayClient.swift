import Foundation

enum HermesLiveKitMode: String, CaseIterable, Identifiable {
    case butler
    case coaching

    var id: String { rawValue }

    var title: String {
        switch self {
        case .butler:
            return String(localized: "Butler")
        case .coaching:
            return String(localized: "Coaching")
        }
    }
}

struct HermesLiveKitCredentials: Equatable, Sendable {
    let serverURL: String
    let token: String
    let roomName: String
    let participantIdentity: String?
}

struct HermesLiveKitGatewayConfiguration: Equatable, Sendable {
    var tokenPath: String
    var dispatchPath: String
    var dispatchesAgent: Bool

    static let `default` = Self(
        tokenPath: "/api/livekit/token",
        dispatchPath: "/api/livekit/dispatch",
        dispatchesAgent: true
    )
}

enum HermesLiveKitGatewayError: LocalizedError {
    case invalidPath(String)
    case invalidResponse
    case missingCredentials
    case http(statusCode: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case let .invalidPath(path):
            return String(localized: "Invalid LiveKit gateway path: \(path)")
        case .invalidResponse:
            return String(localized: "The LiveKit gateway returned an invalid response.")
        case .missingCredentials:
            return String(localized: "The LiveKit gateway did not return a URL and token.")
        case let .http(statusCode, body):
            if let body, !body.isEmpty {
                return String(localized: "LiveKit gateway returned HTTP \(statusCode): \(body)")
            }
            return String(localized: "LiveKit gateway returned HTTP \(statusCode).")
        }
    }
}

actor HermesLiveKitGatewayClient {
    private let baseURL: URL
    private let session: URLSession
    private let customHeaderProvider: @Sendable () -> [CustomHeader]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        session: URLSession = .shared,
        customHeaderProvider: @escaping @Sendable () -> [CustomHeader] = { CustomHeaderStore.shared.snapshot() }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.customHeaderProvider = customHeaderProvider
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder()
    }

    func createSession(
        configuration: HermesLiveKitGatewayConfiguration,
        mode: HermesLiveKitMode,
        participantName: String?
    ) async throws -> HermesLiveKitCredentials {
        let roomName = "hermex-\(UUID().uuidString.lowercased())"
        let identity = "ios-\(UUID().uuidString.prefix(8).lowercased())"
        let metadata = HermesLiveKitParticipantMetadata(client: "hermex-ios", mode: mode.rawValue)

        let request = HermesLiveKitTokenRequest(
            roomName: roomName,
            participantIdentity: String(identity),
            participantName: participantName,
            participantMetadata: String(data: try encoder.encode(metadata), encoding: .utf8),
            mode: mode.rawValue
        )

        let credentials: HermesLiveKitCredentials = try await post(
            path: configuration.tokenPath,
            body: request
        )
        let resolvedCredentials = credentials.roomName.isEmpty
            ? HermesLiveKitCredentials(
                serverURL: credentials.serverURL,
                token: credentials.token,
                roomName: roomName,
                participantIdentity: credentials.participantIdentity
            )
            : credentials

        if configuration.dispatchesAgent {
            let dispatch = HermesLiveKitDispatchRequest(
                roomName: resolvedCredentials.roomName,
                mode: mode.rawValue
            )
            try? await postIgnoringResponse(path: configuration.dispatchPath, body: dispatch)
        }

        return resolvedCredentials
    }

    private func post<Response: Decodable, Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        let data = try await postData(path: path, body: body)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw HermesLiveKitGatewayError.invalidResponse
        }
    }

    private func postIgnoringResponse<Body: Encodable>(
        path: String,
        body: Body
    ) async throws {
        _ = try await postData(path: path, body: body)
    }

    private func postData<Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> Data {
        var request = URLRequest(url: try url(for: path))
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        customHeaderProvider().apply(to: &request)
        request.httpBody = try encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesLiveKitGatewayError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HermesLiveKitGatewayError.http(
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }

        return data
    }

    private func url(for path: String) throws -> URL {
        guard path.hasPrefix("/") else {
            throw HermesLiveKitGatewayError.invalidPath(path)
        }
        return baseURL.appending(path: path)
    }
}

private struct HermesLiveKitParticipantMetadata: Encodable {
    let client: String
    let mode: String
}

private struct HermesLiveKitTokenRequest: Encodable {
    let roomName: String
    let participantIdentity: String
    let participantName: String?
    let participantMetadata: String?
    let mode: String
}

private struct HermesLiveKitDispatchRequest: Encodable {
    let roomName: String
    let mode: String
}

extension HermesLiveKitCredentials: Decodable {
    private enum CodingKeys: String, CodingKey {
        case serverURL = "server_url"
        case serverUrl = "serverUrl"
        case url
        case wsURL = "ws_url"
        case wsUrl = "wsUrl"
        case livekitURL = "livekit_url"
        case livekitUrl = "livekitUrl"
        case token
        case accessToken = "access_token"
        case roomName = "room_name"
        case room
        case roomNameCamel = "roomName"
        case participantIdentity = "participant_identity"
        case participantIdentityCamel = "participantIdentity"
        case identity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let serverURL = try container.decodeFirstString(
            for: [.serverURL, .serverUrl, .url, .wsURL, .wsUrl, .livekitURL, .livekitUrl]
        ),
            let token = try container.decodeFirstString(for: [.token, .accessToken])
        else {
            throw HermesLiveKitGatewayError.missingCredentials
        }

        self.serverURL = serverURL
        self.token = token
        roomName = try container.decodeFirstString(for: [.roomName, .roomNameCamel, .room]) ?? ""
        participantIdentity = try container.decodeFirstString(
            for: [.participantIdentity, .participantIdentityCamel, .identity]
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeFirstString(for keys: [Key]) throws -> String? {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
