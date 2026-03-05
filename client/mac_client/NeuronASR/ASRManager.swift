import Foundation
import AVFoundation
import Combine

class ASRManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isRecording = false
    @Published var status = "Ready"
    @Published var transcriptions: [TranscriptionItem] = []
    @Published var audioDuration: Double = 0.0

    // Streaming state (LocalAgreement)
    @Published var confirmedText = ""
    @Published var pendingText = ""
    @Published var isStreaming = false

    private var audioEngine: AVAudioEngine?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var audioBuffer = Data()
    private var sendTimer: Timer?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var isConnected = false

    private let sampleRate: Double = 16000
    private var chunkDuration: Double = 0.6  // 600ms chunks
    private var samplesPerChunk: Int = 9600  // 16000 * 0.6

    // Settings
    var returnTimestamps = false

    var fullText: String {
        transcriptions.map { $0.text }.joined(separator: " ")
    }

    func start(serverURL: String, chunkDurationMs: Double = 600) {
        guard !isRecording else { return }

        // Configure chunk duration (minimum 600ms)
        let durationMs = max(600, chunkDurationMs)
        chunkDuration = durationMs / 1000.0
        samplesPerChunk = Int(sampleRate * chunkDuration)

        // Connect WebSocket
        guard let url = URL(string: serverURL) else {
            status = "Error: Invalid URL"
            return
        }

        status = "Connecting..."

        // Reset streaming state
        confirmedText = ""
        pendingText = ""
        isStreaming = false

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        // Start receiving messages
        receiveMessage()
    }

    func stop() {
        stopAudioRecording()

        // Send remaining audio
        if !audioBuffer.isEmpty && isConnected {
            sendAudioChunk()
        }

        // Send flush signal (same as Python client)
        if isConnected {
            let flushMessage = URLSessionWebSocketTask.Message.string("{\"type\":\"flush\"}")
            webSocketTask?.send(flushMessage) { _ in }
        }

        // Close WebSocket
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false

        status = "Ready"
        isRecording = false
        audioDuration = 0.0
        isStreaming = false
    }

    func clearTranscriptions() {
        transcriptions.removeAll()
        confirmedText = ""
        pendingText = ""
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.status = "Connected"
            self.sendConfig()
            self.startAudioRecording()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            if self.isRecording {
                self.stop()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.status = "Error: \(error.localizedDescription)"
                self.isConnected = false
                self.isRecording = false
            }
        }
    }

    private func sendConfig() {
        guard isConnected else { return }

        var config: [String: Any] = ["type": "config"]
        if returnTimestamps {
            config["return_timestamps"] = true
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: config),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("Config send error: \(error)")
                }
            }
        }
    }

    private func startAudioRecording() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: sampleRate,
                                                channels: 1,
                                                interleaved: false) else {
            status = "Error: Cannot create audio format"
            return
        }

        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            status = "Error: Cannot create audio converter"
            return
        }

        // Install tap
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        do {
            try audioEngine.start()
            isRecording = true
            status = "Recording..."
            recordingStartTime = Date()
            audioBuffer.removeAll()

            // Start duration timer
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                DispatchQueue.main.async {
                    self.audioDuration = Date().timeIntervalSince(startTime)
                }
            }

            // Start send timer (every 600ms)
            sendTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) { [weak self] _ in
                self?.sendAudioChunk()
            }
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    private func stopAudioRecording() {
        sendTimer?.invalidate()
        sendTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("Conversion error: \(error)")
            return
        }

        // Convert to Int16 and append to buffer
        guard let floatData = convertedBuffer.floatChannelData?[0] else { return }
        let frameLength = Int(convertedBuffer.frameLength)

        var int16Data = [Int16](repeating: 0, count: frameLength)
        for i in 0..<frameLength {
            let sample = floatData[i]
            let clamped = max(-1.0, min(1.0, sample))
            int16Data[i] = Int16(clamped * 32767)
        }

        int16Data.withUnsafeBufferPointer { bufferPointer in
            let data = Data(buffer: bufferPointer)
            DispatchQueue.main.async {
                self.audioBuffer.append(data)
            }
        }
    }

    private func sendAudioChunk() {
        guard isConnected else { return }

        let bytesPerChunk = samplesPerChunk * 2  // Int16 = 2 bytes

        guard audioBuffer.count >= bytesPerChunk else { return }

        let chunk = audioBuffer.prefix(bytesPerChunk)
        audioBuffer.removeFirst(bytesPerChunk)

        // Send as raw bytes (same as Python client)
        webSocketTask?.send(.data(Data(chunk))) { error in
            if let error = error {
                print("Send error: \(error)")
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self?.receiveMessage()

            case .failure(let error):
                DispatchQueue.main.async {
                    if self?.isConnected == true {
                        self?.status = "Error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let messageType = json["type"] as? String ?? "transcription"

        if messageType == "partial" {
            // Streaming partial result (LocalAgreement)
            DispatchQueue.main.async {
                self.isStreaming = true
                self.confirmedText = json["confirmed"] as? String ?? ""
                self.pendingText = json["pending"] as? String ?? ""
            }
        } else if messageType == "transcription" || messageType == "error" {
            // Final transcription or error
            if let transcription = json["text"] as? String, !transcription.isEmpty {
                let duration = json["duration"] as? Double ?? 0.0
                let rtf = json["rtf"] as? Double ?? 0.0
                let isFinal = json["final"] as? Bool ?? false

                // Parse timestamps if available
                var timestamps: [TimestampItem] = []
                if let tsArray = json["timestamps"] as? [[String: Any]] {
                    for ts in tsArray {
                        if let text = ts["text"] as? String,
                           let startTime = ts["start_time"] as? Double,
                           let endTime = ts["end_time"] as? Double {
                            timestamps.append(TimestampItem(text: text, startTime: startTime, endTime: endTime))
                        }
                    }
                }

                let item = TranscriptionItem(
                    text: transcription,
                    timestamp: Date(),
                    duration: duration,
                    rtf: rtf,
                    isFinal: isFinal,
                    timestamps: timestamps
                )

                DispatchQueue.main.async {
                    self.transcriptions.append(item)
                    self.isStreaming = false
                    self.confirmedText = ""
                    self.pendingText = ""
                }
            }

            if messageType == "error" {
                if let errorMsg = json["message"] as? String {
                    DispatchQueue.main.async {
                        self.status = "Error: \(errorMsg)"
                    }
                }
            }
        }
    }
}
