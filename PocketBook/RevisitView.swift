//
//  RevisitView.swift
//  PocketBook
//

import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RevisitView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Board.name, order: .forward) private var boards: [Board]
    @Environment(\.modelContext) private var modelContext
    @State private var draggingNoteID: PersistentIdentifier?
    @State private var isCreatingBoard = false
    @State private var newBoardName = ""

    private var looseNotes: [Note] {
        let now = Date()
        return notes.filter { note in
            guard !note.revisitDone, !note.isBlank, note.boards.isEmpty else { return false }
            let due = note.revisitAfter ?? .distantPast
            return due <= now
        }
    }

    private var trayBoards: [Board] {
        boards.sorted { lhs, rhs in
            if lhs.notes.count != rhs.notes.count { return lhs.notes.count > rhs.notes.count }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Revisit")
                                .font(.largeTitle.bold())
                            Text("Your unorganized thoughts, ready to find a home. Drag notes into boards or skip for now.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if looseNotes.isEmpty {
                            Text("Nothing to revisit")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 240)
                        } else {
                            Text("\(looseNotes.count) NOTES")
                                .font(.caption.weight(.medium))
                                .tracking(0.8)
                                .foregroundStyle(.secondary)

                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(looseNotes) { note in
                                    noteCard(note)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, PocketBarClearance.revisitGrid)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)

                boardTray
                    .padding(.horizontal, 16)
                    .padding(.bottom, PocketBarClearance.tray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeOut(duration: 0.22), value: looseNotes.count)
        }
        .tint(.primary)
        .alert("New Board", isPresented: $isCreatingBoard) {
            TextField("Ideas, Work, Fitness", text: $newBoardName)
            Button("Create") { createBoard() }
            Button("Cancel", role: .cancel) { newBoardName = "" }
        }
    }

    private func noteCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reading(note))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let fileName = note.imageFileNames.first {
                RevisitThumb(fileName: fileName)
            }

            Text(stamp(note.createdAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                later(note)
            } label: {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip for now")
        }
        .onDrag {
            draggingNoteID = note.persistentModelID
            return NSItemProvider(object: token(for: note) as NSString)
        }
    }

    private var boardTray: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                Button {
                    newBoardName = ""
                    isCreatingBoard = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                        Text("New\nBoard")
                            .font(.caption2.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 84)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Board")

                ForEach(trayBoards) { board in
                    boardChip(board)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func boardChip(_ board: Board) -> some View {
        BoardDropTarget(board: board, draggingNoteID: draggingNoteID) { noteID in
            guard let note = notes.first(where: { $0.persistentModelID == noteID }) else { return }
            place(note, on: board)
            draggingNoteID = nil
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol(for: board))
                    .font(.body.weight(.medium))
                Text(board.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(noteCount(board.notes.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(width: 84, height: 84)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func symbol(for board: Board) -> String {
        let name = board.name.lowercased()
        if name.contains("idea") { return "lightbulb" }
        if name.contains("work") || name.contains("job") { return "briefcase" }
        if name.contains("fit") || name.contains("run") || name.contains("gym") { return "figure.run" }
        if name.contains("personal") || name.contains("life") { return "person" }
        let symbols = ["book", "heart", "star", "folder", "music.note", "camera"]
        let index = abs(board.name.hashValue) % symbols.count
        return symbols[index]
    }

    private func noteCount(_ count: Int) -> String {
        count == 1 ? "1 note" : "\(count) notes"
    }

    private func stamp(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today · \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday · \(time)" }
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        return "\(day) · \(time)"
    }

    private func reading(_ note: Note) -> String {
        let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        let transcript = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty { return transcript }
        if note.audioFileName != nil { return "Voice memo" }
        return "Photo"
    }

    private func token(for note: Note) -> String {
        String(describing: note.persistentModelID)
    }

    private func place(_ note: Note, on board: Board) {
        if !note.isOn(board) {
            note.toggleBoard(board)
        }
        note.revisitDone = true
        try? modelContext.save()
    }

    private func later(_ note: Note) {
        note.revisitAfter = Date().addingTimeInterval(86_400 * 3)
        try? modelContext.save()
    }

    private func createBoard() {
        let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(Board(name: name))
        try? modelContext.save()
        newBoardName = ""
    }
}

private struct BoardDropTarget<Label: View>: View {
    var board: Board
    var draggingNoteID: PersistentIdentifier?
    var onDropNote: (PersistentIdentifier) -> Void
    @ViewBuilder var label: () -> Label
    @State private var isTargeted = false

    var body: some View {
        label()
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isTargeted ? 0.8 : 0), lineWidth: 1.5)
            }
            .scaleEffect(isTargeted ? 1.04 : 1)
            .onDrop(of: [.plainText], isTargeted: $isTargeted) { providers in
                guard let draggingNoteID else { return false }
                onDropNote(draggingNoteID)
                _ = providers
                return true
            }
    }
}

private struct RevisitThumb: View {
    var fileName: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.primary.opacity(0.06)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task {
            image = NoteImageStore.thumbnail(fileName: fileName)
        }
    }
}
