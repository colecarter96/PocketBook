//
//  BoardsView.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import SwiftData
import SwiftUI

struct BoardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.createdAt, order: .reverse) private var boards: [Board]

    @State private var isCreatingBoard = false
    @State private var newBoardName = ""

    var body: some View {
        NavigationStack {
            Group {
                if boards.isEmpty {
                    emptyState
                } else {
                    boardList
                }
            }
            .navigationTitle("Boards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Board", systemImage: "plus") {
                        newBoardName = ""
                        isCreatingBoard = true
                    }
                }
            }
            .alert("New Board", isPresented: $isCreatingBoard) {
                TextField("Workout, Surf, Project A", text: $newBoardName)
                Button("Create") {
                    createBoard()
                }
                Button("Cancel", role: .cancel) {
                    newBoardName = ""
                }
            }
        }
        .tint(.primary)
    }

    private var emptyState: some View {
        Text("Boards you create will live here")
            .font(.system(.body, design: .serif))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var boardList: some View {
        List {
            ForEach(boards) { board in
                NavigationLink {
                    BoardDetailView(board: board)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(board.name)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.primary)

                        Text(noteCountLabel(for: board))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color(.systemBackground))
            }
            .onDelete(perform: deleteBoards)
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
    }

    private func noteCountLabel(for board: Board) -> String {
        let count = board.notes.count
        return count == 1 ? "1 note" : "\(count) notes"
    }

    private func createBoard() {
        let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(Board(name: name))
        try? modelContext.save()
        newBoardName = ""
    }

    private func deleteBoards(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(boards[index])
        }
        try? modelContext.save()
    }
}

struct BoardDetailView: View {
    @Bindable var board: Board
    @Environment(\.modelContext) private var modelContext
    @Environment(RecentDelete.self) private var recentDelete

    private var sortedNotes: [Note] {
        board.notes.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if sortedNotes.isEmpty {
                Text("Nothing on this board yet")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedNotes) { note in
                        NavigationLink {
                            NoteDetailView(note: note, sourceBoard: board)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(note.text.isEmpty ? "Empty note" : note.text)
                                    .font(.system(.body, design: .serif))
                                    .foregroundStyle(note.text.isEmpty ? .tertiary : .primary)
                                    .lineLimit(4)

                                Text(note.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemBackground))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteNote(note)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                note.toggleBoard(board)
                                try? modelContext.save()
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .tint(Color(white: 0.45))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Note", systemImage: "plus") {
                    addNoteToBoard()
                }
            }
        }
    }

    private func addNoteToBoard() {
        let note = Note(text: "")
        modelContext.insert(note)
        note.toggleBoard(board)
        try? modelContext.save()
    }

    private func deleteNote(_ note: Note) {
        recentDelete.remember(note)
        modelContext.delete(note)
        try? modelContext.save()
    }
}

struct BoardPickerSheet: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Board.createdAt, order: .reverse) private var boards: [Board]

    @State private var newBoardName = ""

    var body: some View {
        NavigationStack {
            List {
                if !boards.isEmpty {
                    Section {
                        ForEach(boards) { board in
                            Button {
                                note.toggleBoard(board)
                                try? modelContext.save()
                            } label: {
                                HStack {
                                    Text(board.name)
                                        .font(.system(.body, design: .serif))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if note.isOn(board) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("New board", text: $newBoardName)
                            .font(.system(.body, design: .serif))
                        Button("Add") {
                            createBoardAndAssign()
                        }
                        .disabled(newBoardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Boards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .tint(.primary)
        .presentationDetents([.medium, .large])
    }

    private func createBoardAndAssign() {
        let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let board = Board(name: name)
        modelContext.insert(board)
        note.toggleBoard(board)
        try? modelContext.save()
        newBoardName = ""
    }
}
