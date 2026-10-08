//
//  SearchView.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import SwiftData
import SwiftUI
import UIKit

struct SearchView: View {
    var isSelected = false
    var focusToken = 0

    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        isSearchFocused || !trimmedQuery.isEmpty
    }

    private var matches: [Note] {
        guard !trimmedQuery.isEmpty else { return [] }
        return notes.filter { $0.text.localizedStandardContains(trimmedQuery) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !isSearching {
                    dismissibleFill(minHeight: 80)
                }

                VStack(spacing: isSearching ? 20 : 28) {
                    Text("Looking for something?")
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: isSearching ? .leading : .center)
                        .padding(.top, isSearching ? 28 : 0)
                        .onTapGesture(perform: exitSearch)

                    searchPill
                }
                .padding(.horizontal, 24)

                if isSearching {
                    searchResults
                } else {
                    dismissibleFill()
                    dismissibleFill()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSearchFocused {
                    keyboardDismissBar
                }
            }
            .animation(.easeOut(duration: 0.09), value: isSearching)
            .onAppear {
                if isSelected {
                    focusSearch()
                }
            }
            .onChange(of: isSelected) { _, selected in
                if selected {
                    focusSearch()
                } else {
                    isSearchFocused = false
                }
            }
            .onChange(of: focusToken) { _, _ in
                focusSearch()
            }
        }
        .tint(.primary)
    }

    private func focusSearch() {
        isSearchFocused = true
        Task { @MainActor in
            isSearchFocused = true
        }
    }

    private var keyboardDismissBar: some View {
        HStack {
            Spacer()
            Button(action: exitSearch) {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Hide Keyboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
    }

    private func dismissibleFill(minHeight: CGFloat = 0) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: minHeight)
            .contentShape(Rectangle())
            .onTapGesture(perform: exitSearch)
    }

    private func exitSearch() {
        isSearchFocused = false
        query = ""
    }

    private var searchPill: some View {
        HStack(spacing: 12) {
            Button {
                isSearchFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)

            TextField("Search all notes", text: $query)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.primary)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .shadow(color: .black.opacity(isSearchFocused ? 0.08 : 0.05), radius: isSearchFocused ? 18 : 12, y: 4)
    }

    @ViewBuilder
    private var searchResults: some View {
        if trimmedQuery.isEmpty {
            dismissibleFill()
        } else if matches.isEmpty {
            Text("No matches")
                .font(.system(.body, design: .serif))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: exitSearch)
        } else {
            List(matches) { note in
                NavigationLink {
                    NoteDetailView(note: note)
                } label: {
                    SearchResultRow(note: note, query: trimmedQuery)
                }
                .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color(.systemBackground))
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .padding(.top, 12)
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
    @State private var isConfirmingDelete = false
    @State private var showingBoardPicker = false

    var body: some View {
        TextField("", text: $note.text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(.title3, design: .serif))
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .onDisappear {
                try? modelContext.save()
            }
    }
}
