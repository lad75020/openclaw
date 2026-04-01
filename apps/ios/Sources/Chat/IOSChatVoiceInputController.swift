import AVFAudio
import AudioToolbox
import OpenClawChatUI
import OpenClawKit
import Foundation
import Speech

private struct ChatWebSocketTranscriptionEnvelope: Codable {
    let type: String
    let id: String
    let language: String
    let audio: String
}

private struct ChatWebSocketTranscriptionResponse: Decodable {
    let type: String
    let text: String?
    let fullText: String?
    let message: String?
}

@MainActor
final class IOSChatVoiceInputController: NSObject, OpenClawChatVoiceInputControlling {
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var isRecording = false

    func startRecording() async throws {
        guard !self.isRecording else { return }
        try await self.requestPermissions()
        try Self.configureAudioSession()

        let recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-voice-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let recorder = try AVAudioRecorder(url: recordingURL, settings: Self.recordingSettings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw NSError(domain: "ChatVoiceInput", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to start recording",
            ])
        }

        self.audioRecorder = recorder
        self.recordingURL = recordingURL
        self.isRecording = true
    }

    func stopRecording() async throws -> String {
        guard self.isRecording else { return "" }
        guard let recorder = self.audioRecorder, let recordingURL = self.recordingURL else {
            self.resetRecordingState()
            return ""
        }

        self.isRecording = false
        recorder.stop()
        self.audioRecorder = nil
        self.recordingURL = nil
        defer {
            try? Self.deactivateAudioSession()
            try? FileManager.default.removeItem(at: recordingURL)
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: recordingURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue > 0
        else {
            return ""
        }

        switch GatewaySettingsStore.loadSpeechTranscriptionBackend() {
        case .ios:
            return try await self.transcribeUsingSpeechFramework(recordingURL: recordingURL)
        case .websocket:
            let audioData = try Data(contentsOf: recordingURL)
            return try await self.transcribeUsingWebSocket(audioData: audioData)
        }
    }

    private func requestPermissions() async throws {
        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard microphoneGranted else {
            throw NSError(domain: "ChatVoiceInput", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Microphone access is required",
            ])
        }

        guard GatewaySettingsStore.loadSpeechTranscriptionBackend() == .ios else { return }
        let authorization = SFSpeechRecognizer.authorizationStatus()
        switch authorization {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            guard granted else {
                throw NSError(domain: "ChatVoiceInput", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Speech recognition access is required",
                ])
            }
        default:
            throw NSError(domain: "ChatVoiceInput", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Speech recognition access is required",
            ])
        }
    }

    private func transcribeUsingSpeechFramework(recordingURL: URL) async throws -> String {
        let localeIdentifier = GatewaySettingsStore.loadSpeechLanguage().recognitionLocaleIdentifier
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw NSError(domain: "ChatVoiceInput", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Speech recognizer is unavailable",
            ])
        }
        guard recognizer.isAvailable else {
            throw NSError(domain: "ChatVoiceInput", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "Speech recognizer is currently unavailable",
            ])
        }

        let request = SFSpeechURLRecognitionRequest(url: recordingURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if hasResumed { return }
                if let error {
                    hasResumed = true
                    task?.cancel()
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                hasResumed = true
                task?.cancel()
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }

    private func transcribeUsingWebSocket(audioData: Data) async throws -> String {
        let rawURL = GatewaySettingsStore.loadSpeechTranscriptionWebSocketURL()
        guard let url = URL(string: rawURL) else {
            throw NSError(domain: "ChatVoiceInput", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "Speech WebSocket URL is invalid",
            ])
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()
        defer {
            task.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        let payload = ChatWebSocketTranscriptionEnvelope(
            type: "transcribe",
            id: UUID().uuidString,
            language: GatewaySettingsStore.loadSpeechLanguage().rawValue,
            audio: "data:audio/wav;base64,\(audioData.base64EncodedString())")
        let requestData = try JSONEncoder().encode(payload)
        guard let requestString = String(data: requestData, encoding: .utf8) else {
            throw NSError(domain: "ChatVoiceInput", code: 8, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode transcription request",
            ])
        }

        try await task.send(.string(requestString))

        var latestTranscript = ""
        while true {
            let message = try await task.receive()
            let messageData: Data
            switch message {
            case let .data(data):
                messageData = data
            case let .string(text):
                guard let data = text.data(using: .utf8) else { continue }
                messageData = data
            @unknown default:
                continue
            }

            let response = try JSONDecoder().decode(ChatWebSocketTranscriptionResponse.self, from: messageData)
            switch response.type {
            case "delta":
                latestTranscript = response.fullText ?? response.text ?? latestTranscript
            case "done":
                return (response.text ?? latestTranscript).trimmingCharacters(in: .whitespacesAndNewlines)
            case "error":
                throw NSError(domain: "ChatVoiceInput", code: 9, userInfo: [
                    NSLocalizedDescriptionKey: response.message ?? "WebSocket transcription failed",
                ])
            default:
                continue
            }
        }
    }

    private func resetRecordingState() {
        self.audioRecorder?.stop()
        self.audioRecorder = nil
        self.recordingURL = nil
        self.isRecording = false
    }

    private static var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
    }

    private static func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private static func deactivateAudioSession() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
