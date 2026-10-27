//
//  RevisitView.swift
//  PocketBook
//

import SwiftData
import SwiftUI
import UIKit

struct RevisitView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Board.name, order: .forward) private var boards: [Board]
    @Environment(\.modelContext) private var modelContext
    @Environment(RecentFiling.self) private var recentFiling
    @FocusState private var listFieldFocused: Bool
    @State private var focusedID: PersistentIdentifier?
    @State private var isCreatingList = false
    @State private var newListName = ""
    @State private var editorNoteID: PersistentIdentifier?
    @State private var actionToken = 0

    private var looseNotes: [Note] {
        let now = Date()
        return notes.filter { note in
            guard !note.revisitDone, !note.isBlank, note.lists.isEmpty else { return false }
            let due = note.revisitAfter ?? .distantPast
            return due <= now
        }
    }

    private var waitingNotes: [Note] {
        let now = Date()
        return notes.filter { note in
            guard !note.revisitDone, !note.isBlank, note.lists.isEmpty else { return false }
            guard let due = note.revisitAfter else { return false }
            return due > now
        }
        .sorted { ($0.revisitAfter ?? .distantFuture) < ($1.revisitAfter ?? .distantFuture) }
    }

    private var current: Note? {
        if let focusedID, let note = looseNotes.first(where: { $0.persistentModelID == focusedID }) {
            return note
        }
        return looseNotes.first
    }

    private var onTheWay: [Note] {
        let rest = looseNotes.filter { $0.persistentModelID != current?.persistentModelID }
        return rest + waitingNotes
    }

    private var lists: [Board] {
        boards.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    if let note = current {
                        visit(note)
                            .id(note.persistentModelID)
                            .transition(.opacity)
                        actions(for: note)
                    } else if onTheWay.isEmpty {
                        Text("Nothing to revisit")
                            .pocketBody()
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }

                    if !onTheWay.isEmpty {
                        trail
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, PocketBarClearance.scroll + 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PocketCanvas())
            .overlay(alignment: .topTrailing) {
                if recentFiling.canUndo {
                    Button {
                        recentFiling.undo(in: modelContext)
                        focusedID = nil
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Undo")
                    .padding(.trailing, 8)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeOut(duration: 0.22), value: current?.persistentModelID)
            .animation(.easeOut(duration: 0.22), value: onTheWay.count)
            .sensoryFeedback(.selection, trigger: actionToken)
            .navigationDestination(item: $editorNoteID) { id in
                if let note = notes.first(where: { $0.persistentModelID == id }) {
                    NoteDetailView(note: note)
                }
            }
        }
        .tint(.primary)
    }

    private func visit(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(reading(note))
                .pocketBody()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if note.audioFileName != nil {
                VoiceMemoBar(note: note)
            }

            if !note.imageFileNames.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(note.imageFileNames, id: \.self) { fileName in
                            RevisitThumb(fileName: fileName, side: note.imageFileNames.count == 1 ? 168 : 112)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 2) {
                Text(stamp(note.createdAt))
                    .font(PocketGeist.font(size: 15))
                    .foregroundStyle(.secondary)
                Button {
                    editorNoteID = note.persistentModelID
                } label: {
                    Text("↗")
                        .font(PocketGeist.font(size: 15))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open note")
            }
        }
    }

    private func actions(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VisitFlow(spacing: 8) {
                ForEach(lists) { board in
                    Button {
                        place(note, on: board)
                    } label: {
                        chipLabel(board.name)
                    }
                    .buttonStyle(.plain)
                }

                if isCreatingList {
                    TextField("List name", text: $newListName)
                        .font(PocketGeist.font(size: 15))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 120, minHeight: 36)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                        .focused($listFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { createList(for: note) }
                } else {
                    Button {
                        newListName = ""
                        isCreatingList = true
                        listFieldFocused = true
                    } label: {
                        chipLabel("New list")
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 22) {
                Button("No list") {
                    leaveUnlisted(note)
                }
                Button("Back in the mix · 3 days") {
                    later(note)
                }
            }
            .font(PocketGeist.font(size: 15))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
    }

    private func chipLabel(_ title: String) -> some View {
        Text(title)
            .font(PocketGeist.font(size: 15))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private var trail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(onTheWay.prefix(5).enumerated()), id: \.element.persistentModelID) { index, note in
                Button {
                    bringForward(note)
                } label: {
                    HStack(spacing: 12) {
                        Text(reading(note))
                            .font(PocketGeist.font(size: 14))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let due = note.revisitAfter, due > Date() {
                            Text(returnLabel(due))
                                .font(PocketGeist.font(size: 13))
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .padding(.leading, CGFloat(index) * 14)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if onTheWay.count > 5 {
                Text("\(onTheWay.count - 5) more")
                    .font(PocketGeist.font(size: 13))
                    .foregroundStyle(.quaternary)
                    .padding(.leading, 14 * 4)
                    .padding(.top, 4)
            }
        }
    }

    private func stamp(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today · \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday · \(time)" }
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        return "\(day) · \(time)"
    }

    private func returnLabel(_ date: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "tomorrow" }
        return "in \(days) days"
    }

    private func reading(_ note: Note) -> String {
        let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        let transcript = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty { return transcript }
        if note.audioFileName != nil { return "Voice memo" }
        return "Photo"
    }

    private func place(_ note: Note, on board: Board) {
        recentFiling.remember(note)
        if !note.isOn(board) {
            note.toggleBoard(board)
        }
        note.revisitDone = true
        note.revisitAfter = nil
        try? modelContext.save()
        finishVisit()
    }

    private func leaveUnlisted(_ note: Note) {
        recentFiling.remember(note)
        note.revisitDone = true
        note.revisitAfter = nil
        try? modelContext.save()
        finishVisit()
    }

    private func later(_ note: Note) {
        recentFiling.remember(note)
        note.revisitAfter = Date().addingTimeInterval(86_400 * 3)
        try? modelContext.save()
        finishVisit()
    }

    private func bringForward(_ note: Note) {
        if let due = note.revisitAfter, due > Date() {
            note.revisitAfter = nil
            try? modelContext.save()
        }
        focusedID = note.persistentModelID
    }

    private func createList(for note: Note) {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = boards.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            place(note, on: existing)
        } else {
            let board = Board(name: name)
            modelContext.insert(board)
            place(note, on: board)
        }
        newListName = ""
        isCreatingList = false
    }

    private func finishVisit() {
        focusedID = nil
        isCreatingList = false
        newListName = ""
        actionToken += 1
    }
}

private struct VisitFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

private struct RevisitThumb: View {
    var fileName: String
    var side: CGFloat = 112
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
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task {
            let name = fileName
            image = await Task.detached(priority: .userInitiated) {
                NoteImageStore.thumbnail(fileName: name)
            }.value
        }
    }
}
