//
//  PocketBookApp.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import SwiftData
import SwiftUI
import UIKit

@main
struct PocketBookApp: App {
    let container: ModelContainer

    init() {
        PocketGeist.register()
        _ = ScrollFriction.install
        UIScrollView.appearance().decelerationRate = ScrollFriction.rate
        container = PocketStore.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(PocketSettings.shared)
        }
        .modelContainer(container)
    }
}

@Observable
final class RecentDelete {
    private(set) var snapshots: [Snapshot] = []

    struct Snapshot {
        var text: String
        var createdAt: Date
        var boards: [Board]
        var audioFileName: String?
        var audioDuration: Double
        var transcript: String
        var imageFileNames: [String]
        var revisitDone: Bool
        var revisitAfter: Date?
        var widgetKey: String

        init(_ note: Note) {
            text = note.text
            createdAt = note.createdAt
            boards = note.lists
            audioFileName = note.audioFileName
            audioDuration = note.audioDuration
            transcript = note.transcript
            imageFileNames = note.imageFileNames
            revisitDone = note.revisitDone
            revisitAfter = note.revisitAfter
            widgetKey = note.widgetKey
        }
    }

    var canUndo: Bool { !snapshots.isEmpty }

    func remember(_ note: Note) {
        remember([note])
    }

    func remember(_ notes: [Note]) {
        let incomingAudio = Set(notes.compactMap(\.audioFileName))
        let incomingImages = Set(notes.flatMap(\.imageFileNames))
        for previous in snapshots {
            if let audio = previous.audioFileName, !incomingAudio.contains(audio) {
                VoiceMemoStore.delete(audio)
            }
            for name in previous.imageFileNames where !incomingImages.contains(name) {
                NoteImageStore.delete(name)
            }
        }
        snapshots = notes.map(Snapshot.init)
    }

    func undo(in context: ModelContext) {
        guard !snapshots.isEmpty else { return }
        for snapshot in snapshots {
            let note = Note(text: snapshot.text, createdAt: snapshot.createdAt)
            context.insert(note)
            note.boards = snapshot.boards
            note.audioFileName = snapshot.audioFileName
            note.audioDuration = snapshot.audioDuration
            note.transcript = snapshot.transcript
            note.imageFileNames = snapshot.imageFileNames
            note.revisitDone = snapshot.revisitDone
            note.revisitAfter = snapshot.revisitAfter
            if !snapshot.widgetKey.isEmpty {
                note.widgetKey = snapshot.widgetKey
            }
        }
        try? context.save()
        snapshots = []
    }
}

@Observable
final class RecentFiling {
    private var noteID: PersistentIdentifier?
    private var snapshot: RecentDelete.Snapshot?

    var canUndo: Bool { noteID != nil && snapshot != nil }

    func remember(_ note: Note) {
        noteID = note.persistentModelID
        snapshot = RecentDelete.Snapshot(note)
    }

    func undo(in context: ModelContext) {
        defer {
            noteID = nil
            snapshot = nil
        }
        guard let noteID, let snapshot,
              let note = context.model(for: noteID) as? Note else { return }
        note.boards = snapshot.boards
        note.revisitDone = snapshot.revisitDone
        note.revisitAfter = snapshot.revisitAfter
        try? context.save()
    }
}

enum PocketStore {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Note.self, Board.self])
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: cloud) {
            return container
        }
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}

enum PocketAppearance {
    static func scheme(for raw: String) -> ColorScheme? {
        switch raw {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    static func interfaceStyle(for colorway: PocketColorway) -> UIUserInterfaceStyle {
        colorway == .dark ? .dark : .light
    }
}

private struct AppearanceDriver: UIViewRepresentable {
    var style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        apply(to: view.window)
        if view.window == nil {
            DispatchQueue.main.async { [weak view] in
                apply(to: view?.window)
            }
        }
    }

    private func apply(to window: UIWindow?) {
        guard let window, window.overrideUserInterfaceStyle != style else { return }
        window.overrideUserInterfaceStyle = style
        window.rootViewController?.overrideUserInterfaceStyle = style
    }
}

extension PocketAppearance {
    static func apply(_ colorway: PocketColorway) {
        let style = interfaceStyle(for: colorway)
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            scene.traitOverrides.userInterfaceStyle = style
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
                window.rootViewController?.overrideUserInterfaceStyle = style
            }
        }
    }
}

enum PocketTab: Hashable {
    case timeline
    case search
    case revisit
    case boards
}

private struct PocketNavHiddenKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var pocketNavHidden: Binding<Bool> {
        get { self[PocketNavHiddenKey.self] }
        set { self[PocketNavHiddenKey.self] = newValue }
    }
}

struct RootView: View {
    @State private var recentDelete = RecentDelete()
    @State private var recentFiling = RecentFiling()
    @State private var voiceMemos = VoiceMemoController()
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: PocketTab = .timeline
    @State private var timelineTopToken = 0
    @State private var newNoteToken = 0
    @State private var widgetNoteKey = ""
    @State private var widgetOpenToken = 0
    @State private var searchQuery = ""
    @State private var recentSearches = RecentSearches.load()
    @State private var keyboardOverlap: CGFloat = 0
    @State private var hidesNav = false
    @State private var openListID: PersistentIdentifier?
    @FocusState private var searchFieldFocused: Bool
    @Environment(PocketSettings.self) private var settings

    init() {
        _ = InstantTabSwitch.disable
        _ = PocketTabRetap.install
    }

    private var reading: PocketReading { settings.reading }

    private var navDropsBehindKeyboard: Bool {
        selectedTab != .search && keyboardOverlap > 0 && !searchFieldFocused
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab.animation(nil)) {
                Tab("Timeline", systemImage: "list.bullet", value: PocketTab.timeline) {
                    TimelineView(
                        scrollToTopToken: timelineTopToken,
                        newNoteToken: newNoteToken,
                        widgetNoteKey: widgetNoteKey,
                        widgetOpenToken: widgetOpenToken,
                        onOpenList: openList
                    )
                }

                Tab("Search", systemImage: "magnifyingglass", value: PocketTab.search) {
                    SearchView(
                        query: $searchQuery,
                        isSearchFocused: $searchFieldFocused,
                        recents: recentSearches,
                        onPickRecent: pickRecent,
                        onOpenNote: dismissSearchKeyboard
                    )
                }

                Tab("Revisit", systemImage: "square.stack", value: PocketTab.revisit) {
                    RevisitView()
                }

                Tab("Lists", systemImage: "square.grid.2x2", value: PocketTab.boards) {
                    BoardsView(openListID: $openListID)
                }
            }
            .modifier(PocketTabBarChrome(hidden: tabBarHidden))
            .tint(.primary)
            .animation(nil, value: selectedTab)

            if #unavailable(iOS 26.0) {
                StreamNavBar(
                    selectedTab: selectedTab,
                    onSelect: selectTab
                )
                .padding(.bottom, navDropsBehindKeyboard ? 0 : 8)
                .offset(y: navDropsBehindKeyboard ? keyboardOverlap : 0)
                .opacity(hidesNav || searchFieldFocused ? 0 : 1)
                .allowsHitTesting(!hidesNav && !searchFieldFocused && !navDropsBehindKeyboard)
            }
        }
        .environment(\.pocketNavHidden, $hidesNav)
        .environment(recentDelete)
        .environment(recentFiling)
        .environment(voiceMemos)
        .environment(\.colorScheme, reading.colorway.scheme)
        .preferredColorScheme(reading.colorway.scheme)
        .environment(\.pocketReading, reading)
        .background(reading.colorway.canvas.ignoresSafeArea())
        .background {
            AppearanceDriver(style: PocketAppearance.interfaceStyle(for: reading.colorway))
        }
        .onAppear {
            PocketAppearance.apply(settings.colorway)
        }
        .task {
            await PocketCloudStore.prepare()
            let notes = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
            var keptAudio = Set(notes.compactMap(\.audioFileName))
            for pending in recentDelete.snapshots {
                if let audio = pending.audioFileName {
                    keptAudio.insert(audio)
                }
            }
            VoiceMemoStore.deleteAll(except: keptAudio)

            var keptImages = Set(notes.flatMap(\.imageFileNames))
            for pending in recentDelete.snapshots {
                keptImages.formUnion(pending.imageFileNames)
            }
            NoteImageStore.deleteAll(except: keptImages)
        }
        .onChange(of: searchFieldFocused) { _, focused in
            if !focused {
                commitSearch()
                keyboardOverlap = 0
            }
        }
        .onChange(of: selectedTab) { _, tab in
            guard #available(iOS 26.0, *) else { return }
            if tab == .search {
                searchFieldFocused = true
                DispatchQueue.main.async {
                    searchFieldFocused = true
                }
            } else {
                searchFieldFocused = false
            }
        }
        .onOpenURL { url in
            guard url.scheme == "pocketbook" else { return }
            searchFieldFocused = false
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTab = .timeline
            }
            if url.host == "new" {
                newNoteToken += 1
            } else if url.host == "note" {
                let key = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !key.isEmpty else { return }
                widgetNoteKey = key
                widgetOpenToken += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            WidgetNoteLibrary.publish(from: modelContext)
        }
        .task {
            WidgetNoteLibrary.publish(from: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pocketTimelineRetap)) { _ in
            guard selectedTab == .timeline else { return }
            timelineTopToken += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard selectedTab != .search, !searchFieldFocused else {
                keyboardOverlap = 0
                return
            }
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = (note.object as? UIView)?.window?.windowScene?.screen.bounds.height
                ?? UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
                    .first
                ?? frame.maxY
            let overlap = max(0, screenHeight - frame.minY)
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeInOut(duration: duration)) {
                keyboardOverlap = overlap
            }
        }
    }

    private var tabBarHidden: Bool {
        if #available(iOS 26.0, *) {
            return hidesNav || searchFieldFocused || navDropsBehindKeyboard
        }
        return true
    }

    private func openList(_ id: PersistentIdentifier) {
        openListID = id
        selectTab(.boards)
    }

    private func selectTab(_ tab: PocketTab) {
        if tab == .timeline, selectedTab == .timeline {
            timelineTopToken += 1
            return
        }
        searchFieldFocused = tab == .search
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = tab
        }
        if tab == .search {
            DispatchQueue.main.async {
                searchFieldFocused = true
            }
        }
    }

    private func commitSearch() {
        RecentSearches.remember(searchQuery, into: &recentSearches)
    }

    private func pickRecent(_ term: String) {
        searchQuery = term
        searchFieldFocused = false
        RecentSearches.remember(term, into: &recentSearches)
    }

    private func dismissSearchKeyboard() {
        searchFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

}

private struct PocketTabBarChrome: ViewModifier {
    var hidden: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .toolbarVisibility(hidden ? .hidden : .visible, for: .tabBar)
                .tabBarMinimizeBehavior(.never)
        } else {
            content.toolbar(.hidden, for: .tabBar)
        }
    }
}

extension Notification.Name {
    static let pocketTimelineRetap = Notification.Name("pocketbook.timelineRetap")
}

private enum PocketTabRetap {
    static let install: Void = {
        let cls: AnyClass = UITabBarController.self
        let original = #selector(setter: UITabBarController.delegate)
        let replacement = #selector(UITabBarController.pocket_setDelegate(_:))
        guard let method = class_getInstanceMethod(cls, original),
              let swizzled = class_getInstanceMethod(cls, replacement) else { return }
        method_exchangeImplementations(method, swizzled)
    }()
}

private final class PocketTabDelegate: NSObject, UITabBarControllerDelegate {
    static let shared = PocketTabDelegate()
    weak var forwarded: UITabBarControllerDelegate?

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        postIfTimelineRetap(tabBarController, selectingCurrent: viewController === tabBarController.selectedViewController)
        if let forwarded, forwarded.responds(to: #selector(UITabBarControllerDelegate.tabBarController(_:shouldSelect:))) {
            return forwarded.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
        }
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        postIfTimelineRetap(tabBarController, selectingCurrent: tab === tabBarController.selectedTab)
        if let forwarded, forwarded.responds(to: #selector(UITabBarControllerDelegate.tabBarController(_:shouldSelectTab:))) {
            return forwarded.tabBarController?(tabBarController, shouldSelectTab: tab) ?? true
        }
        return true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return forwarded?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let forwarded, forwarded.responds(to: aSelector) {
            return forwarded
        }
        return super.forwardingTarget(for: aSelector)
    }

    private func postIfTimelineRetap(_ tabBarController: UITabBarController, selectingCurrent: Bool) {
        guard selectingCurrent, tabBarController.selectedIndex == 0 else { return }
        NotificationCenter.default.post(name: .pocketTimelineRetap, object: nil)
    }
}

extension UITabBarController {
    @objc func pocket_setDelegate(_ delegate: UITabBarControllerDelegate?) {
        if delegate is PocketTabDelegate {
            pocket_setDelegate(delegate)
            return
        }
        PocketTabDelegate.shared.forwarded = delegate
        pocket_setDelegate(PocketTabDelegate.shared)
    }
}

private enum ScrollFriction {
    static let rate = UIScrollView.DecelerationRate(rawValue: 0.93)

    static let install: Void = {
        let cls: AnyClass = UIScrollView.self
        let original = #selector(setter: UIScrollView.decelerationRate)
        let replacement = #selector(UIScrollView.pocket_setDecelerationRate(_:))
        guard let method = class_getInstanceMethod(cls, original),
              let swizzled = class_getInstanceMethod(cls, replacement) else { return }
        method_exchangeImplementations(method, swizzled)
    }()
}

extension UIScrollView {
    @objc func pocket_setDecelerationRate(_ rate: UIScrollView.DecelerationRate) {
        pocket_setDecelerationRate(ScrollFriction.rate)
    }
}

private enum InstantTabSwitch {
    static let disable: Void = {
        let cls: AnyClass = UITabBarController.self
        exchange(
            cls,
            #selector(setter: UITabBarController.selectedViewController),
            #selector(UITabBarController.pocket_setSelectedViewController(_:))
        )
        exchange(
            cls,
            #selector(setter: UITabBarController.selectedIndex),
            #selector(UITabBarController.pocket_setSelectedIndex(_:))
        )
    }()

    private static func exchange(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let method = class_getInstanceMethod(cls, original),
              let swizzled = class_getInstanceMethod(cls, replacement) else { return }
        method_exchangeImplementations(method, swizzled)
    }
}

extension UITabBarController {
    @objc func pocket_setSelectedViewController(_ viewController: UIViewController?) {
        UIView.performWithoutAnimation {
            pocket_setSelectedViewController(viewController)
        }
    }

    @objc func pocket_setSelectedIndex(_ index: Int) {
        UIView.performWithoutAnimation {
            pocket_setSelectedIndex(index)
        }
    }
}

