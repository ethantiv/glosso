import AppKit
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
        guard target != panel.frame else { return }
        isApplyingFrame = true
        panel.setFrame(target, display: true)
        isApplyingFrame = false
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
