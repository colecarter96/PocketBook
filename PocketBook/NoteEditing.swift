//
//  NoteEditing.swift
//  PocketBook
//

import SwiftData
import SwiftUI
import UIKit

@MainActor
@Observable
final class TimelineEditor {
    var editingID: PersistentIdentifier?

    @ObservationIgnored private var textViews: [PersistentIdentifier: UITextView] = [:]
    @ObservationIgnored private var activationToken = 0
    @ObservationIgnored private var wantsScroll = false
    @ObservationIgnored private var didPlace = false
    @ObservationIgnored private var reclaimCount = 0
    @ObservationIgnored private var placeObserver: NSObjectProtocol?

    func begin(_ id: PersistentIdentifier, scrollIntoView: Bool) {
        reclaimCount = 0
        if editingID != id {
            let previous = editingID
            editingID = id
            if let previous, let old = textViews[previous] {
                old.resignFirstResponder()
            }
        }
        wantsScroll = scrollIntoView
        didPlace = false
        scheduleActivation(for: id)
    }

    func insertTranscript(_ transcript: String, into note: Note) {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        note.transcript = cleaned
        try? note.modelContext?.save()
    }

    func reclaim(_ id: PersistentIdentifier) {
        guard editingID == id else { return }
        reclaimCount += 1
        guard reclaimCount <= 4 else {
            end()
            return
        }
        scheduleActivation(for: id)
    }

    func end() {
        activationToken += 1
        removePlaceObserver()
        let previous = editingID
        editingID = nil
        wantsScroll = false
        if let previous, let view = textViews[previous] {
            view.resignFirstResponder()
        }
    }

    func register(_ id: PersistentIdentifier, view: UITextView) {
        guard textViews[id] !== view else { return }
        textViews[id] = view
        guard editingID == id else { return }
        scheduleActivation(for: id)
    }

    func unregister(_ id: PersistentIdentifier, view: UITextView) {
        guard textViews[id] === view else { return }
        textViews[id] = nil
    }

    private func scheduleActivation(for id: PersistentIdentifier) {
        activationToken += 1
        let token = activationToken
        for delay in [0, 80, 200, 400, 800] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self] in
                guard let self, token == self.activationToken, self.editingID == id else { return }
                guard let view = self.textViews[id], !view.isFirstResponder else { return }
                self.activate(view)
            }
        }
    }

    private func activate(_ view: UITextView) {
        view.isEditable = true
        view.isSelectable = true
        view.isUserInteractionEnabled = true
        guard view.window != nil else { return }
        view.enclosingScrollView()?.keyboardDismissMode = .none
        let end = view.endOfDocument
        view.selectedTextRange = view.textRange(from: end, to: end)
        let shouldPlace = wantsScroll && !didPlace
        if shouldPlace {
            armKeyboardScroll(for: view)
        }
        guard view.becomeFirstResponder() else {
            if shouldPlace {
                removePlaceObserver()
            }
            return
        }
        guard shouldPlace else { return }
        didPlace = true
        let token = activationToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak view] in
            guard let self, let view, token == self.activationToken, view.isFirstResponder else { return }
            guard self.placeObserver != nil else { return }
            self.removePlaceObserver()
            self.scrollIntoQuarter(view, notification: nil)
        }
    }

    private func armKeyboardScroll(for view: UITextView) {
        removePlaceObserver()
        let token = activationToken
        placeObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak view] notification in
            MainActor.assumeIsolated {
                guard let self, let view else { return }
                guard token == self.activationToken, view.isFirstResponder else { return }
                guard self.keyboardIsShowing(notification, around: view) else { return }
                self.removePlaceObserver()
                self.scrollIntoQuarter(view, notification: notification)
            }
        }
    }

    private func keyboardIsShowing(_ notification: Notification, around view: UIView) -> Bool {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return true
        }
        let height = view.window?.bounds.height ?? frame.maxY
        return frame.minY < height - 20
    }

    private func removePlaceObserver() {
        if let placeObserver {
            NotificationCenter.default.removeObserver(placeObserver)
        }
        placeObserver = nil
    }

    private func scrollIntoQuarter(_ view: UIView, notification: Notification?) {
        guard let scrollView = view.enclosingScrollView() else { return }
        let rect = view.convert(view.bounds, to: scrollView)
        let target = rect.origin.y - (scrollView.bounds.height * 0.25)
        let inset = scrollView.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        let y = min(max(target, minY), maxY)
        guard abs(y - scrollView.contentOffset.y) > 8 else { return }

        let duration = notification?.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.22
        let curveRaw = notification?.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
            ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16).union(.beginFromCurrentState)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: y)
        }
    }
}

final class NoteKeyboardAccessory: UIView {
    var onLibrary: () -> Void = {}
    var onCamera: () -> Void = {}
    var onMic: () -> Void = {}
    var onSave: () -> Void = {}

    private let photo = UIButton(type: .system)
    private let mic = UIButton(type: .system)
    private let check = CheckPillButton()
    private let glass: UIVisualEffectView?
    private let fallback = UIView()

    override init(frame: CGRect) {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            glass = UIVisualEffectView(effect: effect)
        } else {
            glass = nil
        }
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 62))
        autoresizingMask = .flexibleWidth
        backgroundColor = .clear

        fallback.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.92)
        fallback.isUserInteractionEnabled = false
        if let glass {
            glass.isUserInteractionEnabled = false
            glass.clipsToBounds = true
            addSubview(glass)
        } else {
            addSubview(fallback)
        }

        photo.tintColor = .label
        photo.setImage(UIImage(systemName: "photo"), for: .normal)
        photo.showsMenuAsPrimaryAction = true
        photo.accessibilityLabel = "Photo"
        addSubview(photo)

        mic.tintColor = .label
        mic.setImage(UIImage(systemName: "mic"), for: .normal)
        mic.accessibilityLabel = "Add Memo"
        mic.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        addSubview(mic)

        check.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        addSubview(check)
        refreshPhotoMenu()
        syncMic(isRecording: false, canRecord: true)
        setDiscarding(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 62)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let width = window?.bounds.width, width > 1 {
            frame.size.width = width
        }
        frame.size.height = 62
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bar = bounds.insetBy(dx: 12, dy: 8)
        let plate = glass ?? fallback
        plate.frame = bar
        plate.layer.cornerRadius = bar.height / 2

        let side = bar.height
        photo.frame = CGRect(x: bar.minX + 6, y: bar.minY, width: side, height: side)
        mic.frame = CGRect(x: photo.frame.maxX, y: bar.minY, width: side, height: side)
        let pill = CGRect(x: bar.maxX - 6 - 68, y: bar.midY - 17, width: 68, height: 34)
        check.frame = pill
    }

    func setDiscarding(_ discarding: Bool) {
        check.setDiscarding(discarding)
    }

    func syncMic(isRecording: Bool, canRecord: Bool) {
        mic.isHidden = !canRecord && !isRecording
        if isRecording {
            mic.menu = nil
            mic.showsMenuAsPrimaryAction = false
            mic.setImage(UIImage(systemName: "stop.fill"), for: .normal)
            mic.tintColor = .systemRed
            mic.accessibilityLabel = "Stop Recording"
        } else {
            mic.tintColor = .label
            mic.setImage(UIImage(systemName: "mic"), for: .normal)
            mic.accessibilityLabel = "Add Memo"
            mic.menu = UIMenu(children: [
                UIAction(title: "Add Memo", image: UIImage(systemName: "mic")) { [weak self] _ in
                    self?.onMic()
                }
            ])
            mic.showsMenuAsPrimaryAction = true
        }
    }

    private func refreshPhotoMenu() {
        var actions = [
            UIAction(title: "Photo Library", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in
                self?.onLibrary()
            }
        ]
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            actions.append(
                UIAction(title: "Take Photo", image: UIImage(systemName: "camera")) { [weak self] _ in
                    self?.onCamera()
                }
            )
        }
        photo.menu = UIMenu(children: actions)
    }

    @objc private func micTapped() {
        onMic()
    }

    @objc private func saveTapped() {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.prepare()
        haptic.impactOccurred()
        onSave()
    }
}

private final class CheckPillButton: UIControl {
    private let mark = UIImageView()
    private let glass: UIVisualEffectView?

    override init(frame: CGRect) {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.tintColor = .systemBlue
            glass = UIVisualEffectView(effect: effect)
        } else {
            glass = nil
        }
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Save"

        if let glass {
            glass.isUserInteractionEnabled = false
            glass.clipsToBounds = true
            addSubview(glass)
        } else {
            backgroundColor = .systemBlue
            clipsToBounds = true
        }

        mark.contentMode = .center
        mark.isUserInteractionEnabled = false
        addSubview(mark)
        setDiscarding(false)
    }

    func setDiscarding(_ discarding: Bool) {
        let symbol = discarding ? "xmark" : "checkmark"
        mark.image = UIImage(systemName: symbol)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .bold))
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        accessibilityLabel = discarding ? "Discard" : "Save"
        let tint: UIColor = discarding ? .systemRed : .systemBlue
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.tintColor = tint
            glass?.effect = effect
        } else {
            backgroundColor = tint
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass?.frame = bounds
        glass?.layer.cornerRadius = bounds.height / 2
        if glass == nil {
            layer.cornerRadius = bounds.height / 2
        }
        mark.frame = bounds
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -12, dy: -10).contains(point)
    }
}

struct NoteTextView: View {
    @Environment(PocketSettings.self) private var settings
    var note: Note
    var editor: TimelineEditor
    var fillsSpace = false
    var onHeight: (CGFloat) -> Void
    var onLibrary: () -> Void
    var onCamera: () -> Void

    var body: some View {
        NoteTextRepresentable(
            note: note,
            editor: editor,
            fillsSpace: fillsSpace,
            font: settings.reading.bodyUIFont,
            ink: settings.colorway.ink,
            onHeight: onHeight,
            onLibrary: onLibrary,
            onCamera: onCamera
        )
    }
}

private struct NoteTextRepresentable: UIViewRepresentable {
    var note: Note
    var editor: TimelineEditor
    var fillsSpace = false
    var font: UIFont
    var ink: UIColor
    var onHeight: (CGFloat) -> Void
    var onLibrary: () -> Void
    var onCamera: () -> Void
    @Environment(VoiceMemoController.self) private var voice

    func makeCoordinator() -> Coordinator {
        Coordinator(note: note, editor: editor, onHeight: onHeight)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.textColor = ink
        textView.tintColor = ink
        textView.font = font
        textView.isScrollEnabled = fillsSpace
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.delegate = context.coordinator
        textView.text = note.text
        textView.inputAccessoryView = context.coordinator.accessory
        context.coordinator.installPlaceholder(on: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.note = note
        context.coordinator.editor = editor
        context.coordinator.onHeight = onHeight
        context.coordinator.onLibrary = onLibrary
        context.coordinator.onCamera = onCamera
        context.coordinator.voice = voice
        context.coordinator.allowsDiscard = !fillsSpace
        context.coordinator.textView = textView
        textView.isScrollEnabled = fillsSpace
        context.coordinator.accessory.onLibrary = onLibrary
        context.coordinator.accessory.onCamera = onCamera
        context.coordinator.accessory.onMic = { [weak coordinator = context.coordinator] in
            coordinator?.toggleRecording()
        }
        context.coordinator.accessory.onSave = { [weak coordinator = context.coordinator] in
            coordinator?.save()
        }
        context.coordinator.syncMic(
            isRecording: voice.recordingNoteID == note.persistentModelID,
            canRecord: note.audioFileName == nil
        )
        context.coordinator.syncDiscard()
        if textView.markedTextRange == nil, !textView.isFirstResponder, textView.text != note.text {
            textView.text = note.text
        }
        textView.font = font
        textView.textColor = ink
        textView.tintColor = ink
        context.coordinator.syncPlaceholder(on: textView)
        editor.register(note.persistentModelID, view: textView)
        context.coordinator.publishHeight(of: textView)
    }

    static func dismantleUIView(_ textView: UITextView, coordinator: Coordinator) {
        coordinator.editor.unregister(coordinator.note.persistentModelID, view: textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 1 else { return nil }
        if fillsSpace, let proposedHeight = proposal.height, proposedHeight > 1 {
            return CGSize(width: width, height: proposedHeight)
        }
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: max(22, ceil(height)))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var note: Note
        var editor: TimelineEditor
        var onHeight: (CGFloat) -> Void
        var onLibrary: () -> Void = {}
        var onCamera: () -> Void = {}
        var voice: VoiceMemoController?
        var allowsDiscard = false
        weak var textView: UITextView?
        let accessory = NoteKeyboardAccessory()
        private static let placeholderTag = 91

        init(note: Note, editor: TimelineEditor, onHeight: @escaping (CGFloat) -> Void) {
            self.note = note
            self.editor = editor
            self.onHeight = onHeight
        }

        func syncMic(isRecording: Bool, canRecord: Bool) {
            accessory.syncMic(isRecording: isRecording, canRecord: canRecord)
        }

        func syncDiscard() {
            let text = textView?.text ?? note.text
            let recording = voice?.recordingNoteID == note.persistentModelID
            let blank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && note.audioFileName == nil
                && note.imageFileNames.isEmpty
                && !recording
            accessory.setDiscarding(allowsDiscard && blank)
        }

        @objc func toggleRecording() {
            guard note.audioFileName == nil || voice?.recordingNoteID == note.persistentModelID else { return }
            voice?.toggleRecording(for: note, editor: editor)
            syncDiscard()
        }

        @objc func save() {
            if let textView {
                note.text = textView.text ?? ""
            }
            try? note.modelContext?.save()
            textView?.resignFirstResponder()
            editor.end()
        }

        func installPlaceholder(on textView: UITextView) {
            let label = UILabel()
            label.tag = Self.placeholderTag
            label.text = "Add note..."
            label.textColor = textView.textColor?.withAlphaComponent(0.45)
            label.font = textView.font
            label.isUserInteractionEnabled = false
            textView.addSubview(label)
            syncPlaceholder(on: textView)
        }

        func syncPlaceholder(on textView: UITextView) {
            guard let label = textView.viewWithTag(Self.placeholderTag) as? UILabel else { return }
            label.font = textView.font
            label.textColor = textView.textColor?.withAlphaComponent(0.45)
            let line = ceil(textView.font?.lineHeight ?? 22)
            label.frame = CGRect(x: 0, y: 0, width: max(textView.bounds.width, 1), height: line)
            label.isHidden = !(textView.text ?? "").isEmpty
        }

        func textViewDidChange(_ textView: UITextView) {
            note.text = textView.text ?? ""
            syncPlaceholder(on: textView)
            publishHeight(of: textView)
            syncDiscard()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if editor.editingID != note.persistentModelID {
                voice?.stopRecordingIfCurrent(note.persistentModelID)
            }
            try? note.modelContext?.save()
            editor.reclaim(note.persistentModelID)
        }

        func publishHeight(of textView: UITextView) {
            let width = textView.bounds.width
            guard width > 1 else { return }
            let height = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            let next = max(22, ceil(height))
            DispatchQueue.main.async {
                self.onHeight(next)
            }
        }
    }
}

struct NoteTouchSurface: UIViewRepresentable {
    var passThrough: CGRect = .zero
    var onTap: (CGPoint) -> Void
    var onLongPress: (UIGestureRecognizer.State, CGPoint) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.passThrough = passThrough

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePress(_:)))
        press.minimumPressDuration = 0.35
        press.allowableMovement = 22
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delaysTouchesEnded = false
        press.delegate = context.coordinator
        view.addGestureRecognizer(press)
        context.coordinator.press = press
        return view
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.passThrough = passThrough
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
    }

    final class TouchView: UIView {
        var passThrough: CGRect = .zero

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard passThrough.width > 1, passThrough.height > 1 else {
                return super.hitTest(point, with: event)
            }
            let global = convert(point, to: nil)
            if passThrough.insetBy(dx: -8, dy: -8).contains(global) {
                return nil
            }
            return super.hitTest(point, with: event)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TouchView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (CGPoint) -> Void
        var onLongPress: (UIGestureRecognizer.State, CGPoint) -> Bool
        weak var press: UILongPressGestureRecognizer?
        private var pressOwnsTouch = false

        init(
            onTap: @escaping (CGPoint) -> Void,
            onLongPress: @escaping (UIGestureRecognizer.State, CGPoint) -> Bool
        ) {
            self.onTap = onTap
            self.onLongPress = onLongPress
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            other is UIPanGestureRecognizer
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, !pressOwnsTouch else { return }
            onTap(recognizer.location(in: nil))
        }

        @objc func handlePress(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: nil)
            switch recognizer.state {
            case .began:
                let accepted = onLongPress(.began, point)
                pressOwnsTouch = accepted
                recognizer.view?.enclosingScrollView()?.isScrollEnabled = !accepted
            case .changed:
                guard pressOwnsTouch else { return }
                _ = onLongPress(.changed, point)
            case .ended, .cancelled:
                recognizer.view?.enclosingScrollView()?.isScrollEnabled = true
                if pressOwnsTouch {
                    _ = onLongPress(recognizer.state, point)
                }
                pressOwnsTouch = false
            case .failed:
                recognizer.view?.enclosingScrollView()?.isScrollEnabled = true
                pressOwnsTouch = false
            default:
                break
            }
        }
    }
}

extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? UIScrollView { return scrollView }
            current = view.superview
        }
        return nil
    }
}
