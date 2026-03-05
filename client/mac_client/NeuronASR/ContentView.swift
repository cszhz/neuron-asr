import SwiftUI

struct ContentView: View {
    @StateObject private var manager = ASRManager()
    @State private var serverURL = "ws://127.0.0.1:3003"
    @State private var chunkDurationMs: Double = 600
    @State private var returnTimestamps = true
    @State private var showTimestampsUI = false  // 是否显示时间戳详情

    //Qwen3-ASR
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                Text("Neuron-ASR")
                    .font(.title)
                    .fontWeight(.bold)
            }
            .padding(.top, 20)
            .padding(.bottom, 10)

            Divider()

            // Settings
            GroupBox("Settings") {
                VStack(spacing: 8) {
                    HStack {
                        Text("Server:")
                            .frame(width: 80, alignment: .leading)
                        TextField("ws://127.0.0.1:3003", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .disabled(manager.isRecording)
                    }
                    HStack {
                        Text("Chunk:")
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $chunkDurationMs, in: 600...3000, step: 100)
                            .disabled(manager.isRecording)
                        Text("\(Int(chunkDurationMs))ms")
                            .frame(width: 60)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Timestamps:")
                            .frame(width: 80, alignment: .leading)
                        Toggle("", isOn: $returnTimestamps)
                            .toggleStyle(.switch)
                            .disabled(manager.isRecording)
                            .onChange(of: returnTimestamps) { newValue in
                                manager.returnTimestamps = newValue
                            }
                        Spacer()
                    }
                    HStack {
                        Text("Show Detail:")
                            .frame(width: 80, alignment: .leading)
                        Toggle("", isOn: $showTimestampsUI)
                            .toggleStyle(.switch)
                        Spacer()
                    }
                }
                .padding(.vertical, 5)
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)

            // Control
            HStack(spacing: 15) {
                Button(action: toggleRecording) {
                    HStack {
                        Image(systemName: manager.isRecording ? "stop.fill" : "mic.fill")
                        Text(manager.isRecording ? "Stop" : "Start")
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(manager.isRecording ? .red : .blue)
                .controlSize(.large)

                Button(action: { manager.clearTranscriptions() }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.vertical, 15)

            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(manager.status)
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
                if manager.isRecording {
                    Text("Audio: \(String(format: "%.1f", manager.audioDuration))s")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 25)
            .padding(.bottom, 10)

            // Streaming Preview (LocalAgreement)
            if manager.isStreaming {
                GroupBox("Streaming") {
                    HStack(alignment: .top, spacing: 4) {
                        if !manager.confirmedText.isEmpty {
                            Text(manager.confirmedText)
                                .foregroundColor(.green)
                                .fontWeight(.medium)
                        }
                        if !manager.pendingText.isEmpty {
                            Text(manager.pendingText)
                                .foregroundColor(.orange)
                        }
                        Spacer()
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            Divider()

            // Transcription
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcription")
                        .font(.headline)
                    Spacer()
                    Text("\(manager.transcriptions.count) items")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 5)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(manager.transcriptions) { item in
                                TranscriptionRow(item: item, showTimestampsUI: showTimestampsUI)
                                    .id(item.id)
                            }
                        }
                        .padding(10)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .onChange(of: manager.transcriptions.count) { _ in
                        if let last = manager.transcriptions.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            // Summary
            if !manager.transcriptions.isEmpty {
                GroupBox("Full Text") {
                    ScrollView {
                        Text(manager.fullText)
                            .font(.system(.body, design: .default))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 80)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 15)
            }
        }
        .frame(minWidth: 500, minHeight: 650)
    }

    private var statusColor: Color {
        switch manager.status {
        case "Recording...": return .green
        case "Connected": return .blue
        case let s where s.hasPrefix("Error"): return .red
        default: return .gray
        }
    }

    private func toggleRecording() {
        if manager.isRecording {
            manager.stop()
        } else {
            manager.returnTimestamps = returnTimestamps
            manager.start(serverURL: serverURL, chunkDurationMs: chunkDurationMs)
        }
    }
}

struct TranscriptionRow: View {
    let item: TranscriptionItem
    let showTimestampsUI: Bool
    @State private var showTimestamps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.text)
                    .font(.body)
                    .textSelection(.enabled)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("RTF: \(String(format: "%.3f", item.rtf))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Timestamps (only show when enabled in settings)
            if showTimestampsUI && !item.timestamps.isEmpty {
                Button(action: { showTimestamps.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: showTimestamps ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("Timestamps (\(item.timestamps.count))")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                if showTimestamps {
                    TimestampsView(timestamps: item.timestamps)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

struct TimestampsView: View {
    let timestamps: [TimestampItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(timestamps) { ts in
                    VStack(spacing: 2) {
                        Text(ts.text)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                        Text("\(String(format: "%.2f", ts.startTime))-\(String(format: "%.2f", ts.endTime))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct TranscriptionItem: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let duration: Double
    let rtf: Double
    let isFinal: Bool
    let timestamps: [TimestampItem]
}

struct TimestampItem: Identifiable {
    let id = UUID()
    let text: String
    let startTime: Double
    let endTime: Double
}

#Preview {
    ContentView()
}
