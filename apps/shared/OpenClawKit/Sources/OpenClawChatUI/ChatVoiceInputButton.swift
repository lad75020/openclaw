import SwiftUI

struct ChatVoiceInputButton: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            if self.isTranscribing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: self.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(6)
        .background(Circle().fill(self.backgroundColor))
        .accessibilityLabel(self.accessibilityLabel)
    }

    private var backgroundColor: Color {
        if self.isRecording {
            return .red
        }
        return Color.accentColor
    }

    private var accessibilityLabel: String {
        if self.isTranscribing {
            return "Transcribing voice message"
        }
        if self.isRecording {
            return "Stop recording"
        }
        return "Start recording"
    }
}
