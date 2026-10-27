//
//  SearchView.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct SearchView: View {
    @Binding var query: String
    var isSearchFocused: FocusState<Bool>.Binding
    var recents: [String]
    var onPickRecent: (String) -> Void
    var onOpenNote: () -> Void

    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var openedNoteID: PersistentIdentifier?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matches: [Note] {
        guard !trimmedQuery.isEmpty else { return [] }
        return notes.filter {
            $0.text.localizedStandardContains(trimmedQuery)
                || $0.transcript.localizedStandardContains(trimmedQuery)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PocketCanvas()
                pageContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                searchBar
                    .padding(.horizontal, PocketBarClearance.barInset)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openedNoteID) { id in
                if let note = notes.first(where: { $0.persistentModelID == id }) {
                    NoteDetailView(note: note)
                }
            }
        }
        .tint(.primary)
    }

    @ViewBuilder
    private var pageContent: some View {
        if !trimmedQuery.isEmpty {
            searchResults
        } else if !recents.isEmpty {
            recentSearches
        } else {
            Text("Looking for something?")
                .pocketBody()
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var searchBar: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(
                    "",
                    text: $query,
                    prompt: Text("Search").foregroundStyle(.tertiary)
                )
                .id("pocket-search-field")
                .pocketBody()
                .focused(isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    hideKeyboard()
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, query.isEmpty ? 48 : 82)
            .frame(height: 52)
            .modifier(SearchBarGlass())

            HStack(spacing: 4) {
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(.systemGray))
                            .frame(width: 30, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }

                RedGlassDismissButton(action: hideKeyboard)
                    .frame(width: 34, height: 34)
            }
            .padding(.trailing, 9)
        }
    }

    private func hideKeyboard() {
        isSearchFocused.wrappedValue = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var recentSearches: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("RECENT")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 2)

                ForEach(recents, id: \.self) { term in
                    Button {
                        onPickRecent(term)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "clock.arrow.circlepath")
                                .pocketBody()
                                .foregroundStyle(.tertiary)
                            Text(term)
                                .pocketBody()
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var searchResults: some View {
        if matches.isEmpty {
            Text("No matches")
                .pocketBody()
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(matches) { note in
                Button {
                    onOpenNote()
                    openedNoteID = note.persistentModelID
                } label: {
                    SearchResultRow(note: note, query: trimmedQuery)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(PocketCanvas())
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 16, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SearchBarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule(style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
    }
}

private struct RedGlassDismissButton: UIViewRepresentable {
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> RedGlassButton {
        let button = RedGlassButton(type: .custom)
        button.accessibilityLabel = "Hide"
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: RedGlassButton, context: Context) {
        context.coordinator.action = action
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RedGlassButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 34, height: proposal.height ?? 34)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tap() {
            action()
        }
    }
}

private final class RedGlassButton: UIButton {
    private let mark = UIImageView()
    private let glass: UIVisualEffectView?

    override init(frame: CGRect) {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.tintColor = .systemRed
            glass = UIVisualEffectView(effect: effect)
        } else {
            glass = nil
        }
        super.init(frame: frame)
        if let glass {
            glass.isUserInteractionEnabled = false
            glass.clipsToBounds = true
            addSubview(glass)
        } else {
            backgroundColor = .systemRed
            clipsToBounds = true
        }
        mark.image = UIImage(systemName: "chevron.down")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .bold))
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        mark.contentMode = .center
        mark.isUserInteractionEnabled = false
        addSubview(mark)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass?.frame = bounds
        glass?.layer.cornerRadius = bounds.height / 2
        if glass == nil {
            layer.cornerRadius = bounds.height / 2
        }
        mark.frame = bounds
    }
}

private struct SearchResultRow: View {
    let note: Note
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(highlightedSnippet)
                .pocketBody()
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Text(note.createdAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var highlightedSnippet: AttributedString {
        let snippetText = snippet(from: snippetSource, matching: query)
        var attributed = AttributedString(snippetText)
        var searchStart = snippetText.startIndex

        while let match = snippetText.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<snippetText.endIndex
        ) {
            if let lower = AttributedString.Index(match.lowerBound, within: attributed),
               let upper = AttributedString.Index(match.upperBound, within: attributed) {
                attributed[lower..<upper].font = .body.weight(.semibold)
                attributed[lower..<upper].backgroundColor = Color.yellow.opacity(0.45)
            }
            searchStart = match.upperBound
        }

        return attributed
    }

    private var snippetSource: String {
        if note.text.localizedStandardContains(query) {
            return note.text
        }
        return note.transcript
    }

    private func snippet(from text: String, matching query: String) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        guard let match = flattened.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return flattened
        }

        let start = flattened.index(match.lowerBound, offsetBy: -48, limitedBy: flattened.startIndex) ?? flattened.startIndex
        let end = flattened.index(match.upperBound, offsetBy: 48, limitedBy: flattened.endIndex) ?? flattened.endIndex
        var result = String(flattened[start..<end]).trimmingCharacters(in: .whitespaces)

        if start != flattened.startIndex { result = "…" + result }
        if end != flattened.endIndex { result += "…" }
        return result
    }
}

struct NoteDetailView: View {
    @Bindable var note: Note
    var sourceBoard: Board?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(RecentDelete.self) private var recentDelete
    @Environment(VoiceMemoController.self) private var voice
    @Environment(\.pocketNavHidden) private var pocketNavHidden
    @State private var isConfirmingDelete = false
    @State private var showingBoardPicker = false
    @State private var previewImageName: String?
    @State private var isArrangingPhotos = false
    @State private var showLibrary = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var transcriptEditor = TimelineEditor()
    @State private var transcriptOpen = false
    @State private var transcriptEditing = false

    private var isRecording: Bool {
        voice.recordingNoteID == note.persistentModelID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if note.audioFileName != nil || isRecording {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VoiceMemoBar(note: note)
                        if isRecording {
                            Button("Stop") {
                                voice.toggleRecording(for: note, editor: transcriptEditor)
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    if note.audioFileName != nil {
                        MemoTranscript(
                            note: note,
                            isOpen: $transcriptOpen,
                            isEditing: $transcriptEditing,
                            editor: transcriptEditor,
                            onLibrary: {
                                libraryItems = []
                                showLibrary = true
                            },
                            onCamera: { showCamera = true }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            NoteImageStrip(
                fileNames: note.imageFileNames,
                isArranging: isArrangingPhotos,
                onOpen: { previewImageName = $0 },
                onDelete: { removeImage($0) },
                onFinishArrange: { isArrangingPhotos = false }
            )
            .padding(.horizontal)

            NoteTextView(
                note: note,
                editor: transcriptEditor,
                fillsSpace: true,
                onHeight: { _ in },
                onLibrary: {
                    libraryItems = []
                    showLibrary = true
                },
                onCamera: { showCamera = true }
            )
            .padding(.horizontal)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(note.createdAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Copy", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = note.text
                        }
                        if isRecording {
                            Button("Stop Transcription", systemImage: "stop.fill") {
                                voice.toggleRecording(for: note, editor: transcriptEditor)
                            }
                        } else if note.audioFileName == nil {
                            Button("Add Transcription", systemImage: "mic") {
                                voice.toggleRecording(for: note, editor: transcriptEditor)
                            }
                        } else {
                            Button("Remove Transcription", systemImage: "mic.slash") {
                                removeMemo()
                            }
                        }
                        Button("Photo Library", systemImage: "photo") {
                            libraryItems = []
                            showLibrary = true
                        }
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take Photo", systemImage: "camera") {
                                showCamera = true
                            }
                        }
                        if !note.imageFileNames.isEmpty {
                            Button("Remove Photos", systemImage: "photo.badge.minus") {
                                isArrangingPhotos = true
                            }
                        }
                        Button("Lists", systemImage: "square.stack") {
                            showingBoardPicker = true
                        }
                        if let sourceBoard {
                            Button("Remove from \(sourceBoard.name)", systemImage: "minus.circle") {
                                note.toggleBoard(sourceBoard)
                                try? modelContext.save()
                                dismiss()
                            }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    recentDelete.remember(note)
                    modelContext.delete(note)
                    try? modelContext.save()
                    dismiss()
                }
            }
            .sheet(isPresented: $showingBoardPicker) {
                BoardPickerSheet(note: note)
            }
            .photosPicker(
                isPresented: $showLibrary,
                selection: $libraryItems,
                maxSelectionCount: 10,
                matching: .images
            )
            .onChange(of: showLibrary) { _, isShowing in
                guard !isShowing else { return }
                let picked = libraryItems
                guard !picked.isEmpty else { return }
                Task {
                    await NoteImageStore.importPhotos(picked, into: note)
                    libraryItems = []
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    guard let image else { return }
                    Task {
                        await NoteImageStore.append(image, to: note)
                    }
                }
                .ignoresSafeArea()
            }
            .onAppear {
                pocketNavHidden.wrappedValue = true
            }
            .onDisappear {
                voice.stopRecordingIfCurrent(note.persistentModelID)
                pocketNavHidden.wrappedValue = false
                try? modelContext.save()
            }
            .overlay {
                if let previewImageName {
                    NoteImagePreview(fileName: previewImageName) {
                        self.previewImageName = nil
                    }
                }
            }
    }

    private func removeMemo() {
        voice.stopPlayback(of: note)
        recentDelete.rememberRemovedMemo(from: note)
        note.audioFileName = nil
        note.audioDuration = 0
        note.transcript = ""
        try? modelContext.save()
    }

    private func removeImage(_ fileName: String) {
        recentDelete.rememberRemovedPhoto(fileName, from: note)
        var names = note.imageFileNames
        names.removeAll { $0 == fileName }
        note.imageFileNames = names
        try? modelContext.save()
        if names.isEmpty {
            isArrangingPhotos = false
        }
    }
}
