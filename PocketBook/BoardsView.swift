//
//  BoardsView.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import SwiftData
import SwiftUI
import UIKit

struct BoardsView: View {
    @Binding var openListID: PersistentIdentifier?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.createdAt, order: .reverse) private var boards: [Board]

    @State private var isCreatingBoard = false
    @State private var newBoardName = ""
    @State private var path = NavigationPath()
    @State private var isSelecting = false
    @State private var selectedListIDs: Set<PersistentIdentifier> = []
    @State private var listJump: ListJump?
    @State private var jumpToken = 0
    @State private var isScrubbing = false
    @State private var scrubLetter = ""
    @State private var scrubY: CGFloat = 0
    @State private var scrubTick = 0

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                selectBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                if boards.isEmpty {
                    emptyState
                } else {
                    boardList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PocketCanvas())
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                if !isSelecting {
                    newListButton
                        .padding(.trailing, 30)
                        .padding(.bottom, PocketBarClearance.control)
                }
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let board = boards.first(where: { $0.persistentModelID == id }) {
                    BoardDetailView(board: board)
                }
            }
            .onAppear(perform: openPendingList)
            .onChange(of: openListID) { _, _ in
                openPendingList()
            }
            .sensoryFeedback(.selection, trigger: scrubTick)
            .onChange(of: boards.isEmpty) { _, empty in
                if empty { endSelecting() }
            }
            .alert("New List", isPresented: $isCreatingBoard) {
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
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sortedBoards: [Board] {
        boards.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var indexLetters: [String] {
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    }

    private var boardList: some View {
        ScrollViewReader { proxy in
                List {
                    ForEach(sortedBoards) { board in
                        row(board)
                            .id(board.persistentModelID)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 36))
                            .listRowSeparator(.hidden)
                            .listRowBackground(PocketCanvas())
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !isSelecting {
                                    Button(role: .destructive) {
                                        deleteBoards([board])
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 56 + 24 + PocketBarClearance.control, for: .scrollContent)
                .background(PocketCanvas())
                .overlay(alignment: .trailing) {
                    if !sortedBoards.isEmpty {
                        ListLetterIndex(
                            letters: indexLetters,
                            activeLetter: isScrubbing ? scrubLetter : nil,
                            onTap: { reveal($0, animated: true) },
                            onScrub: { letter, y in
                                scrubY = y
                                isScrubbing = true
                                guard letter != scrubLetter else { return }
                                scrubLetter = letter
                                scrubTick += 1
                                reveal(letter, animated: false)
                            },
                            onScrubEnd: {
                                isScrubbing = false
                            }
                        )
                        .padding(.top, 8)
                        .padding(.bottom, 56 + 18 + PocketBarClearance.control)
                        .padding(.trailing, 4)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isScrubbing, !scrubLetter.isEmpty {
                        Text(scrubLetter)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(minWidth: 28)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .offset(x: -40, y: 8 + scrubY - 18)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: listJump) { _, jump in
                    guard let jump else { return }
                    if jump.animated {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(jump.id, anchor: .top)
                        }
                    } else {
                        var transaction = Transaction()
                        transaction.animation = nil
                        withTransaction(transaction) {
                            proxy.scrollTo(jump.id, anchor: .top)
                        }
                    }
                }
            }
        .background(PocketCanvas())
    }

    private var selectBar: some View {
        HStack(spacing: 10) {
            Text("Lists")
                .pocketBody()
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if isSelecting {
                trashButton
            }
            Button {
                if isSelecting {
                    endSelecting()
                } else {
                    beginSelecting()
                }
            } label: {
                Text(isSelecting ? "Done" : "Select")
                    .font(.custom("HelveticaNeue-Medium", size: 16))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .modifier(BarGlass())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelecting ? "Done" : "Select")
        }
    }

    private var trashButton: some View {
        let enabled = !selectedListIDs.isEmpty
        return ZStack {
            Image(systemName: "trash")
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .opacity(enabled ? 1 : 0.35)
                .frame(width: 44, height: 44)
                .modifier(ComposeGlass())
                .allowsHitTesting(false)

            ComposeHitButton {
                deleteSelected()
            }
            .frame(width: 44, height: 44)
            .allowsHitTesting(enabled)
        }
        .frame(width: 44, height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Delete Selected")
        .accessibilityAddTraits(.isButton)
    }

    private func row(_ board: Board) -> some View {
        let selected = selectedListIDs.contains(board.persistentModelID)
        return Group {
            if isSelecting {
                Button {
                    toggleSelection(board)
                } label: {
                    rowLabel(board, selected: selected)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    BoardDetailView(board: board)
                } label: {
                    rowLabel(board, selected: false)
                }
            }
        }
    }

    private func rowLabel(_ board: Board, selected: Bool) -> some View {
        HStack(spacing: 14) {
            if isSelecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.28))
            }
            ListMark(name: board.name)
            Text(board.name)
                .pocketBody()
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text("\(board.listedNotes.count)")
                .pocketBody()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var newListButton: some View {
        ZStack {
            Image(systemName: "plus")
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
                .modifier(ComposeGlass())
                .allowsHitTesting(false)

            ComposeHitButton {
                newBoardName = ""
                isCreatingBoard = true
            }
            .frame(width: 56, height: 56)
        }
        .frame(width: 56, height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New List")
        .accessibilityAddTraits(.isButton)
    }

    private func openPendingList() {
        guard let id = openListID else { return }
        var next = NavigationPath()
        next.append(id)
        path = next
        openListID = nil
    }

    private func listLetter(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        return first.isLetter ? String(first).uppercased() : "#"
    }

    private func reveal(_ letter: String, animated: Bool) {
        guard let board = nearestBoard(to: letter) else { return }
        jumpToken += 1
        listJump = ListJump(id: board.persistentModelID, animated: animated, token: jumpToken)
    }

    private func nearestBoard(to letter: String) -> Board? {
        guard !sortedBoards.isEmpty else { return nil }
        if let exact = sortedBoards.first(where: { listLetter($0.name) == letter }) {
            return exact
        }
        guard let nextIndex = sortedBoards.firstIndex(where: {
            listLetter($0.name).localizedStandardCompare(letter) == .orderedDescending
        }) else {
            return sortedBoards.last
        }
        if nextIndex == 0 {
            return sortedBoards[0]
        }
        let previous = sortedBoards[nextIndex - 1]
        let next = sortedBoards[nextIndex]
        let previousDistance = abs(letterRank(listLetter(previous.name)) - letterRank(letter))
        let nextDistance = abs(letterRank(listLetter(next.name)) - letterRank(letter))
        return previousDistance < nextDistance ? previous : next
    }

    private func letterRank(_ letter: String) -> Int {
        guard let value = letter.unicodeScalars.first?.value, value >= 65, value <= 90 else { return -1 }
        return Int(value)
    }

    private func beginSelecting() {
        selectedListIDs = []
        isSelecting = true
    }

    private func endSelecting() {
        selectedListIDs = []
        isSelecting = false
    }

    private func toggleSelection(_ board: Board) {
        if selectedListIDs.contains(board.persistentModelID) {
            selectedListIDs.remove(board.persistentModelID)
        } else {
            selectedListIDs.insert(board.persistentModelID)
        }
    }

    private func deleteSelected() {
        let chosen = sortedBoards.filter { selectedListIDs.contains($0.persistentModelID) }
        deleteBoards(chosen)
    }

    private func deleteBoards(_ boards: [Board]) {
        guard !boards.isEmpty else { return }
        for board in boards {
            selectedListIDs.remove(board.persistentModelID)
            modelContext.delete(board)
        }
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

private struct ListJump: Equatable {
    var id: PersistentIdentifier
    var animated: Bool
    var token: Int
}

private struct ListMark: View {
    var name: String

    private var letter: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "•" }
        return String(first).uppercased()
    }

    var body: some View {
        Text(letter)
            .font(PocketGeist.font(size: 17))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
            }
    }
}

private struct BarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule(style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
    }
}

private struct ListLetterIndex: View {
    var letters: [String]
    var activeLetter: String?
    var onTap: (String) -> Void
    var onScrub: (String, CGFloat) -> Void
    var onScrubEnd: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: letters.count > 18 ? 10 : 12, weight: .semibold))
                        .foregroundStyle(letter == activeLetter ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .allowsHitTesting(false)

            LetterIndexTouch(
                letterCount: letters.count,
                onTap: { index in
                    guard letters.indices.contains(index) else { return }
                    onTap(letters[index])
                },
                onScrub: { index, y in
                    guard letters.indices.contains(index) else { return }
                    onScrub(letters[index], y)
                },
                onScrubEnd: onScrubEnd
            )
        }
        .frame(width: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("List index")
    }
}

private struct LetterIndexTouch: UIViewRepresentable {
    var letterCount: Int
    var onTap: (Int) -> Void
    var onScrub: (Int, CGFloat) -> Void
    var onScrubEnd: () -> Void

    func makeUIView(context: Context) -> LetterIndexView {
        let view = LetterIndexView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        return view
    }

    func updateUIView(_ uiView: LetterIndexView, context: Context) {
        uiView.letterCount = letterCount
        uiView.onTap = onTap
        uiView.onScrub = onScrub
        uiView.onScrubEnd = onScrubEnd
    }

    static func dismantleUIView(_ uiView: LetterIndexView, coordinator: ()) {
        uiView.cancel()
    }
}

private final class LetterIndexView: UIView {
    var letterCount = 0
    var onTap: (Int) -> Void = { _ in }
    var onScrub: (Int, CGFloat) -> Void = { _, _ in }
    var onScrubEnd: () -> Void = {}

    private var start = CGPoint.zero
    private var last = CGPoint.zero
    private var moved = false
    private var scrubbing = false
    private var timer: Timer?

    func cancel() {
        timer?.invalidate()
        timer = nil
        if scrubbing {
            scrubbing = false
            onScrubEnd()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        start = touch.location(in: self)
        last = start
        moved = false
        scrubbing = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.beginScrub()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        last = touch.location(in: self)
        let dx = last.x - start.x
        let dy = last.y - start.y
        if dx * dx + dy * dy > 64 {
            moved = true
        }
        if scrubbing {
            onScrub(index(at: last.y), last.y)
        } else if moved {
            timer?.invalidate()
            timer = nil
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        timer?.invalidate()
        timer = nil
        if scrubbing {
            scrubbing = false
            onScrubEnd()
        } else if !moved {
            onTap(index(at: start.y))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancel()
    }

    private func beginScrub() {
        timer = nil
        scrubbing = true
        onScrub(index(at: last.y), last.y)
    }

    private func index(at y: CGFloat) -> Int {
        guard letterCount > 0 else { return 0 }
        let height = max(bounds.height, 1)
        let raw = Int(y / height * CGFloat(letterCount))
        return min(letterCount - 1, max(0, raw))
    }
}

struct BoardDetailView: View {
    @Bindable var board: Board
    @Environment(\.modelContext) private var modelContext
    @Environment(RecentDelete.self) private var recentDelete

    private var sortedNotes: [Note] {
        board.listedNotes.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if sortedNotes.isEmpty {
                Text("Nothing on this list yet")
                    .pocketBody()
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
                                    .pocketBody()
                                    .foregroundStyle(note.text.isEmpty ? .tertiary : .primary)

                                Text(note.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(PocketCanvas())
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
                .contentMargins(.bottom, PocketBarClearance.scroll, for: .scrollContent)
                .background(PocketCanvas())
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
    var completesOnPick = false
    var onPlaced: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Board.createdAt, order: .reverse) private var boards: [Board]

    @State private var newBoardName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ThumbCloud(items: boards, key: { String(describing: $0.persistentModelID) }, bottomReserve: 16) { board in
                    Button {
                        if completesOnPick {
                            if !note.isOn(board) {
                                note.toggleBoard(board)
                            }
                            try? modelContext.save()
                            onPlaced()
                            dismiss()
                        } else {
                            note.toggleBoard(board)
                            try? modelContext.save()
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Text(board.name)
                                .font(.system(ThumbCloudStyle.size(for: String(describing: board.persistentModelID)), design: .serif))
                                .foregroundStyle(.primary)
                            if note.isOn(board) {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    TextField("New list", text: $newBoardName)
                        .pocketBody()
                    Button("Add") {
                        createBoardAndAssign()
                    }
                    .disabled(newBoardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            }
            .navigationTitle("Lists")
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
        if completesOnPick {
            onPlaced()
            dismiss()
        }
    }
}

private enum ThumbCloudStyle {
    static func size(for key: String) -> Font.TextStyle {
        switch stableHash(key) % 3 {
        case 0: .body
        case 1: .title3
        default: .title2
        }
    }
}

private struct CloudItemSize: PreferenceKey {
    static var defaultValue: [String: CGSize] = [:]

    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ThumbCloud<Item: Identifiable, Content: View>: View {
    var items: [Item]
    var key: (Item) -> String
    var bottomReserve: CGFloat = 120
    var focusedKey: String? = nil
    var onCenterKey: ((String) -> Void)? = nil
    @ViewBuilder var content: (Item) -> Content

    @State private var measured: [String: CGSize] = [:]

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = ThumbSpot.columnWidth(in: geometry.size.width)
            let layout = ThumbSpot.layout(
                entries: items.map { item in
                    let itemKey = key(item)
                    let size = measured[itemKey] ?? CGSize(width: min(columnWidth, 88), height: 36)
                    return (key: itemKey, size: size)
                },
                viewport: geometry.size,
                columnWidth: columnWidth,
                bottomReserve: bottomReserve
            )
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .frame(width: geometry.size.width, height: layout.height)
                        ForEach(items) { item in
                            content(item)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: columnWidth)
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: CloudItemSize.self,
                                            value: [key(item): proxy.size]
                                        )
                                    }
                                }
                                .position(layout.positions[key(item)] ?? CGPoint(x: geometry.size.width / 2, y: layout.height - bottomReserve))
                                .id(key(item))
                        }
                    }
                    .frame(width: geometry.size.width, height: layout.height)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom)
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y + geo.containerSize.height / 2
                } action: { _, center in
                    guard let onCenterKey else { return }
                    let closest = layout.positions.min { abs($0.value.y - center) < abs($1.value.y - center) }?.key
                    if let closest {
                        onCenterKey(closest)
                    }
                }
                .onChange(of: focusedKey) { _, next in
                    guard let next else { return }
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        proxy.scrollTo(next, anchor: .center)
                    }
                }
            }
            .onPreferenceChange(CloudItemSize.self) { next in
                guard sizesChanged(measured, next) else { return }
                measured = next
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sizesChanged(_ current: [String: CGSize], _ next: [String: CGSize]) -> Bool {
        guard current.count == next.count else { return true }
        for (itemKey, size) in next {
            guard let existing = current[itemKey] else { return true }
            if abs(existing.width - size.width) > 1 || abs(existing.height - size.height) > 1 {
                return true
            }
        }
        return false
    }
}

private enum ThumbSpot {
    static func columnWidth(in width: CGFloat) -> CGFloat {
        let sideInset: CGFloat = 18
        let gap: CGFloat = 16
        return max((width - sideInset * 2 - gap * 2) / 3, 1)
    }

    static func layout(
        entries: [(key: String, size: CGSize)],
        viewport: CGSize,
        columnWidth: CGFloat,
        bottomReserve: CGFloat
    ) -> (positions: [String: CGPoint], height: CGFloat) {
        let sideInset: CGFloat = 18
        let gapX: CGFloat = 16
        let gapY: CGFloat = 18
        let columnX = (0..<3).map { index in
            sideInset + columnWidth / 2 + CGFloat(index) * (columnWidth + gapX)
        }
        let ordered = entries
            .map { entry in
                (key: entry.key, hash: stableHash(entry.key), size: entry.size, column: Int(stableHash(entry.key) % 3))
            }
            .sorted { $0.hash < $1.hash }

        var cursor = [CGFloat](repeating: 0, count: 3)
        var fromBottom: [(key: String, point: CGPoint)] = []
        for entry in ordered {
            let y = cursor[entry.column] + gapY + entry.size.height / 2
            cursor[entry.column] = y + entry.size.height / 2
            let spare = max(0, columnWidth - entry.size.width)
            let jitter = (CGFloat(entry.hash % 1000) / 999 - 0.5) * spare
            fromBottom.append((
                key: entry.key,
                point: CGPoint(x: columnX[entry.column] + jitter, y: y)
            ))
        }

        let packed = (cursor.max() ?? 0) + gapY
        let height = max(viewport.height, packed + bottomReserve + 8)
        var positions: [String: CGPoint] = [:]
        for entry in fromBottom {
            positions[entry.key] = CGPoint(
                x: entry.point.x,
                y: height - bottomReserve - entry.point.y
            )
        }
        return (positions, height)
    }
}

private func stableHash(_ key: String) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in key.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return hash
}
