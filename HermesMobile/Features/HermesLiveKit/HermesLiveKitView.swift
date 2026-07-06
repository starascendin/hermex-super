import SwiftUI

struct HermesLiveKitView: View {
    let server: URL

    @StateObject private var session = HermesLiveKitSession()
    @State private var mode: HermesLiveKitMode = .butler
    @State private var tokenPath = HermesLiveKitGatewayConfiguration.default.tokenPath
    @State private var dispatchPath = HermesLiveKitGatewayConfiguration.default.dispatchPath
    @State private var dispatchesAgent = HermesLiveKitGatewayConfiguration.default.dispatchesAgent
    @State private var draftMessage = ""
    @AppStorage(SessionIdentitySettings.displayNameKey) private var identityDisplayName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusCard
                gatewayCard
                messagesCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Hermes Voice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if case .connected = session.connectionState {
                    Button("Disconnect") {
                        Task { await session.disconnect() }
                    }
                }
            }
        }
    }

    private var configuration: HermesLiveKitGatewayConfiguration {
        .init(
            tokenPath: tokenPath.trimmingCharacters(in: .whitespacesAndNewlines),
            dispatchPath: dispatchPath.trimmingCharacters(in: .whitespacesAndNewlines),
            dispatchesAgent: dispatchesAgent
        )
    }

    private var statusCard: some View {
        liveKitCard(title: String(localized: "Session")) {
            HStack(spacing: 12) {
                Image(systemName: connectionIcon)
                    .font(AppFont.title3(weight: .semibold))
                    .foregroundStyle(connectionTint)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.connectionState.title)
                        .font(AppFont.headline())

                    Text(server.absoluteString)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }

            if case let .failed(message) = session.connectionState {
                Text(message)
                    .font(AppFont.caption())
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(primaryButtonTitle) {
                    Task {
                        if case .connected = session.connectionState {
                            await session.disconnect()
                        } else {
                            await session.connect(
                                server: server,
                                configuration: configuration,
                                mode: mode,
                                participantName: participantName
                            )
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPrimaryButtonDisabled)

                Button {
                    Task { await session.toggleMicrophone() }
                } label: {
                    Label(
                        session.isMicrophoneEnabled ? String(localized: "Mute") : String(localized: "Unmute"),
                        systemImage: session.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(!isConnected)
            }

            Picker("Mode", selection: $mode) {
                ForEach(HermesLiveKitMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isConnected)
        }
    }

    private var gatewayCard: some View {
        liveKitCard(title: String(localized: "Gateway")) {
            TextField("Token path", text: $tokenPath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .disabled(isConnected)

            Toggle(isOn: $dispatchesAgent) {
                Text("Dispatch Hermes agent")
                    .font(AppFont.subheadline(weight: .medium))
            }
            .disabled(isConnected)

            if dispatchesAgent {
                TextField("Dispatch path", text: $dispatchPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .disabled(isConnected)
            }
        }
    }

    private var messagesCard: some View {
        liveKitCard(title: String(localized: "Data Channel")) {
            VStack(alignment: .leading, spacing: 10) {
                if session.messages.isEmpty {
                    Text("Messages from the Hermes gateway appear here.")
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.messages) { message in
                        messageRow(message)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Send text to Hermes", text: $draftMessage, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let message = draftMessage
                    draftMessage = ""
                    Task { await session.sendText(message) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isConnected || draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
    }

    private func liveKitCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .textCase(.uppercase)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.secondary)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func messageRow(_ message: HermesLiveKitMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(senderLabel(for: message.sender))
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(senderTint(for: message.sender))

                if let topic = message.topic, !topic.isEmpty {
                    Text(topic)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }
            }

            Text(message.text)
                .font(AppFont.subheadline())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var participantName: String? {
        let trimmed = identityDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var isConnected: Bool {
        if case .connected = session.connectionState { return true }
        return false
    }

    private var isPrimaryButtonDisabled: Bool {
        if case .connecting = session.connectionState { return true }
        if case .disconnecting = session.connectionState { return true }
        return false
    }

    private var primaryButtonTitle: String {
        if isConnected {
            return String(localized: "Disconnect")
        }
        return String(localized: "Connect")
    }

    private var connectionIcon: String {
        switch session.connectionState {
        case .connected:
            return "waveform.circle.fill"
        case .connecting, .disconnecting:
            return "clock.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "waveform.circle"
        }
    }

    private var connectionTint: Color {
        switch session.connectionState {
        case .connected:
            return .green
        case .connecting, .disconnecting:
            return .blue
        case .failed:
            return .orange
        case .idle:
            return .secondary
        }
    }

    private func senderLabel(for sender: HermesLiveKitMessage.Sender) -> String {
        switch sender {
        case .local:
            return String(localized: "You")
        case let .remote(identity):
            return identity
        case .system:
            return String(localized: "System")
        }
    }

    private func senderTint(for sender: HermesLiveKitMessage.Sender) -> Color {
        switch sender {
        case .local:
            return .blue
        case .remote:
            return .green
        case .system:
            return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        HermesLiveKitView(server: URL(staticString: "http://100.78.186.127:8787"))
    }
}
