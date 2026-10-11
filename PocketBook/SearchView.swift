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
    var isFieldFocused: Bool
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
        return notes.filter { $0.text.localizedStandardContains(trimmedQuery) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Looking for something?")
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: showsPromptCentered ? .center : .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, showsPromptCentered ? 72 : 28)
                    .padding(.bottom, 18)

                if !trimmedQuery.isEmpty {
                    searchResults
                } else if !isFieldFocused && !recents.isEmpty {
                    recentSearches
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .navigationDestination(item: $openedNoteID) { id in
                if let note = notes.first(where: { $0.persistentModelID == id }) {
                    NoteDetailView(note: note)
                }
            }
        }
        .tint(.primary)
    }

    private var showsPromptCentered: Bool {
        trimmedQuery.isEmpty && (isFieldFocused || recents.isEmpty)
    }

    private var recentSearches: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(recents, id: \.self) { term in
                    Button {
                        onPickRecent(term)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                            Text(term)
                                .font(.system(.body, design: .serif))
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
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var searchResults: some View {
        if matches.isEmpty {
            Text("No matches")
                .font(.system(.body, design: .serif))
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
                .listRowBackground(Color(.systemBackground))
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.never)
            .contentMargins(.bottom, 96, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SearchResultRow: View {
    let note: Note
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(highlightedSnippet)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Text(note.createdAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var highlightedSnippet: AttributedString {
        let snippetText = snippet(from: note.text, matching: query)
        var attributed = AttributedString(snippetText)
        var searchStart = snippetText.startIndex

        while let match = snippetText.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<snippetText.endIndex
        ) {
            if let lower = AttributedString.Index(match.lowerBound, within: attributed),
               let upper = AttributedString.Index(match.upperBound, within: attributed) {
                attributed[lower..<upper].font = .system(.body, design: .serif).weight(.semibold)
            }
            searchStart = match.upperBound
        }

        return attributed
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

    private var isRecording: Bool {
        voice.recordingNoteID == note.persistentModelID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if note.audioFileName != nil || isRecording {
                HStack(spacing: 12) {
                    VoiceMemoBar(note: note)
                    if isRecording {
                        Button("Stop") {
                            voice.toggleRecording(for: note, editor: transcriptEditor)
                        }
                        .font(.caption.weight(.semibold))
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

            TextField("", text: $note.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.title3, design: .serif))
                .padding(.horizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
                        Button("Boards", systemImage: "square.stack") {
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
                    if let image {
                        NoteImageStore.append(image, to: note)
                        try? modelContext.save()
                    }
                    showCamera = false
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
        VoiceMemoStore.delete(note.audioFileName)
        note.audioFileName = nil
        note.audioDuration = 0
        try? modelContext.save()
    }

    private func removeImage(_ fileName: String) {
        var names = note.imageFileNames
        names.removeAll { $0 == fileName }
        note.imageFileNames = names
        NoteImageStore.delete(fileName)
        try? modelContext.save()
        if names.isEmpty {
            isArrangingPhotos = false
        }
    }
}
