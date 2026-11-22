#if DEBUG && !FOCUS_DESK_UPDATES
import AVFoundation
import Foundation
import Observation
import Security

@MainActor @Observable
final class VoiceCapture: NSObject, AVAudioRecorderDelegate {
    private(set) var isRecording = false
    private(set) var file: URL?
    private(set) var errorMessage: String?
    @ObservationIgnored private var recorder: AVAudioRecorder?

    func start() async throws {
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            throw VoiceNoteError.message("Open the Focus Desk Dev app to record audio, or type your note here.")
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw VoiceNoteError.message("Allow microphone access in System Settings → Privacy & Security → Microphone, or type your note.")
        }
        try Task.checkCancellation()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("focus-desk-\(UUID()).m4a")
        do {
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48000
            ])
            recorder.delegate = self
            guard recorder.record() else { throw VoiceNoteError.message("Recording could not start. Check the input device.") }
            self.recorder = recorder
            file = url
            errorMessage = nil
            isRecording = true
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        isRecording = false
    }

    func discard() {
        stop()
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        errorMessage = nil
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, file == url, isRecording else { return }
            self.recorder = nil
            isRecording = false
            if !flag { errorMessage = "Recording stopped unexpectedly. Try transcribing the available audio or record again." }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        audioRecorderDidFinishRecording(recorder, successfully: false)
    }
}

enum VoiceAPIKey {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "com.dgilmano.focusdesk.dev") + ".openai",
         kSecAttrAccount as String: "voice-tasks"]
    }

    static func read() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        try check(status)
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func save(_ value: String) throws {
        let value = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            try check(SecItemAdd(query.merging(value) { _, new in new } as CFDictionary, nil))
        } else { try check(status) }
    }

    static func forget() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw VoiceNoteError.message("Keychain is unavailable (\(status)). You can still enter a key for this session.")
        }
    }
}
#endif
