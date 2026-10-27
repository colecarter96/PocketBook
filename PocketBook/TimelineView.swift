//
//  TimelineView.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import SwiftData
import SwiftUI
import PhotosUI
import UIKit

struct TimelineView: View {
    var scrollToTopToken = 0
    var newNoteToken = 0
    var widgetNoteKey = ""
    var widgetOpenToken = 0
    var onOpenList: (PersistentIdentifier) -> Void = { _ in }
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RecentDelete.self) private var recentDelete
    @Environment(RecentFiling.self) private var recentFiling
    @Environment(VoiceMemoController.self) private var voiceMemos
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Board.createdAt, order: .reverse) private var boards: [Board]

    @State private var editor = TimelineEditor()
    @State private var railProgress: CGFloat = 0
    @State private var railDate: Date?
    @State private var isDraggingRail = false
    @State private var canScrollTimeline = false
    @State private var timelineHeight: CGFloat = 0
    @State private var restingTimelineHeight: CGFloat = 0
    @State private var hapticNoteIndex = 0
    @State private var railImpactToken = 0
    @State private var noteFrames: [PersistentIdentifier: CGRect] = [:]
    @State private var radialNoteID: PersistentIdentifier?
    @State private var radialOrigin: CGPoint?
    @State private var radialFinger: CGPoint?
    @State private var radialActions: [NotePressAction] = []
    @State private var hoveredAction: NotePressAction?
    @State private var pressedScale: CGFloat = 1
    @State private var dimFrame: CGRect = .zero
    @State private var menuBounds: CGRect = .zero
    @State private var boardPickerNote: Note?
    @State private var libraryNote: Note?
    @State private var showLibrary = false
    @State private var cameraNote: Note?
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var previewImageName: String?
    @State private var editingPhotosNoteID: PersistentIdentifier?
    @State private var headerHidden: CGFloat = 0
    @State private var topInset: CGFloat = StreamHeader.resolvedTopInset()
    @State private var headerTopToken = 0
    @State private var composeTopToken = 0
    @State private var composeFrame: CGRect = .zero
    @State private var composeTapLock = false
    @State private var editorNoteID: PersistentIdentifier?
    @State private var isSelecting = false
    @State private var selectedNoteIDs: Set<PersistentIdentifier> = []
    @Environment(PocketSettings.self) private var settings
    @State private var showsReadingSettings = false
    @State private var isCreatingList = false
    @State private var newListName = ""
    @State private var handledNewNoteToken = 0
    @State private var handledWidgetOpen = 0

    private var isEditing: Bool { editor.editingID != nil }
    private var canUseRail: Bool {
        notes.count >= 8 && canScrollTimeline && radialNoteID == nil && !isSelecting
    }

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    emptyState
                } else {
                    timeline
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $editorNoteID) { id in
                if let note = notes.first(where: { $0.persistentModelID == id }) {
                    NoteDetailView(note: note)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 14) {
                    if recentDelete.canUndo {
                        Button {
                            recentDelete.undo(in: modelContext)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.gray.opacity(0.55))
                        }
                        .accessibilityLabel("Undo Delete")
                    }

                    if recentFiling.canUndo {
                        Button {
                            recentFiling.undo(in: modelContext)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.gray.opacity(0.55))
                        }
                        .accessibilityLabel("Undo File")
                    }

                    if !isEditing && !isSelecting {
                        composeButton
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: ComposeFramePreference.self,
                                        value: geometry.frame(in: .global)
                                    )
                                }
                            }
                    }
                }
                .padding(.trailing, 30)
                .padding(.bottom, PocketBarClearance.control)
            }
            .background {
                if isEditing || isSelecting {
                    Color.clear.preference(key: ComposeFramePreference.self, value: .zero)
                }
            }
            .onPreferenceChange(ComposeFramePreference.self) { frame in
                composeFrame = frame
            }
            .scrollDismissesKeyboard(.never)
            .photosPicker(
                isPresented: $showLibrary,
                selection: $libraryItems,
                maxSelectionCount: 10,
                matching: .images
            )
            .onChange(of: showLibrary) { _, isShowing in
                guard !isShowing, let note = libraryNote else { return }
                let picked = libraryItems
                libraryNote = nil
                guard !picked.isEmpty else {
                    libraryItems = []
                    return
                }
                Task {
                    await NoteImageStore.importPhotos(picked, into: note)
                    libraryItems = []
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { cameraNote != nil },
                    set: { if !$0 { cameraNote = nil } }
                )
            ) {
                CameraPicker { image in
                    if let image, let note = cameraNote {
                        NoteImageStore.append(image, to: note)
                        try? note.modelContext?.save()
                    }
                    cameraNote = nil
                }
                .ignoresSafeArea()
            }
            .overlay {
                if let previewImageName {
                    NoteImagePreview(fileName: previewImageName) {
                        self.previewImageName = nil
                    }
                }
            }
            .background {
                EditingOutsideTap(editingID: editor.editingID, noteFrame: editingNoteFrame) { editingID in
                    DispatchQueue.main.async {
                        guard editor.editingID == editingID else { return }
                        editor.end()
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: hapticNoteIndex)
        .sensoryFeedback(.impact(weight: .heavy), trigger: railImpactToken)
        .tint(.primary)
        .environment(\.colorScheme, settings.colorway.scheme)
        .environment(\.pocketReading, settings.reading)
        .preferredColorScheme(settings.colorway.scheme)
        .sheet(isPresented: $showsReadingSettings) {
            ReadingSettingsSheet()
        }
        .alert("New List", isPresented: $isCreatingList) {
            TextField("Workout, Surf, Project A", text: $newListName)
            Button("Create") { createList() }
            Button("Cancel", role: .cancel) { newListName = "" }
        }
        .onAppear {
            beginNote(from: newNoteToken)
            openWidgetNote()
        }
        .onChange(of: newNoteToken) { _, token in
            beginNote(from: token)
        }
        .onChange(of: widgetOpenToken) { _, _ in
            openWidgetNote()
        }
        .onChange(of: notes.count) { _, _ in
            openWidgetNote()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                persist()
            }
        }
        .onChange(of: editor.editingID) { previous, _ in
            guard let previous else { return }
            DispatchQueue.main.async {
                discardIfEmpty(previous)
            }
        }
    }

    private var streamHeaderSlide: CGFloat {
        -headerHidden
    }

    private var headerPanelHeight: CGFloat {
        topInset + StreamHeader.height
    }

    private var streamHeaderReach: CGFloat {
        headerPanelHeight
    }

    private var streamMasthead: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: requestHeaderTop) {
                Image("PocketBookWordmark")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 30, alignment: .leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("PocketBook")

            if isSelecting {
                    Button(action: deleteSelected) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(selectedNoteIDs.isEmpty ? Color.primary.opacity(0.25) : Color.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedNoteIDs.isEmpty)
                    .accessibilityLabel("Delete Selected")

                    Button(action: endSelecting) {
                        Text("Done")
                            .font(.custom("HelveticaNeue-Medium", size: 17))
                            .foregroundStyle(.primary)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        showsReadingSettings = true
                    } label: {
                        Text("Aa")
                            .font(.system(size: 18, weight: .semibold, design: .serif))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reading Settings")

                    Button(action: toggleAppearance) {
                        Image(systemName: settings.colorway == .light ? "sun.max" : "sun.max.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(settings.colorway == .light ? Color.primary.opacity(0.35) : Color.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(settings.colorway == .light ? "Switch to Dark Mode" : "Switch to Light Mode")

                    Menu {
                        Button("New Note", systemImage: "plus") {
                            startNewNote()
                        }
                        Button("Select", systemImage: "checkmark.circle") {
                            beginSelecting()
                        }
                    } label: {
                        Text("...")
                            .font(.custom("HelveticaNeue-Medium", size: 18))
                            .baselineOffset(3)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Menu")
                }
        }
        .padding(.bottom, 8)
    }

    private var lists: [Board] {
        boards.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var listInk: Color {
        settings.colorway == .dark ? .white : .black
    }

    private var listStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                Button {
                    newListName = ""
                    isCreatingList = true
                } label: {
                    Text("+")
                        .pocketBody()
                        .foregroundStyle(listInk)
                        .frame(minWidth: 24, minHeight: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New List")

                ForEach(lists) { board in
                    Button {
                        onOpenList(board.persistentModelID)
                    } label: {
                        Text(board.name)
                            .pocketBody()
                            .foregroundStyle(listInk)
                            .lineLimit(1)
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 0)
        }
        .scrollIndicators(.hidden)
    }

    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        newListName = ""
        guard !name.isEmpty else { return }
        guard !boards.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        modelContext.insert(Board(name: name))
        try? modelContext.save()
    }

    private func requestHeaderTop() {
        headerTopToken += 1
    }

    private func toggleAppearance() {
        settings.toggleAppearance()
    }

    private var stickyHeader: some View {
        streamMasthead
            .padding(.top, topInset + 62)
            .padding(.leading, 20 * settings.reading.padScale)
            .padding(.trailing, 16 * settings.reading.padScale)
            .padding(.bottom, 8 * settings.reading.padScale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PocketCanvas())
            .offset(y: streamHeaderSlide)
            .animation(nil, value: headerHidden)
            .allowsHitTesting(headerHidden < headerPanelHeight - 1)
    }

    private var composeButton: some View {
        ZStack {
            Image(systemName: "plus")
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
                .modifier(ComposeGlass())
                .allowsHitTesting(false)

            ComposeHitButton(action: startNewNote)
                .frame(width: 56, height: 56)
        }
        .frame(width: 56, height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New Note")
        .accessibilityAddTraits(.isButton)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            streamMasthead
            listStrip
                .padding(.horizontal, 20 * settings.reading.padScale)
            Text("Nothing captured yet")
                .pocketBody()
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            List {
                Color.clear
                    .frame(height: StreamHeader.height)
                    .id(TimelineAnchor.top)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                listStrip
                    .listRowInsets(EdgeInsets(
                        top: 2 * settings.reading.padScale,
                        leading: 28 * settings.reading.padScale,
                        bottom: 0,
                        trailing: 20 * settings.reading.padScale
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(PocketCanvas())
                ForEach(notes) { note in
                    NoteRow(
                        note: note,
                        isEditing: editor.editingID == note.persistentModelID,
                        editor: editor,
                        isSelecting: isSelecting,
                        isSelected: selectedNoteIDs.contains(note.persistentModelID),
                        onTap: {
                            if isSelecting {
                                toggleSelection(note)
                            } else {
                                edit(note)
                            }
                        },
                        onLongPress: { state, point in
                            handlePress(state, at: point, noteID: note.persistentModelID)
                        },
                        onLibrary: {
                            libraryNote = note
                            libraryItems = []
                            showLibrary = true
                        },
                        onCamera: { cameraNote = note },
                        onOpenImage: { previewImageName = $0 },
                        isArrangingPhotos: editingPhotosNoteID == note.persistentModelID,
                        onDeleteImage: { removeImage($0, from: note) },
                        onFinishPhotoEdit: { editingPhotosNoteID = nil },
                        onOpenEditor: {
                            editor.end()
                            editorNoteID = note.persistentModelID
                        },
                        onOpenList: onOpenList,
                        composeFrame: composeFrame,
                        onCompose: startNewNote
                    )
                    .id(note.persistentModelID)
                    .scaleEffect(radialNoteID == note.persistentModelID ? pressedScale : 1)
                    .rotation3DEffect(
                        .degrees(tilt(for: note).x),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.45
                    )
                    .rotation3DEffect(
                        .degrees(tilt(for: note).y),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.45
                    )
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: NoteFramePreference.self,
                                value: [note.persistentModelID: geometry.frame(in: .global)]
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets(
                        top: 2 * settings.reading.padScale,
                        leading: 28 * settings.reading.padScale,
                        bottom: 2 * settings.reading.padScale,
                        trailing: 36 * settings.reading.padScale
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(PocketCanvas())
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !isSelecting {
                            ForEach(menuActions(for: note.persistentModelID).reversed(), id: \.self) { action in
                                Button(role: action == .delete ? .destructive : nil) {
                                    performNoteAction(action, on: note)
                                } label: {
                                    Label(action.title, systemImage: action.systemImage)
                                }
                                .tint(action == .delete ? Color.red : Color(white: 0.28))
                            }
                        }
                    }
                }

                Color.clear
                    .frame(minHeight: 240)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .background {
                PocketCanvas()
                    .ignoresSafeArea(edges: .top)
            }
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: TimelineScrollState.self) { geometry in
                TimelineScrollState(geometry: geometry)
            } action: { oldState, newState in
                canScrollTimeline = newState.canScroll
                updateStreamHeader(from: oldState.offsetY, to: newState.offsetY)
                if editor.editingID == nil {
                    timelineHeight = newState.containerHeight
                    restingTimelineHeight = newState.containerHeight
                }
                guard !isDraggingRail else { return }
                railProgress = newState.progress
                registerPassedNote(at: newState.progress)
            }
            .overlay(alignment: .top) {
                stickyHeader
                    .offset(y: -topInset)
                    .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .trailing) {
                if canUseRail {
                    GeometryReader { geometry in
                        let railSpan = max(geometry.size.height - 28 - PocketBarClearance.rail, 1)
                        let topCut = railSpan * (1 - 0.85 * 0.85)
                        TimeRail(
                            progress: railProgress,
                            date: railDate,
                            isDragging: isDraggingRail,
                            onDragChanged: { progress in
                                scrub(to: progress, proxy: proxy)
                            },
                            onDragEnded: {
                                isDraggingRail = false
                                railImpactToken += 1
                                persist()
                            }
                        )
                        .padding(.top, 28 + topCut)
                        .padding(.bottom, PocketBarClearance.rail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .opacity(isEditing || isSelecting ? 0 : 1)
                        .allowsHitTesting(!isEditing && !isSelecting)
                    }
                }
            }
            .overlay {
                NoteDimOverlay(noteFrame: dimNoteFrame)
                    .opacity(radialNoteID == nil ? 0 : 1)
                    .animation(.easeInOut(duration: 0.28), value: radialNoteID == nil)
                    .allowsHitTesting(false)
            }
            .overlay {
                if let radialOrigin {
                    RadialActionMenu(
                        origin: radialOrigin,
                        actions: radialActions,
                        hovered: hoveredAction,
                        container: menuBounds
                    )
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: scrollToTopToken) { _, _ in
                scrollToTop(proxy, endEditing: true)
            }
            .onChange(of: headerTopToken) { _, _ in
                scrollToTop(proxy, endEditing: true)
            }
            .onChange(of: composeTopToken) { _, _ in
                scrollToTop(proxy, endEditing: false)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: MenuBoundsPreference.self,
                            value: geometry.frame(in: .global)
                        )
                        .preference(
                            key: TopInsetPreference.self,
                            value: geometry.safeAreaInsets.top
                        )
                }
            }
            .onPreferenceChange(MenuBoundsPreference.self) { menuBounds = $0 }
            .onPreferenceChange(TopInsetPreference.self) { topInset = $0 }
            .onPreferenceChange(NoteFramePreference.self) { frames in
                noteFrames = frames
                if let radialNoteID, let frame = frames[radialNoteID] {
                    dimFrame = frame
                }
            }
            .sheet(item: $boardPickerNote) { note in
                BoardPickerSheet(note: note)
            }
        }
    }

    private func handlePress(
        _ state: UIGestureRecognizer.State,
        at point: CGPoint,
        noteID: PersistentIdentifier
    ) -> Bool {
        _ = (state, point, noteID)
        return false
    }

    private func edit(_ note: Note) {
        guard radialNoteID == nil else { return }
        let isNewest = notes.first?.persistentModelID == note.persistentModelID
        editor.begin(note.persistentModelID, scrollIntoView: !isNewest)
    }

    private var dimNoteFrame: CGRect {
        if let radialNoteID, let frame = noteFrames[radialNoteID], frame.width > 1 {
            return frame
        }
        return dimFrame
    }

    private func beginRadial(noteID: PersistentIdentifier, at point: CGPoint) {
        editor.end()
        if let frame = noteFrames[noteID] {
            dimFrame = frame
        }
        radialNoteID = noteID
        radialActions = menuActions(for: noteID)
        radialOrigin = point
        radialFinger = point
        hoveredAction = nil
        pressedScale = 0.9
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.1)) {
            pressedScale = 0.9
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            guard radialNoteID == noteID else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                pressedScale = 1.08
            }
        }
    }

    private func finishRadial() {
        let action = hoveredAction
        let noteID = radialNoteID
        cancelRadial()
        guard let action, let noteID, let note = notes.first(where: { $0.persistentModelID == noteID }) else { return }
        performNoteAction(action, on: note)
    }

    private func performNoteAction(_ action: NotePressAction, on note: Note) {
        switch action {
        case .copy:
            UIPasteboard.general.string = note.text
        case .board:
            boardPickerNote = note
        case .memo:
            removeMemo(from: note)
        case .photos:
            editingPhotosNoteID = note.persistentModelID
        case .delete:
            deleteNote(note)
        }
    }

    private func cancelRadial() {
        if let radialNoteID, let frame = noteFrames[radialNoteID] {
            dimFrame = frame
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            pressedScale = 1
        }
        radialNoteID = nil
        radialActions = []
        radialOrigin = nil
        radialFinger = nil
        hoveredAction = nil
    }

    private func action(at point: CGPoint, origin: CGPoint) -> NotePressAction? {
        let bounds = menuBounds.width > 1 ? menuBounds : UIScreen.main.bounds
        let centers = RadialFan.placement(origin: origin, actions: radialActions, in: bounds).centers
        var nearest: (action: NotePressAction, distance: CGFloat)?
        for action in radialActions {
            guard let center = centers[action] else { continue }
            let distance = hypot(point.x - center.x, point.y - center.y)
            guard distance < 36 else { continue }
            if nearest == nil || distance < nearest!.distance {
                nearest = (action, distance)
            }
        }
        return nearest?.action
    }

    private func menuActions(for noteID: PersistentIdentifier) -> [NotePressAction] {
        guard let note = notes.first(where: { $0.persistentModelID == noteID }) else {
            return [.copy, .board, .delete]
        }
        var actions: [NotePressAction] = [.copy]
        if note.audioFileName != nil {
            actions.append(.memo)
        }
        actions.append(.board)
        if !note.imageFileNames.isEmpty {
            actions.append(.photos)
        }
        actions.append(.delete)
        return actions
    }

    private func removeMemo(from note: Note) {
        voiceMemos.stopPlayback(of: note)
        VoiceMemoStore.delete(note.audioFileName)
        note.audioFileName = nil
        note.audioDuration = 0
        note.transcript = ""
        persist()
    }

    private func removeImage(_ fileName: String, from note: Note) {
        var names = note.imageFileNames
        names.removeAll { $0 == fileName }
        note.imageFileNames = names
        NoteImageStore.delete(fileName)
        persist()
        if names.isEmpty {
            editingPhotosNoteID = nil
        }
    }

    private func tilt(for note: Note) -> (x: Double, y: Double) {
        guard radialNoteID == note.persistentModelID,
              let finger = radialFinger,
              let frame = noteFrames[note.persistentModelID] else {
            return (0, 0)
        }
        let dx = (finger.x - frame.midX) / max(frame.width, 1)
        let dy = (finger.y - frame.midY) / max(frame.height, 1)
        return (
            x: Double(max(-14, min(14, -dy * 22))),
            y: Double(max(-18, min(18, dx * 28)))
        )
    }

    private func scrub(to progress: CGFloat, proxy: ScrollViewProxy) {
        guard !notes.isEmpty else { return }

        if !isDraggingRail, editor.editingID == nil {
            railImpactToken += 1
        }

        isDraggingRail = true

        let clamped = min(1, max(0, progress))
        railProgress = clamped

        let index = noteIndex(for: clamped)
        let note = notes[index]
        railDate = note.createdAt
        registerPassedNote(at: clamped)

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            if index == 0 {
                proxy.scrollTo(TimelineAnchor.top, anchor: .top)
            } else {
                proxy.scrollTo(note.persistentModelID, anchor: .top)
            }
        }
    }

    private func updateStreamHeader(from oldOffset: CGFloat, to newOffset: CGFloat) {
        if newOffset <= 0 {
            headerHidden = 0
            return
        }
        let delta = newOffset - oldOffset
        headerHidden = min(streamHeaderReach, max(0, headerHidden + delta))
    }

    private func noteIndex(for progress: CGFloat) -> Int {
        guard notes.count > 1 else { return 0 }
        return Int((min(1, max(0, progress)) * CGFloat(notes.count - 1)).rounded())
    }

    private func registerPassedNote(at progress: CGFloat) {
        let index = noteIndex(for: progress)
        guard index != hapticNoteIndex else { return }
        hapticNoteIndex = index
    }

    private func openWidgetNote() {
        guard widgetOpenToken > handledWidgetOpen, !widgetNoteKey.isEmpty else { return }
        guard let note = notes.first(where: { $0.widgetKey == widgetNoteKey }) else { return }
        handledWidgetOpen = widgetOpenToken
        editor.end()
        editorNoteID = note.persistentModelID
    }

    private func beginNote(from token: Int) {
        guard token > handledNewNoteToken else { return }
        handledNewNoteToken = token
        startNewNote()
    }

    private func startNewNote() {
        if composeTapLock { return }
        composeTapLock = true
        DispatchQueue.main.async { composeTapLock = false }
        let note = Note(text: "")
        modelContext.insert(note)
        persist()
        editor.begin(note.persistentModelID, scrollIntoView: false)
        composeTopToken += 1
    }

    private var editingNoteFrame: CGRect {
        guard let editingID = editor.editingID,
              let frame = noteFrames[editingID],
              frame.width > 1, frame.height > 1 else {
            return .zero
        }
        return frame
    }

    private func scrollToTop(_ proxy: ScrollViewProxy, endEditing: Bool) {
        if radialNoteID != nil {
            cancelRadial()
        }
        if endEditing {
            editor.end()
        }
        withAnimation(.spring(duration: 0.95, bounce: 0)) {
            proxy.scrollTo(TimelineAnchor.top, anchor: .top)
        }
    }

    private func persist() {
        try? modelContext.save()
    }

    private func discardIfEmpty(_ id: PersistentIdentifier) {
        guard voiceMemos.recordingNoteID != id else { return }
        guard libraryNote?.persistentModelID != id, cameraNote?.persistentModelID != id else { return }
        guard let note = notes.first(where: { $0.persistentModelID == id }), note.isBlank else { return }
        modelContext.delete(note)
        persist()
    }

    private func beginSelecting() {
        editor.end()
        if radialNoteID != nil {
            cancelRadial()
        }
        selectedNoteIDs = []
        isSelecting = true
    }

    private func endSelecting() {
        selectedNoteIDs = []
        isSelecting = false
    }

    private func toggleSelection(_ note: Note) {
        if selectedNoteIDs.contains(note.persistentModelID) {
            selectedNoteIDs.remove(note.persistentModelID)
        } else {
            selectedNoteIDs.insert(note.persistentModelID)
        }
    }

    private func deleteSelected() {
        let chosen = notes.filter { selectedNoteIDs.contains($0.persistentModelID) }
        guard !chosen.isEmpty else { return }
        recentDelete.remember(chosen)
        for note in chosen {
            voiceMemos.stopPlayback(of: note)
            voiceMemos.stopRecordingIfCurrent(note.persistentModelID)
            modelContext.delete(note)
        }
        persist()
        selectedNoteIDs = []
    }

    private func deleteNote(_ note: Note) {
        if editor.editingID == note.persistentModelID {
            editor.end()
        }
        recentDelete.remember(note)
        modelContext.delete(note)
        persist()
    }
}

private struct TopInsetPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MenuBoundsPreference: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct NoteFramePreference: PreferenceKey {
    static var defaultValue: [PersistentIdentifier: CGRect] = [:]

    static func reduce(
        value: inout [PersistentIdentifier: CGRect],
        nextValue: () -> [PersistentIdentifier: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct NoteDimOverlay: View {
    var noteFrame: CGRect

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global)
            let hole = CGRect(
                x: noteFrame.minX - origin.minX,
                y: noteFrame.minY - origin.minY,
                width: noteFrame.width,
                height: noteFrame.height
            )

            Color.black.opacity(0.42)
                .mask {
                    ZStack {
                        Rectangle()
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .frame(width: hole.width + 12, height: hole.height + 6)
                            .position(x: hole.midX, y: hole.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
        }
        .ignoresSafeArea()
    }
}

private struct ComposeFramePreference: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

struct ComposeHitButton: UIViewRepresentable {
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> CircleButton {
        let button = CircleButton(type: .custom)
        button.backgroundColor = .clear
        button.isAccessibilityElement = false
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: CircleButton, context: Context) {
        context.coordinator.action = action
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CircleButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 56, height: proposal.height ?? 56)
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

    final class CircleButton: UIButton {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let radius = min(bounds.width, bounds.height) / 2
            let dx = point.x - center.x
            let dy = point.y - center.y
            return dx * dx + dy * dy <= radius * radius
        }
    }
}

struct ComposeGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Circle())
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

private struct NoteRow: View {
    @Bindable var note: Note
    var isEditing: Bool
    var editor: TimelineEditor
    var isSelecting: Bool
    var isSelected: Bool
    var onTap: () -> Void
    var onLongPress: (UIGestureRecognizer.State, CGPoint) -> Bool
    var onLibrary: () -> Void
    var onCamera: () -> Void
    var onOpenImage: (String) -> Void
    var isArrangingPhotos: Bool
    var onDeleteImage: (String) -> Void
    var onFinishPhotoEdit: () -> Void
    var onOpenEditor: () -> Void
    var onOpenList: (PersistentIdentifier) -> Void = { _ in }
    var composeFrame: CGRect = .zero
    var onCompose: () -> Void = {}
    @Environment(VoiceMemoController.self) private var voice
    @Environment(PocketSettings.self) private var settings
    @State private var editorHeight: CGFloat = 22
    @State private var hitFrames = NoteHitFrames()
    @State private var transcriptOpen = false
    @State private var transcriptEditing = false
    @State private var scrollToken = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12 * settings.reading.padScale) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.28))
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: stackGap) {
            if isEditing {
                NoteTextView(note: note, editor: editor, onHeight: { height in
                    if abs(editorHeight - height) > 0.5 {
                        editorHeight = height
                    }
                }, onLibrary: onLibrary, onCamera: onCamera)
                .frame(maxWidth: .infinity, minHeight: editorHeight, alignment: .topLeading)
            } else {
                Text(note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add note..." : note.text)
                    .pocketBody()
                    .foregroundStyle(note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .topLeading)
            }

            VoiceMemoBar(note: note)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: NoteHitPreference.self,
                            value: NoteHitFrames(memo: geometry.frame(in: .global))
                        )
                    }
                }
            if note.audioFileName != nil || voice.recordingNoteID == note.persistentModelID {
                MemoTranscript(
                    note: note,
                    isOpen: $transcriptOpen,
                    isEditing: $transcriptEditing,
                    editor: editor,
                    onLibrary: onLibrary,
                    onCamera: onCamera
                )
                KeepTranscriptVisible(token: scrollToken)
                    .frame(height: 1)
            }
            NoteImageStrip(
                fileNames: note.imageFileNames,
                isArranging: isArrangingPhotos,
                onOpen: onOpenImage
            )
            }
            if namedLists.isEmpty {
                stampRow
                    .padding(.top, stackGap)
            } else {
                listNames
                    .padding(.top, noteToList)
                stampRow
                    .padding(.top, listToDate)
            }
            }
        }
        .padding(.vertical, 10 * settings.reading.padScale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if !isEditing {
                NoteTouchSurface(
                    passThrough: transcriptEditing ? hitFrames.transcriptField : .zero,
                    onTap: handleCardTap,
                    onLongPress: onLongPress
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onPreferenceChange(NoteHitPreference.self) { hitFrames = $0 }
        .onChange(of: isEditing) { _, editing in
            if editing {
                transcriptEditing = false
            }
        }
        .onChange(of: voice.recordingNoteID) { _, id in
            guard id == note.persistentModelID else { return }
            transcriptOpen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                scrollToken += 1
            }
        }
        .onChange(of: note.transcript) { old, new in
            guard old.isEmpty, !new.isEmpty else { return }
            scrollToken += 1
        }
    }

    private var editorArrow: some View {
        Text("↗")
            .font(PocketGeist.font(size: settings.reading.metaPointSize))
            .foregroundStyle(.primary)
            .frame(width: max(32, settings.reading.metaPointSize + 14), height: max(32, settings.reading.metaPointSize + 14))
            .contentShape(Rectangle())
            .accessibilityLabel("Edit note")
    }

    private var streamStamp: String {
        let time = note.createdAt.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(note.createdAt) {
            return "Today · \(time)"
        }
        if Calendar.current.isDateInYesterday(note.createdAt) {
            return "Yesterday · \(time)"
        }
        let day = note.createdAt.formatted(.dateTime.month(.abbreviated).day())
        return "\(day) · \(time)"
    }

    private var stackGap: CGFloat { 8 * settings.reading.padScale }
    private var noteToList: CGFloat { stackGap * 0.9 }
    private var listToDate: CGFloat { stackGap * 0.8 }

    private var namedLists: [Board] {
        note.lists.filter { !$0.name.isEmpty }
    }

    private var stampRow: some View {
        HStack(spacing: 2) {
            Text(streamStamp)
                .font(PocketGeist.font(size: settings.reading.metaPointSize))
                .foregroundStyle(.secondary)
            if !isSelecting {
                Group {
                    if isEditing {
                        Button(action: onOpenEditor) {
                            editorArrow
                        }
                        .buttonStyle(.plain)
                    } else {
                        editorArrow
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: NoteHitPreference.self,
                                        value: NoteHitFrames(editor: geometry.frame(in: .global))
                                    )
                                }
                            }
                    }
                }
            }
        }
    }

    private var listNames: some View {
        HStack(spacing: 0) {
            ForEach(Array(namedLists.enumerated()), id: \.element.persistentModelID) { index, board in
                if index > 0 {
                    Text(", ")
                        .font(settings.reading.metaFont())
                        .foregroundStyle(.tertiary)
                }
                Button {
                    onOpenList(board.persistentModelID)
                } label: {
                    Text(board.name)
                        .font(settings.reading.metaFont())
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(board.name)")
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: NoteHitPreference.self,
                            value: NoteHitFrames(lists: [String(describing: board.persistentModelID): geometry.frame(in: .global)])
                        )
                    }
                }
            }
        }
    }

    private func handleCardTap(_ point: CGPoint) {
        if composeFrame.width > 1, composeFrame.insetBy(dx: -4, dy: -4).contains(point) {
            onCompose()
            return
        }
        if isSelecting {
            onTap()
            return
        }
        if let listID = hitFrames.lists.first(where: { $0.value.insetBy(dx: -8, dy: -8).contains(point) })?.key,
           let board = namedLists.first(where: { String(describing: $0.persistentModelID) == listID }) {
            onOpenList(board.persistentModelID)
            return
        }
        if hitFrames.editor.insetBy(dx: -8, dy: -8).contains(point) {
            onOpenEditor()
            return
        }
        if isArrangingPhotos, hitFrames.check.insetBy(dx: -8, dy: -8).contains(point) {
            onFinishPhotoEdit()
            return
        }
        if isArrangingPhotos {
            for (fileName, frame) in hitFrames.images {
                let center = CGPoint(x: frame.maxX - 15, y: frame.minY + 15)
                if hypot(point.x - center.x, point.y - center.y) < 22 {
                    onDeleteImage(fileName)
                    return
                }
            }
        }
        if let fileName = hitFrames.images.first(where: { $0.value.insetBy(dx: -6, dy: -6).contains(point) })?.key {
            onOpenImage(fileName)
            return
        }
        if transcriptOpen, hitFrames.transcriptField.insetBy(dx: -4, dy: -4).contains(point) {
            transcriptEditing = true
            return
        }
        if hitFrames.transcriptToggle.insetBy(dx: -8, dy: -6).contains(point) {
            withAnimation(.easeOut(duration: 0.2)) {
                transcriptOpen.toggle()
            }
            return
        }
        if note.audioFileName != nil, hitFrames.memo.insetBy(dx: -6, dy: -6).contains(point) {
            voice.togglePlayback(for: note)
            return
        }
        onTap()
    }
}

private struct KeepTranscriptVisible: UIViewRepresentable {
    var token: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard context.coordinator.token != token else { return }
        context.coordinator.token = token
        DispatchQueue.main.async {
            guard let scrollView = uiView.enclosingScrollView() else { return }
            let rect = uiView.convert(uiView.bounds, to: scrollView)
            let visibleBottom = scrollView.contentOffset.y
                + scrollView.bounds.height
                - scrollView.adjustedContentInset.bottom
                - 16
            let overflow = rect.maxY - visibleBottom
            guard overflow > 8 else { return }
            let minY = -scrollView.adjustedContentInset.top
            let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            let y = min(max(scrollView.contentOffset.y + overflow, minY), maxY)
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: true)
        }
    }

    final class Coordinator {
        var token = 0
    }
}

private struct EditingOutsideTap: UIViewRepresentable {
    var editingID: PersistentIdentifier?
    var noteFrame: CGRect
    var chromeFrame: CGRect = .zero
    var onOutside: (PersistentIdentifier) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOutside: onOutside)
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.isUserInteractionEnabled = false
        view.onMoveToWindow = { [weak coordinator = context.coordinator] host in
            coordinator?.attach(from: host)
        }
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        context.coordinator.editingID = editingID
        context.coordinator.noteFrame = noteFrame
        context.coordinator.chromeFrame = chromeFrame
        context.coordinator.onOutside = onOutside
        context.coordinator.attach(from: uiView)
    }

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class HostView: UIView {
        var onMoveToWindow: ((HostView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMoveToWindow?(self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var editingID: PersistentIdentifier?
        var noteFrame: CGRect = .zero
        var chromeFrame: CGRect = .zero
        var onOutside: (PersistentIdentifier) -> Void
        private var armedID: PersistentIdentifier?
        private weak var window: UIWindow?
        private var tap: UITapGestureRecognizer?

        init(onOutside: @escaping (PersistentIdentifier) -> Void) {
            self.onOutside = onOutside
        }

        func attach(from view: UIView) {
            guard let window = view.window else { return }
            guard self.window !== window || tap == nil else { return }
            detach()
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            self.tap = tap
            self.window = window
        }

        func detach() {
            if let tap, let window {
                window.removeGestureRecognizer(tap)
            }
            tap = nil
            window = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let editingID, noteFrame.width > 1, noteFrame.height > 1 else { return false }
            if touchesEditingChrome(touch) { return false }
            let point = touch.location(in: nil)
            if chromeFrame.width > 1, chromeFrame.insetBy(dx: -8, dy: -8).contains(point) { return false }
            if noteFrame.insetBy(dx: -8, dy: -6).contains(point) { return false }
            armedID = editingID
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func touchesEditingChrome(_ touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextView || current is UIToolbar || current is UIControl || current is NoteKeyboardAccessory {
                    return true
                }
                view = current.superview
            }
            return false
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let armedID else { return }
            onOutside(armedID)
        }
    }
}

private enum StreamHeader {
    /// Gap above the controls, the control row, and the gap before the first note.
    static let height: CGFloat = 122

    static func resolvedTopInset() -> CGFloat {
        let inset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
        return inset > 1 ? inset : 59
    }
}

private enum TimelineAnchor: Hashable {
    case top
}

private struct TimelineScrollState: Equatable {
    var offsetY: CGFloat
    var progress: CGFloat
    var canScroll: Bool

    var containerHeight: CGFloat

    init(geometry: ScrollGeometry) {
        let visibleHeight = geometry.visibleRect.height
        let scrollable = geometry.contentSize.height - visibleHeight
        offsetY = geometry.visibleRect.minY
        containerHeight = geometry.containerSize.height
        canScroll = scrollable > 24
        progress = scrollable > 1 ? min(1, max(0, offsetY / scrollable)) : 0
    }
}

#Preview("Timeline") {
    let container = try! ModelContainer(
        for: Note.self, Board.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    context.insert(Note(text: "A quiet thought I wanted to keep."))
    context.insert(
        Note(
            text: "Earlier in the day, something else felt worth writing down.",
            createdAt: .now.addingTimeInterval(-3_600)
        )
    )

    return TimelineView()
        .modelContainer(container)
        .environment(RecentDelete())
        .environment(RecentFiling())
        .environment(VoiceMemoController())
}

#Preview("Time Rail") {
    let container = try! ModelContainer(
        for: Note.self, Board.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let samples = [
        "A quiet thought I wanted to keep.",
        "Something I noticed on a walk.",
        "A sentence I did not want to lose.",
        "Later, the same idea returned in a different shape."
    ]

    for index in 0..<120 {
        context.insert(
            Note(
                text: samples[index % samples.count],
                createdAt: .now.addingTimeInterval(Double(-index) * 86_400 * 6)
            )
        )
    }

    return TimelineView()
        .modelContainer(container)
        .environment(RecentDelete())
        .environment(RecentFiling())
        .environment(VoiceMemoController())
}
