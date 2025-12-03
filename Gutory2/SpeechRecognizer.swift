//
//  SpeechRecognizer.swift
//  Gutory2
//
//  Simple ObservableObject wrapper for iOS speech recognition,
//  used by NewLogFlowView for mic-to-text.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import Speech

final class SpeechRecognizer: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var transcript: String = ""
    @Published var isRecording: Bool = false

    // MARK: - Speech Engine Internals

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Permissions

    func requestPermissions() {
        AVAudioSession.sharedInstance().requestRecordPermission { allowed in
            if !allowed {
                print("Microphone permission denied.")
            }
        }

        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("Speech permission granted.")
            case .denied:
                print("Speech permission denied.")
            case .restricted:
                print("Speech restricted.")
            case .notDetermined:
                print("Speech permission not determined.")
            @unknown default:
                print("Unknown speech authorization state.")
            }
        }
    }

    // MARK: - Reset

    func resetTranscript() {
        DispatchQueue.main.async {
            self.transcript = ""
        }
    }

    // MARK: - Start Recording

    func startTranscribing() {
        stopTranscribing() // Cleanup just in case
        resetTranscript()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed:", error)
            return
        }

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        guard let request = request else { return }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                self.stopTranscribing()
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0,
                             bufferSize: 1024,
                             format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        do {
            try audioEngine.start()
            DispatchQueue.main.async { self.isRecording = true }
        } catch {
            print("Audio engine could not start:", error)
        }
    }

    // MARK: - Stop Recording

    func stopTranscribing() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        request?.endAudio()
        recognitionTask?.cancel()

        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
}
