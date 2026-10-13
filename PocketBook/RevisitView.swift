//
//  RevisitView.swift
//  PocketBook
//

import SwiftData
import SwiftUI

struct RevisitView: View {
    @Query(sort: \Note.createdAt, order: .forward) private var notes: [Note]
    @Query(sort: \Board.name, order: .forward) private var boards: [Board]
    @Environment(\.modelContext) private var modelContext
    @State private var dragX: CGFloat = 0
    @State private var isDismissing = false
    @State private var previewImageName: String?
    @State private var addedNoteID: PersistentIdentifier?

    private var focus: Note? {
        let now = Date()
        return notes.first { note in
            guard !note.revisitDone, !note.isBlank else { return false }
            let due = note.revisitAfter ?? note.createdAt.addingTimeInterval(86_400)
            return due <= now
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let focus {
                    revisit(focus)
                } else {
                    Text("Nothing to revisit")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .overlay {
                if let previewImageName {
                    NoteImagePreview(fileName: previewImageName) {
                        self.previewImageName = nil
                    }
                }
            }
        }
        .tint(.primary)
    }

    private func revisit(_ note: Note) -> some View {
        let likely = likelyBoards(for: note)
        return VStack(spacing: 0) {
            ZStack {
                swipeBackdrop
                noteBody(note)
                    .offset(x: dragX)
                    .id(note.persistentModelID)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.28), value: note.persistentModelID)

            decisionDock(note, likely: likely)
                .animation(nil, value: note.persistentModelID)
        }
        .onChange(of: note.persistentModelID) { _, _ in
            dragX = 0
            isDismissing = false
            addedNoteID = nil
        }
    }

    private var swipeBackdrop: some View {
        HStack {
            Text("No list")
                .opacity(min(1, max(0, dragX / 72)))
            Spacer()
            Text("Still pondering")
                .opacity(min(1, max(0, -dragX / 72)))
        }
        .font(.system(.title3, design: .serif))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 28)
    }

    private func noteBody(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if addedNoteID == note.persistentModelID {
                Text("Successfully added to list")
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Text(note.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(reading(note))
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(swipe(note))

                if note.audioFileName != nil {
                    VoiceMemoBar(note: note)
                }

                if !note.imageFileNames.isEmpty {
                    NoteImageStrip(fileNames: note.imageFileNames) { fileName in
                        previewImageName = fileName
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityAction(named: "Still pondering") {
            later(note)
        }
        .accessibilityAction(named: "No list") {
            finish(note)
        }
    }

    private func decisionDock(_ note: Note, likely: [Board]) -> some View {
        let featured = Array(likely.prefix(2))
        let featuredIDs = Set(featured.map(\.persistentModelID))
        let others = boards.filter { !featuredIDs.contains($0.persistentModelID) }
        return VStack(alignment: .leading, spacing: 14) {
            if !featured.isEmpty {
                VStack(spacing: 8) {
                    ForEach(featured) { board in
                        choiceButton(board.name) {
                            place(note, on: board)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                decisionButton("Still pondering", fill: Color(white: 0.45), ink: .white) {
                    later(note)
                }
                decisionButton("No list", fill: Color(red: 1, green: 0.78, blue: 0.62), ink: .black) {
                    finish(note)
                }
            }

            if !others.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 22) {
                        ForEach(others) { board in
                            Button {
                                place(note, on: board)
                            } label: {
                                Text(board.name)
                                    .font(.system(.subheadline, design: .serif))
                                    .underline()
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 28)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -28)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 108)
    }

    private func decisionButton(
        _ title: String,
        fill: Color,
        ink: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func choiceButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.black)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func swipe(_ note: Note) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard !isDismissing else { return }
                let translation = value.translation
                guard abs(translation.width) > abs(translation.height) else { return }
                dragX = translation.width
            }
            .onEnded { value in
                guard !isDismissing else { return }
                let width = value.translation.width
                guard abs(width) > abs(value.translation.height) else {
                    withAnimation(.spring(duration: 0.28, bounce: 0)) { dragX = 0 }
                    return
                }
                if width <= -88 {
                    dismiss(note, edge: -1) { later(note) }
                } else if width >= 88 {
                    dismiss(note, edge: 1) { finish(note) }
                } else {
                    withAnimation(.spring(duration: 0.28, bounce: 0)) { dragX = 0 }
                }
            }
    }

    private func likelyBoards(for note: Note) -> [Board] {
        boards
            .map { (board: $0, score: affinity(of: note, for: $0)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.board.name.localizedStandardCompare(rhs.board.name) == .orderedAscending
            }
            .prefix(2)
            .map(\.board)
    }

    private func affinity(of note: Note, for board: Board) -> Double {
        let noteTokens = tokens(note.text + " " + note.transcript)
        var score = note.isOn(board) ? 1_000.0 : 0
        let name = board.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !name.isEmpty {
            let haystack = (note.text + " " + note.transcript).lowercased()
            if haystack.contains(name) {
                score += 6
            }
            score += Double(noteTokens.intersection(tokens(board.name)).count) * 4
        }

        let others = board.notes.filter { $0.persistentModelID != note.persistentModelID }
        var overlap = 0
        var compared = 0
        for other in others.prefix(30) {
            let otherTokens = tokens(other.text + " " + other.transcript)
            guard !otherTokens.isEmpty else { continue }
            compared += 1
            overlap += noteTokens.intersection(otherTokens).count
        }
        if compared > 0 {
            score += Double(overlap) / Double(compared)
        }
        return score
    }

    private func tokens(_ string: String) -> Set<String> {
        let parts = string.lowercased().split { !$0.isLetter && !$0.isNumber }
        return Set(parts.compactMap { part in
            let word = String(part)
            guard word.count > 2, !Self.stopWords.contains(word) else { return nil }
            return word
        })
    }

    private func dismiss(_ note: Note, edge: CGFloat, action: @escaping () -> Void) {
        isDismissing = true
        withAnimation(.easeOut(duration: 0.16)) {
            dragX = edge * 420
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            action()
            dragX = 0
            isDismissing = false
        }
    }

    private func place(_ note: Note, on board: Board) {
        guard addedNoteID == nil, !isDismissing else { return }
        if !note.isOn(board) {
            note.toggleBoard(board)
        }
        try? modelContext.save()
        addedNoteID = note.persistentModelID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            finish(note)
        }
    }

    private func later(_ note: Note) {
        note.revisitAfter = Date().addingTimeInterval(86_400 * 3)
        try? modelContext.save()
    }

    private func finish(_ note: Note) {
        note.revisitDone = true
        try? modelContext.save()
    }

    private func reading(_ note: Note) -> String {
        let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        let transcript = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty { return transcript }
        if note.audioFileName != nil { return "Voice memo" }
        return "Photo"
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "have", "was", "were",
        "are", "but", "not", "you", "your", "its", "just", "about", "into", "then",
        "than", "them", "they", "what", "when", "where", "which", "while", "will",
        "would", "could", "should", "there", "their", "been", "also", "some", "more"
    ]
}
