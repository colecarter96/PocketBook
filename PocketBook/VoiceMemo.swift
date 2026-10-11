//
//  VoiceMemo.swift
//  PocketBook
//

import AVFoundation
import Speech
import SwiftData
import SwiftUI
import UIKit

enum VoiceMemoStore {
    static var directory: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceMemos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func fileURL(_ fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func makeFileURL() -> URL {
        directory.appendingPathComponent(UUID().uuidString + ".m4a")
    }

    static func delete(_ fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: fileURL(fileName))
    }

    static func deleteAll(except kept: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in files where !kept.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

@MainActor
@Observable
final class VoiceMemoController {
    var recordingNoteID: PersistentIdentifier?
    var playingNoteID: PersistentIdentifier?
    var playbackRunning = false
    var playbackTime: TimeInterval = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var recordURL: URL?
    @ObservationIgnored private var recordingNote: Note?
    @ObservationIgnored private var recordingEditor: TimelineEditor?
    @ObservationIgnored private var capturedDuration: TimeInterval = 0
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognitionRequest: SFSpeechRecognitionRequest?
    @ObservationIgnored private var recognitionGeneration = UUID()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let recorderDelegate = RecorderDelegate()
    @ObservationIgnored private let playerDelegate = PlayerDelegate()

    func toggleRecording(for note: Note, editor: TimelineEditor) {
        if recordingNoteID == note.persistentModelID {
            stopRecording()
        } else if note.audioFileName == nil {
            requestMicrophone {
                self.startRecording(for: note, editor: editor)
            }
        }
    }

    func stopRecordingIfCurrent(_ noteID: PersistentIdentifier?) {
        guard let noteID, recordingNoteID == noteID else { return }
        stopRecording()
    }

    func togglePlayback(for note: Note) {
        guard let fileName = note.audioFileName else { return }
        if playingNoteID == note.persistentModelID, player?.isPlaying == true {
            player?.pause()
            playbackRunning = false
            stopTicking()
            return
        }
        if playingNoteID == note.persistentModelID, let player, !player.isPlaying {
            preparePlaybackSession()
            playbackRunning = true
            player.play()
            startTicking()
            return
        }
        stopPlayback()
        let url = VoiceMemoStore.fileURL(fileName)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        preparePlaybackSession()
        player.delegate = playerDelegate
        playerDelegate.onFinish = { [weak self] in
            self?.stopPlayback()
        }
        self.player = player
        playingNoteID = note.persistentModelID
        playbackRunning = true
        playbackTime = 0
        player.play()
        startTicking()
    }

    func stopPlayback(of note: Note) {
        guard playingNoteID == note.persistentModelID else { return }
        stopPlayback()
    }

    func isPlaying(_ note: Note) -> Bool {
        playbackRunning && playingNoteID == note.persistentModelID
    }

    private func requestMicrophone(_ granted: @escaping @MainActor () -> Void) {
        AVAudioApplication.requestRecordPermission { allowed in
            Task { @MainActor in
                guard allowed else { return }
                granted()
            }
        }
    }

    private func startRecording(for note: Note, editor: TimelineEditor) {
        stopPlayback()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            return
        }

        let url = VoiceMemoStore.makeFileURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return }
        recorder.delegate = recorderDelegate
        recorderDelegate.onFinish = { [weak self] success in
            self?.finishRecording(success: success)
        }
        guard recorder.record() else {
            VoiceMemoStore.delete(url.lastPathComponent)
            return
        }
        self.recorder = recorder
        recordURL = url
        recordingNote = note
        recordingEditor = editor
        recordingNoteID = note.persistentModelID
    }

    private func stopRecording() {
        guard let recorder, recorder.isRecording else { return }
        capturedDuration = recorder.currentTime
        recorder.stop()
    }

    private func finishRecording(success: Bool) {
        let url = recordURL
        let note = recordingNote
        let editor = recordingEditor
        let duration = capturedDuration
        recorder = nil
        recordURL = nil
        recordingNote = nil
        recordingEditor = nil
        recordingNoteID = nil
        capturedDuration = 0

        guard success, duration >= 0.4, let url, let note else {
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        let previous = note.audioFileName
        note.audioFileName = url.lastPathComponent
        note.audioDuration = duration
        if previous != url.lastPathComponent {
            VoiceMemoStore.delete(previous)
        }
        try? note.modelContext?.save()
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        transcribe(url: url, into: note, editor: editor)
    }

    private func transcribe(url: URL, into note: Note, editor: TimelineEditor?) {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else { return }
                self.startRecognition(url: url, into: note, editor: editor, onDevice: true)
            }
        }
    }

    private func startRecognition(
        url: URL,
        into note: Note,
        editor: TimelineEditor?,
        onDevice: Bool
    ) {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return }
        if onDevice, !recognizer.supportsOnDeviceRecognition {
            startRecognition(url: url, into: note, editor: editor, onDevice: false)
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        if onDevice {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        let generation = UUID()
        recognitionGeneration = generation
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, self.recognitionGeneration == generation else { return }
                if isFinal, !transcript.isEmpty {
                    self.recognitionGeneration = UUID()
                    self.recognitionTask = nil
                    self.recognitionRequest = nil
                    editor?.insertTranscript(transcript, into: note)
                } else if error != nil {
                    self.recognitionGeneration = UUID()
                    self.recognitionTask = nil
                    self.recognitionRequest = nil
                    if onDevice {
                        self.startRecognition(url: url, into: note, editor: editor, onDevice: false)
                    } else if !transcript.isEmpty {
                        editor?.insertTranscript(transcript, into: note)
                    }
                }
            }
        }
    }

    private func preparePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        playingNoteID = nil
        playbackRunning = false
        playbackTime = 0
        stopTicking()
    }

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player, player.isPlaying else { return }
                self.playbackTime = player.currentTime
            }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }
}

private final class RecorderDelegate: NSObject, AVAudioRecorderDelegate {
    var onFinish: (@MainActor (Bool) -> Void)?

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let finish = onFinish
        Task { @MainActor in
            finish?(flag)
        }
    }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (@MainActor () -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finish = onFinish
        Task { @MainActor in
            finish?()
        }
    }
}

struct VoiceMemoBar: View {
    @Bindable var note: Note
    @Environment(VoiceMemoController.self) private var voice

    var body: some View {
        if voice.recordingNoteID == note.persistentModelID {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                Text("Recording")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityLabel("Recording")
        } else if note.audioFileName != nil {
            Button {
                voice.togglePlayback(for: note)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: voice.isPlaying(note) ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.semibold))
                        .frame(width: 16)

                    GeometryReader { geometry in
                        let progress = progressWidth(in: geometry.size.width)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.14))
                            Capsule()
                                .fill(Color.primary.opacity(0.55))
                                .frame(width: progress)
                        }
                    }
                    .frame(height: 3)

                    Text(durationText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.isPlaying(note) ? "Pause voice memo" : "Play voice memo")
        }
    }

    private var durationText: String {
        let shown = voice.playingNoteID == note.persistentModelID && voice.playbackTime > 0
            ? voice.playbackTime
            : note.audioDuration
        let total = Int(shown.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func progressWidth(in width: CGFloat) -> CGFloat {
        guard voice.playingNoteID == note.persistentModelID, note.audioDuration > 0 else { return 0 }
        let fraction = min(1, max(0, voice.playbackTime / note.audioDuration))
        return width * fraction
    }
}

struct MemoTranscript: View {
    @Bindable var note: Note
    @Binding var isOpen: Bool
    @Binding var isEditing: Bool
    @State private var editorHeight: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if isOpen {
                        isEditing = false
                    }
                    isOpen.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Transcript")
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen ? "Hide Transcript" : "Show Transcript")
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: NoteHitPreference.self,
                        value: NoteHitFrames(transcriptToggle: geometry.frame(in: .global))
                    )
                }
            }

            if isOpen {
                Group {
                    if isEditing {
                        TranscriptTextView(note: note, onHeight: { height in
                            if abs(editorHeight - height) > 0.5 {
                                editorHeight = height
                            }
                        }, onSave: {
                            isEditing = false
                        })
                        .frame(maxWidth: .infinity, minHeight: editorHeight, alignment: .topLeading)
                    } else {
                        Text(note.transcript.isEmpty ? " " : note.transcript)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(note.transcript.isEmpty ? .clear : .primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 22, alignment: .topLeading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isEditing = true
                            }
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: NoteHitPreference.self,
                            value: NoteHitFrames(transcriptField: geometry.frame(in: .global))
                        )
                    }
                }
            }
        }
    }
}

private struct TranscriptTextView: UIViewRepresentable {
    var note: Note
    var onHeight: (CGFloat) -> Void
    var onSave: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(note: note, onHeight: onHeight, onSave: onSave)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.tintColor = .label
        textView.font = Self.serifBody
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.delegate = context.coordinator
        textView.text = note.transcript
        textView.inputAccessoryView = context.coordinator.makeAccessory(for: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.note = note
        context.coordinator.onHeight = onHeight
        context.coordinator.onSave = onSave
        context.coordinator.textView = textView
        if textView.markedTextRange == nil, !textView.isFirstResponder, textView.text != note.transcript {
            textView.text = note.transcript
        }
        if !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                guard textView.window != nil else { return }
                textView.becomeFirstResponder()
                let end = textView.endOfDocument
                textView.selectedTextRange = textView.textRange(from: end, to: end)
            }
        }
        context.coordinator.publishHeight(of: textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 1 else { return nil }
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: max(22, ceil(height)))
    }

    private static let serifBody: UIFont = {
        let base = UIFont.preferredFont(forTextStyle: .body)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }()

    final class Coordinator: NSObject, UITextViewDelegate {
        var note: Note
        var onHeight: (CGFloat) -> Void
        var onSave: () -> Void
        var didFocus = false
        weak var textView: UITextView?

        init(note: Note, onHeight: @escaping (CGFloat) -> Void, onSave: @escaping () -> Void) {
            self.note = note
            self.onHeight = onHeight
            self.onSave = onSave
        }

        func makeAccessory(for textView: UITextView) -> UIToolbar {
            self.textView = textView
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            let save = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
            let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            bar.items = [flex, save]
            return bar
        }

        @objc func save() {
            note.transcript = textView?.text ?? note.transcript
            try? note.modelContext?.save()
            textView?.resignFirstResponder()
            onSave()
        }

        func textViewDidChange(_ textView: UITextView) {
            note.transcript = textView.text ?? ""
            publishHeight(of: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            note.transcript = textView.text ?? ""
            try? note.modelContext?.save()
        }

        func publishHeight(of textView: UITextView) {
            let width = textView.bounds.width
            guard width > 1 else { return }
            let height = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            let next = max(22, ceil(height))
            DispatchQueue.main.async {
                self.onHeight(next)
            }
        }
    }
}
