import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class TranslationPopupController: TranslationPopupPresenting {
    var onDismiss: (@MainActor () -> Void)?
    var onSelectFormality: (@MainActor (Formality) -> Void)?
    var onSelectAction: (@MainActor (Action) -> Void)?
    var onFetchAlternatives: (@MainActor (_ word: String, _ translation: String) async -> [String])?
    var onPickAlternative: (@MainActor (_ original: String, _ chosen: String, _ translation: String) -> Void)?
    var onFetchExplanation: (@MainActor (_ word: String, _ translation: String) async -> String)?
    var onFetchFixReason: (@MainActor (_ before: String, _ after: String, _ corrected: String) async -> String)?
    var onFetchToneNote: (@MainActor (_ previous: String, _ current: String, _ from: Formality, _ to: Formality) async -> String)?
    var onReplace: (@MainActor (_ translation: String) -> Void)?
    var onRetranslate: (@MainActor (_ source: String) -> Void)?
    var onUndo: (@MainActor () -> Void)?

    private var panel: FloatingPanel?
    /// The alternatives dropdown lives in its own child window: inside the panel it straddled the card's bottom edge,
    /// where the panel's own AppKit shadow turned any blur of its own into a hard ring.
    private var dropdownPanel: FloatingPanel?
    private var dropdownIdealSize: CGSize?
    private var dropdownAnchor: CGRect?
    private let model = PopupModel()
    private var contentIdealSize: CGSize?
    private var eventTap: CFMachPort?
    private var tapRunLoopSource: CFRunLoopSource?
    private var escMonitor: Any?
    private var outsideClickMonitor: Any?
    private var closeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var sizeApplyScheduled = false
    private var isApplyingFrame = false
    // Destination of the in-flight resize animation, nil when settled.
    private var frameTarget: CGRect?
    private var frameAnimSeq = 0
    private var resizeStartDelta: CGSize?
    private var anchorTopLeft: CGPoint = .zero
    private var anchorScreenFrame: CGRect = .zero

    private static let defaultSize = CGSize(width: 561, height: 160)

    func present(at screenPoint: CGPoint, formality: Formality) {
        tearDown()

        resetTranslationPane()
        model.clearUndo()
        model.clearToneNote()
        model.sourceText = ""
        model.direction = .unknown
        model.formality = formality
        model.action = .translate
        model.sizeDelta = .zero
        resizeStartDelta = nil
        contentIdealSize = nil

        let panel = FloatingPanel(contentRect: CGRect(origin: .zero, size: Self.defaultSize))
        panel.title = loc("Tłumaczenie", "Translation")
        let hostView = NSHostingView(rootView: PopupView(
            model: model,
            close: { [weak self] in self?.dismiss() },
            selectFormality: { [weak self] formality in self?.onSelectFormality?(formality) },
            selectAction: { [weak self] action in self?.onSelectAction?(action) },
            fetchAlternatives: { [weak self] word, translation in
                await self?.onFetchAlternatives?(word, translation) ?? []
            },
            fetchExplanation: { [weak self] word, translation in
                await self?.onFetchExplanation?(word, translation) ?? ""
            },
            fetchFixReason: { [weak self] before, after, corrected in
                await self?.onFetchFixReason?(before, after, corrected) ?? ""
            },
            fetchToneNote: { [weak self] previous, current, from, to in
                await self?.onFetchToneNote?(previous, current, from, to) ?? ""
            },
            pickAlternative: { [weak self] original, chosen, translation in
                self?.onPickAlternative?(original, chosen, translation)
            },
            replace: { [weak self] text in self?.onReplace?(text) },
            retranslate: { [weak self] source in self?.onRetranslate?(source) },
            undo: { [weak self] in
                self?.model.undo()
                self?.onUndo?()
            },
            resizeBy: { [weak self, weak panel] translation, ended in
                guard let self, let panel, self.panel === panel else { return }
                self.handleResizeDrag(translation: translation, ended: ended)
            },
            reportSize: { [weak self, weak panel] size in
                guard let self, let panel, self.panel === panel else { return }
                self.contentIdealSize = size
                self.scheduleApplyContentSize()
            },
            reportDropdownAnchor: { [weak self, weak panel] rect in
                guard let self, let panel, self.panel === panel else { return }
                self.updateDropdown(anchor: rect)
            }
        ))
        hostView.sizingOptions = []
        self.panel = panel
        panel.contentView = hostView

        hostView.layoutSubtreeIfNeeded()
        let size = contentIdealSize ?? Self.defaultSize

        let frame = screen(containing: screenPoint).visibleFrame
        let panelTopLeft = PanelPositioning.topLeft(
            forMouse: screenPoint,
            panelSize: size,
            screenFrame: frame
        )
        let margin = PopupView.shadowMargin
        anchorTopLeft = CGPoint(
            x: (panelTopLeft.x - margin).rounded(),
            y: (panelTopLeft.y + margin).rounded()
        )
        anchorScreenFrame = frame
        contentIdealSize = size
        applyContentSize()
        panel.orderFrontRegardless()
        // Key on open, not only after the first click: the panel's controls and its editable source field are useless
        // without keyboard, and forcing `appearsActive` made an unfocused panel look focused. `orderFrontRegardless`
        // stays because a background agent's plain `orderFront` can be refused; `.nonactivatingPanel` is what keeps the
        // app itself from activating, so the frontmost app stays frontmost and keeps its selection.
        panel.makeKey()

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: nil
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, self.panel === panel,
                      !self.isApplyingFrame else { return }
                self.anchorTopLeft = CGPoint(
                    x: panel.frame.minX.rounded(),
                    y: panel.frame.maxY.rounded()
                )
                self.anchorScreenFrame = panel.screen?.visibleFrame ?? self.anchorScreenFrame
            }
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, self.panel === panel else { return }
                self.releaseResources()
                self.panel = nil
                self.onDismiss?()
            }
        }

        installMonitors()
    }

    func update(direction: TranslationDirection, sourceText: String, action: Action) {
        model.direction = direction
        model.sourceText = sourceText
        model.capturedSource = sourceText
        model.action = action
        panel?.title = action == .translate
            ? "\(loc("Tłumaczenie", "Translation")) · \(direction.label)"
            : action.displayName
    }

    func append(token: String) {
        if model.phase == .capturing { model.phase = .streaming }
        model.text += token
    }

    func showError(_ message: String) {
        model.phase = .error
        model.errorMessage = message
    }

    func finish(truncated: Bool) {
        model.truncated = truncated
        model.phase = .done
    }

    func showReplies(_ drafts: [String]) {
        model.replyDrafts = drafts
        model.selectedDraftIndex = drafts.isEmpty ? nil : 0
        model.text = drafts.first ?? ""
        model.phase = .done
    }

    func restartTranslation() {
        resetTranslationPane()
    }

    private func resetTranslationPane() {
        model.closeDropdown()
        model.altsCache.removeAll()
        model.explanationCache.removeAll()
        model.fixReasonCache.removeAll()
        model.text = ""
        model.replyDrafts = []
        model.selectedDraftIndex = nil
        model.errorMessage = nil
        model.truncated = false
        model.diffHidden = false
        model.phase = .capturing
    }

    // MARK: Dropdown window

    private func updateDropdown(anchor: CGRect?) {
        guard let panel, let anchor else { return closeDropdownPanel() }
        dropdownAnchor = anchor
        let child = dropdownPanel ?? makeDropdownPanel(parent: panel)
        placeDropdown(child, parent: panel)
    }

    private func makeDropdownPanel(parent: FloatingPanel) -> FloatingPanel {
        let child = FloatingPanel(contentRect: CGRect(origin: .zero, size: CGSize(width: AlternativesDropdown.width, height: 1)))
        let host = NSHostingView(rootView: dropdownRoot())
        host.sizingOptions = []
        child.contentView = host
        host.layoutSubtreeIfNeeded()
        // A child window rides along when the parent moves and closes with it, so nothing here has to watch didMove.
        parent.addChildWindow(child, ordered: .above)
        dropdownPanel = child
        return child
    }

    private func dropdownRoot() -> some View {
        AlternativesDropdown(
            model: model,
            onPick: { [weak self] chosen in
                guard let self, let id = model.selectedWordID else { return }
                let original = self.model.segments.first { $0.id == id }?.text ?? ""
                self.model.snapshotForUndo()
                self.onPickAlternative?(original, chosen, self.model.text)
            },
            onExplain: { [weak self] in
                guard let self, let id = model.selectedWordID else { return }
                self.explain(wordID: id)
            },
            onBack: { [weak self] in self?.model.closeExplanation() }
        )
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in
            guard let self else { return }
            self.dropdownIdealSize = size
            if let child = self.dropdownPanel, let panel = self.panel { self.placeDropdown(child, parent: panel) }
        }
    }

    private func explain(wordID: Int) {
        let word = model.segments.first { $0.id == wordID }?.text ?? ""
        let translation = model.text
        model.openExplanation()
        if let cached = model.explanationCache[wordID] {
            model.explanationText = cached
            model.explanationLoading = false
            return
        }
        let token = model.explanationRequestToken
        Task { @MainActor in
            let explanation = await self.onFetchExplanation?(word, translation) ?? ""
            guard self.model.explanationRequestToken == token,
                  self.model.dropdownVisible, self.model.showingExplanation else { return }
            self.model.explanationText = explanation
            self.model.explanationLoading = false
            if !explanation.isEmpty { self.model.explanationCache[wordID] = explanation }
        }
    }

    /// The anchor arrives in SwiftUI's coordinate space — origin at the hosting view's top-left, y growing downward —
    /// so screen y is the panel's top edge minus it.
    private func placeDropdown(_ child: FloatingPanel, parent: FloatingPanel) {
        guard let anchor = dropdownAnchor else { return }
        let size = dropdownIdealSize ?? child.frame.size
        guard size.width > 0, size.height > 0 else { return }
        let desired = CGPoint(
            x: parent.frame.minX + anchor.minX,
            y: parent.frame.maxY - anchor.maxY - Self.dropdownGap
        )
        let screenFrame = child.screen?.visibleFrame ?? parent.screen?.visibleFrame ?? anchorScreenFrame
        let topLeft = PanelPositioning.clampedTopLeft(desired, panelSize: size, screenFrame: screenFrame)
        let target = CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        guard target != child.frame else { return }
        child.setFrame(target, display: true)
        child.invalidateShadow()
        child.orderFront(nil)
    }

    private func closeDropdownPanel() {
        guard let child = dropdownPanel else { return }
        panel?.removeChildWindow(child)
        child.orderOut(nil)
        child.close()
        dropdownPanel = nil
        dropdownIdealSize = nil
        dropdownAnchor = nil
    }

    private static let dropdownGap: CGFloat = 4

    private func scheduleApplyContentSize() {
        guard !sizeApplyScheduled else { return }
        sizeApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sizeApplyScheduled = false
            self.applyContentSize()
        }
    }

    private func applyContentSize() {
        guard let panel, var size = contentIdealSize else { return }
        guard size.width > 0, size.height > 0 else { return }
        size = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        let margin = PopupView.shadowMargin
        let screenFrame = (panel.screen?.visibleFrame ?? anchorScreenFrame)
            .insetBy(dx: -margin, dy: -margin)
        let topLeft = PanelPositioning.clampedTopLeft(
            anchorTopLeft, panelSize: size, screenFrame: screenFrame
        )
        let target = CGRect(
            x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height
        )
        // Compare against the in-flight destination, not the frame mid-animation, or every runloop turn restarts it.
        guard target != (frameTarget ?? panel.frame) else { return }
        // Not while the grip is being dragged (the window would lag the mouse), not before the panel is on screen,
        // and not under reduce motion.
        let animate = panel.isVisible && resizeStartDelta == nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animate else {
            frameTarget = nil
            isApplyingFrame = true
            panel.setFrame(target, display: true)
            isApplyingFrame = false
            // AppKit caches a non-opaque window's shadow and won't recompute it when the frame changes; without this
            // the shadow keeps the silhouette it had before the dropdown grew the window.
            panel.invalidateShadow()
            return
        }
        // `isApplyingFrame` has to outlive the animation: the didMove observer fires per animation step and would
        // otherwise re-anchor the panel from a frame it is still travelling through. Same guard shape as the reader's
        // chat resize — only the newest animation clears the flag.
        frameAnimSeq += 1
        let seq = frameAnimSeq
        frameTarget = target
        isApplyingFrame = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.frameAnimSeq == seq else { return }
                self.frameTarget = nil
                self.isApplyingFrame = false
                // Once, at the end — recomputing the shadow mask per animation step costs a full-window pass a frame.
                panel.invalidateShadow()
            }
        })
    }

    private func handleResizeDrag(translation: CGSize, ended: Bool) {
        let startDelta = resizeStartDelta ?? model.sizeDelta
        resizeStartDelta = ended ? nil : startDelta
        let newDelta = PanelResize.delta(startDelta: startDelta, translation: translation)
        if newDelta != model.sizeDelta { model.sizeDelta = newDelta }
    }

    func dismiss() {
        guard let panel else { return }
        releaseResources()
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
        onDismiss?()
    }

    private func tearDown() {
        guard let panel else { return }
        releaseResources()
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
    }

    private func releaseResources() {
        closeDropdownPanel()
        removeMonitors()
        for observer in [closeObserver, moveObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObserver = nil
        moveObserver = nil
        contentIdealSize = nil
    }

    private func installMonitors() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.dropdownVisible else { return }
                self.model.closeDropdown()
            }
        }

        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: translationPopupEscTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else {
            installFallbackMonitor()
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func reenableTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }

    fileprivate func handleTapKeyDown(keyCode: UInt16, modifiersRawValue: UInt) -> Bool {
        switch EscKeyHandling.action(
            keyCode: keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRawValue),
            dropdownVisible: model.dropdownVisible,
            explanationVisible: model.showingExplanation,
            fixReasonMode: model.fixReasonMode
        ) {
        case .passThrough:
            return false
        case .closeExplanation:
            model.closeExplanation()
            return true
        case .closeDropdown:
            model.closeDropdown()
            return true
        case .dismiss:
            DispatchQueue.main.async { [weak self] in self?.dismiss() }
            return true
        }
    }

    private func installFallbackMonitor() {
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch EscKeyHandling.action(
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags,
                    dropdownVisible: self.model.dropdownVisible,
                    explanationVisible: self.model.showingExplanation,
                    fixReasonMode: self.model.fixReasonMode
                ) {
                case .passThrough: break
                case .closeExplanation: self.model.closeExplanation()
                case .closeDropdown: self.model.closeDropdown()
                case .dismiss: self.dismiss()
                }
            }
        }
    }

    private func removeMonitors() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let tapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapRunLoopSource, .commonModes)
            self.tapRunLoopSource = nil
        }
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func screen(containing point: CGPoint) -> NSScreen {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }
}

private func translationPopupEscTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<TranslationPopupController>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { controller.reenableTap() }
        return Unmanaged.passUnretained(event)
    }
    guard UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == EscKeyHandling.escKeyCode,
          let nsEvent = NSEvent(cgEvent: event)
    else { return Unmanaged.passUnretained(event) }
    let keyCode = nsEvent.keyCode
    let modifiersRawValue = nsEvent.modifierFlags.rawValue
    let swallow = MainActor.assumeIsolated {
        controller.handleTapKeyDown(keyCode: keyCode, modifiersRawValue: modifiersRawValue)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
