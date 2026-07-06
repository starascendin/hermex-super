import Foundation
import SwiftUI

struct ComposerVoiceStatus: Equatable {
    let text: String
    let systemImage: String
    let isError: Bool
}

struct ComposerVoiceStatusView: View {
    let status: ComposerVoiceStatus

    var body: some View {
        Label(status.text, systemImage: status.systemImage)
            .font(.caption)
            .foregroundStyle(status.isError ? Color.red : Color.secondary)
    }
}

/// WeChat-style hold-to-talk surface for the composer voice mode. Release sends;
/// slide up past `ComposerVoiceNoteGesture.cancelTranslationThreshold` cancels.
struct ComposerHoldToTalkButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isDisabled: Bool
    let isRecording: Bool
    let isCancelArmed: Bool
    let onRecordingStart: () -> Void
    let onRecordingDragChanged: (CGFloat) -> Void
    let onRecordingEnd: (CGFloat) -> Void

    @State private var isPressing = false
    @State private var didTriggerRecording = false
    @State private var holdWorkItem: DispatchWorkItem?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))

            Text(title)
                .font(AppFont.body(weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .padding(.horizontal, 16)
        .background(background)
        .foregroundStyle(foreground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isRecording ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(isDisabled && !isRecording ? 0.45 : 1)
        .scaleEffect(isRecording ? 1.01 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isRecording)
        .animation(ChatMotion.quickState(reduceMotion: reduceMotion), value: isCancelArmed)
        .gesture(pressGesture)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Hold to record, release to send."))
        .accessibilityAction(named: Text("Record voice note")) {
            if !isDisabled {
                didTriggerRecording = true
                onRecordingStart()
            }
        }
    }

    private var title: String {
        if isCancelArmed { return String(localized: "Release to Cancel") }
        if isRecording { return String(localized: "Release to Send") }
        return String(localized: "Hold to Talk")
    }

    private var iconName: String {
        isCancelArmed ? "xmark.circle.fill" : "mic.fill"
    }

    private var foreground: Color {
        if isCancelArmed { return .red }
        return isRecording ? .white : .primary
    }

    private var borderColor: Color {
        if isCancelArmed { return .red.opacity(0.45) }
        return isRecording ? .blue.opacity(0.35) : Color(.separator)
    }

    private var background: some ShapeStyle {
        if isCancelArmed {
            return AnyShapeStyle(Color.red.opacity(0.12))
        }
        if isRecording {
            return AnyShapeStyle(Color.blue)
        }
        return AnyShapeStyle(Color(.secondarySystemBackground))
    }

    private var accessibilityLabel: Text {
        if isCancelArmed { return Text("Release to cancel voice note") }
        if isRecording { return Text("Release to send voice note") }
        return Text("Hold to talk")
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isPressing {
                    isPressing = true
                    scheduleRecordingStart()
                }
                if isRecording {
                    onRecordingDragChanged(value.translation.height)
                }
            }
            .onEnded { value in
                cancelScheduledRecordingStart()
                let triggered = didTriggerRecording
                isPressing = false
                didTriggerRecording = false

                if triggered {
                    onRecordingEnd(value.translation.height)
                }
            }
    }

    private func scheduleRecordingStart() {
        guard !isDisabled else { return }

        didTriggerRecording = false
        let item = DispatchWorkItem {
            didTriggerRecording = true
            onRecordingStart()
        }
        holdWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ComposerVoiceNoteGesture.holdActivationDelay,
            execute: item
        )
    }

    private func cancelScheduledRecordingStart() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
    }
}

/// The composer mic. A quick **tap** toggles on-device dictation (unchanged); a
/// **press-and-hold** records a server-transcribed voice note, releasing to send
/// and sliding up to cancel. Both paths run through a single
/// `DragGesture(minimumDistance: 0)`: touch-down schedules a `DispatchWorkItem`
/// after the hold threshold, and a release before it fires cancels the item and
/// counts as a tap → dictation. See `pressGesture` for why timing beats composing
/// `LongPressGesture`/`TapGesture`.
struct ComposerVoiceControlButton: View {
    let isListening: Bool
    let isDisabled: Bool
    let color: Color
    let isRecordingVoiceNote: Bool
    let onTap: () -> Void
    let onRecordingStart: () -> Void
    let onRecordingDragChanged: (CGFloat) -> Void
    let onRecordingEnd: (CGFloat) -> Void

    @State private var isPressing = false
    @State private var didTriggerRecording = false
    @State private var holdWorkItem: DispatchWorkItem?

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 18, weight: .regular))
            .frame(width: 28, height: 28)
            .chatMinimumHitTarget(in: Circle())
            .foregroundStyle(isListening || isRecordingVoiceNote ? Color.red : color)
            .scaleEffect(isRecordingVoiceNote ? 1.3 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecordingVoiceNote)
            .contentShape(Circle())
            .opacity(isDisabled && !isRecordingVoiceNote ? 0.4 : 1)
            .gesture(pressGesture)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                // Default VoiceOver activation (double-tap) toggles dictation.
                // VoiceOver synthesizes an activation rather than a real touch, so
                // the gesture's tap path never fires for it; without this the
                // dictation toggle is unreachable for VoiceOver users.
                if !isDisabled { onTap() }
            }
            .accessibilityAction(named: Text("Record voice note")) {
                // VoiceOver can't hold-to-talk, so this starts recording; the
                // recording bar then exposes "Stop and send" / "Cancel" actions.
                onRecordingStart()
            }
    }

    private var symbolName: String {
        if isRecordingVoiceNote { return "mic.fill" }
        return isListening ? "stop.circle.fill" : "mic"
    }

    private var accessibilityLabel: Text {
        if isRecordingVoiceNote { return Text("Recording voice note") }
        return isListening ? Text("Stop voice input") : Text("Voice input")
    }

    /// One `DragGesture(minimumDistance: 0)` distinguishes tap from hold by timing,
    /// which is far more reliable than composing `LongPressGesture`/`TapGesture`/
    /// `highPriorityGesture` (those let the press keep claiming the touch so the tap
    /// never wins). Touch-down schedules a delayed "start recording"; a release
    /// before the delay cancels it and counts as a tap → dictation. A perfectly
    /// still hold still records because the delay is timer-driven, not movement-driven.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isPressing {
                    isPressing = true
                    scheduleRecordingStart()
                }
                if isRecordingVoiceNote {
                    onRecordingDragChanged(value.translation.height)
                }
            }
            .onEnded { value in
                cancelScheduledRecordingStart()
                let triggered = didTriggerRecording
                isPressing = false
                didTriggerRecording = false

                if triggered {
                    onRecordingEnd(value.translation.height)
                } else if !isDisabled {
                    onTap()
                }
            }
    }

    private func scheduleRecordingStart() {
        didTriggerRecording = false
        let item = DispatchWorkItem {
            didTriggerRecording = true
            onRecordingStart()
        }
        holdWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ComposerVoiceNoteGesture.holdActivationDelay,
            execute: item
        )
    }

    private func cancelScheduledRecordingStart() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
    }
}

/// Telegram-style indicator shown above the composer while a voice note records:
/// a pulsing red dot, an `m:ss` timer, and a slide-to-cancel hint that turns red
/// once the cancel threshold is armed. Exposes explicit VoiceOver actions because
/// the hold-to-talk gesture isn't reachable with VoiceOver on.
struct ComposerVoiceRecordingBar: View {
    let elapsed: TimeInterval
    let isCancelArmed: Bool
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(isCancelArmed ? 0.4 : 1)

            Text(AudioDurationFormatter.string(from: elapsed))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Label(
                isCancelArmed
                    ? String(localized: "Release to cancel")
                    : String(localized: "Slide up to cancel"),
                systemImage: isCancelArmed ? "xmark.circle.fill" : "chevron.up"
            )
            .font(.caption)
            .foregroundStyle(isCancelArmed ? Color.red : Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Recording voice note, \(AudioDurationFormatter.string(from: elapsed))"))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityAction(named: Text("Stop and send"), onStop)
        .accessibilityAction(named: Text("Cancel recording"), onCancel)
    }
}
