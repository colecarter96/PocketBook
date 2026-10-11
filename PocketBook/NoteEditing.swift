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

struct NoteTextView: UIViewRepresentable {
    var note: Note
    var editor: TimelineEditor
    var fillsSpace = false
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
        textView.textColor = .label
        textView.tintColor = .label
        textView.font = Self.serifBody
        textView.isScrollEnabled = fillsSpace
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.delegate = context.coordinator
        textView.text = note.text
        textView.inputAccessoryView = context.coordinator.makeAccessory()
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.note = note
        context.coordinator.editor = editor
        context.coordinator.onHeight = onHeight
        context.coordinator.onLibrary = onLibrary
        context.coordinator.onCamera = onCamera
        context.coordinator.voice = voice
        context.coordinator.textView = textView
        textView.isScrollEnabled = fillsSpace
        context.coordinator.syncMic(
            isRecording: voice.recordingNoteID == note.persistentModelID,
            canRecord: note.audioFileName == nil
        )
        if textView.markedTextRange == nil, !textView.isFirstResponder, textView.text != note.text {
            textView.text = note.text
        }
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

    private static let serifBody: UIFont = {
        let base = UIFont.preferredFont(forTextStyle: .body)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }()

    final class Coordinator: NSObject, UITextViewDelegate {
        var note: Note
        var editor: TimelineEditor
        var onHeight: (CGFloat) -> Void
        var onLibrary: () -> Void = {}
        var onCamera: () -> Void = {}
        var voice: VoiceMemoController?
        weak var textView: UITextView?
        private var micItem: UIBarButtonItem?

        init(note: Note, editor: TimelineEditor, onHeight: @escaping (CGFloat) -> Void) {
            self.note = note
            self.editor = editor
            self.onHeight = onHeight
        }

        func makeAccessory() -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            let mic = UIBarButtonItem(
                image: UIImage(systemName: "mic"),
                style: .plain,
                target: self,
                action: #selector(toggleRecording)
            )
            micItem = mic
            if note.audioFileName != nil {
                mic.isHidden = true
            }
            let photo = UIBarButtonItem(image: UIImage(systemName: "photo"), menu: photoMenu())
            let gap = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
            gap.width = 8
            let save = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
            let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            bar.items = [photo, gap, mic, flex, save]
            return bar
        }

        private func photoMenu() -> UIMenu {
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
            return UIMenu(children: actions)
        }

        func syncMic(isRecording: Bool, canRecord: Bool) {
            micItem?.isHidden = !canRecord && !isRecording
            micItem?.image = UIImage(systemName: isRecording ? "stop.fill" : "mic")
            micItem?.tintColor = isRecording ? .systemRed : .label
        }

        @objc func toggleRecording() {
            guard note.audioFileName == nil || voice?.recordingNoteID == note.persistentModelID else { return }
            voice?.toggleRecording(for: note, editor: editor)
        }

        @objc func save() {
            if let textView {
                note.text = textView.text ?? ""
            }
            try? note.modelContext?.save()
            textView?.resignFirstResponder()
            editor.end()
        }

        func textViewDidChange(_ textView: UITextView) {
            note.text = textView.text ?? ""
            publishHeight(of: textView)
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

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? UIScrollView { return scrollView }
            current = view.superview
        }
        return nil
    }
}
