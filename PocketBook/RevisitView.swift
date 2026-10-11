//
//  RevisitView.swift
//  PocketBook
//

import SwiftData
import SwiftUI

struct RevisitView: View {
    @Query(sort: \Note.createdAt, order: .forward) private var notes: [Note]
    @Environment(\.modelContext) private var modelContext
    @State private var boardNote: Note?

    private var dueNote: Note? {
        let now = Date()
        return notes.first { note in
            guard !note.revisitDone else { return false }
            let due = note.revisitAfter ?? note.createdAt.addingTimeInterval(86_400)
            return due <= now
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let dueNote {
                    noteCard(dueNote)
                } else {
                    Text("Nothing to revisit")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.2), value: dueNote?.persistentModelID)
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
        }
        .tint(.primary)
        .sheet(item: $boardNote) { note in
            BoardPickerSheet(note: note, completesOnPick: true) {
                finish(note)
            }
        }
    }

    private func noteCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 14) {
                Text(note.text.isEmpty ? "Empty note" : note.text)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(note.text.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(note.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                revisitButton("Later", systemImage: "clock") {
                    note.revisitAfter = Date().addingTimeInterval(86_400 * 3)
                    try? modelContext.save()
                }
                revisitButton("Board", systemImage: "square.stack") {
                    boardNote = note
                }
                revisitButton("Acknowledge", systemImage: "checkmark") {
                    finish(note)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 96)
        .id(note.persistentModelID)
        .transition(.opacity)
    }

    private func revisitButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.system(.caption, design: .serif))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func finish(_ note: Note) {
        note.revisitDone = true
        try? modelContext.save()
    }
}
