import Foundation
import LiveKit

struct HermesLiveKitMessage: Identifiable, Equatable {
    enum Sender: Equatable {
        case local
        case remote(String)
        case system
    }

    let id = UUID()
    let sender: Sender
    let text: String
    let topic: String?
    let date: Date
}

@MainActor
final class HermesLiveKitSession: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected(roomName: String)
        case disconnecting
        case failed(String)

        var title: String {
            switch self {
            case .idle:
                return String(localized: "Idle")
            case .connecting:
                return String(localized: "Connecting")
            case .connected:
                return String(localized: "Connected")
            case .disconnecting:
                return String(localized: "Disconnecting")
            case .failed:
                return String(localized: "Failed")
            }
        }
    }

    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var isMicrophoneEnabled = false
    @Published private(set) var messages: [HermesLiveKitMessage] = []

    private var room: Room?
    private let textTopic = "hermes.text"

    func connect(
        server: URL,
        configuration: HermesLiveKitGatewayConfiguration,
        mode: HermesLiveKitMode,
        participantName: String?
    ) async {
        guard case .connecting = connectionState else {
            connectionState = .connecting
            do {
                let gateway = HermesLiveKitGatewayClient(baseURL: server)
                let credentials = try await gateway.createSession(
                    configuration: configuration,
                    mode: mode,
                    participantName: participantName
                )
                let room = Room(delegate: self)
                try await room.connect(url: credentials.serverURL, token: credentials.token)
                try await room.localParticipant.setMicrophone(enabled: true)

                self.room = room
                isMicrophoneEnabled = true
                connectionState = .connected(roomName: credentials.roomName)
                appendSystemMessage(String(localized: "Connected to \(credentials.roomName.isEmpty ? "LiveKit" : credentials.roomName)."))
            } catch {
                self.room = nil
                isMicrophoneEnabled = false
                connectionState = .failed(error.localizedDescription)
                appendSystemMessage(error.localizedDescription)
            }
            return
        }
    }

    func disconnect() async {
        guard let room else {
            connectionState = .idle
            return
        }
        connectionState = .disconnecting
        await room.disconnect()
        self.room = nil
        isMicrophoneEnabled = false
        connectionState = .idle
        appendSystemMessage(String(localized: "Disconnected."))
    }

    func toggleMicrophone() async {
        guard let room else { return }
        do {
            let nextValue = !isMicrophoneEnabled
            try await room.localParticipant.setMicrophone(enabled: nextValue)
            isMicrophoneEnabled = nextValue
        } catch {
            appendSystemMessage(error.localizedDescription)
        }
    }

    func sendText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let room else { return }

        do {
            guard let data = trimmed.data(using: .utf8) else { return }
            try await room.localParticipant.publish(
                data: data,
                options: DataPublishOptions(topic: textTopic, reliable: true)
            )
            messages.append(.init(sender: .local, text: trimmed, topic: textTopic, date: Date()))
        } catch {
            appendSystemMessage(error.localizedDescription)
        }
    }

    private func appendSystemMessage(_ text: String) {
        messages.append(.init(sender: .system, text: text, topic: nil, date: Date()))
    }
}

extension HermesLiveKitSession: RoomDelegate {
    nonisolated func room(
        _ room: Room,
        participant: RemoteParticipant?,
        didReceiveData data: Data,
        forTopic topic: String,
        encryptionType _: EncryptionType
    ) {
        let senderIdentity = participant?.identity?.stringValue ?? String(localized: "Remote")
        let text = String(data: data, encoding: .utf8) ?? String(localized: "<binary data>")
        Task { @MainActor [weak self] in
            self?.messages.append(.init(
                sender: .remote(senderIdentity),
                text: text,
                topic: topic,
                date: Date()
            ))
        }
    }
}
