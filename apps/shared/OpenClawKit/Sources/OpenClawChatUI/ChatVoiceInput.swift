import Foundation

@MainActor
public protocol OpenClawChatVoiceInputControlling: AnyObject {
    func startRecording() async throws
    func stopRecording() async throws -> String
}
