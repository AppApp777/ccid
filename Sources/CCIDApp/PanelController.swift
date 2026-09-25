import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A borderless panel that takes typing without pulling focus away from the app you were in,
/// so the ID can be pasted the moment the panel closes.
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Metrics.windowSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let model: PanelModel
    private let panel = FloatingPanel()
    private var keyMonitor: Any?
    private var generation = 0

    init(model: PanelModel) {
        self.model = model
        super.init()
        let host = NSHostingView(rootView: PanelView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        panel.delegate = self
        model.onFinish = { [weak self] in self?.hide() }
    }

    var windowNumber: Int { panel.windowNumber }

    func toggle() {
        if panel.isVisible, panel.isKeyWindow { hide() } else { show() }
    }

    func show() {
        generation += 1
        model.prepareForShow()
        model.refresh()
        place()
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        startKeyMonitor()
    }

    func hide() {
        guard panel.isVisible, keyMonitor != nil else { return }
        stopKeyMonitor()
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
                self.model.didHide()
            }
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// Spotlight's spot: centred, a fifth of the way down the screen the pointer is on.
    private func place() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let size = Metrics.windowSize
        let top = area.maxY - (area.height * 0.2).rounded() + Metrics.margin
        panel.setFrame(
            NSRect(x: (area.midX - size.width / 2).rounded(), y: top - size.height, width: size.width, height: size.height),
            display: false)
    }

    // MARK: - Keys

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        // While an input method is composing (pinyin, kana…), its keys belong to it.
        if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(event.keyCode) {
        case kVK_DownArrow where flags.isEmpty:
            model.moveSelection(1)
        case kVK_UpArrow where flags.isEmpty:
            model.moveSelection(-1)
        case kVK_ANSI_N where flags == .control:
            model.moveSelection(1)
        case kVK_ANSI_P where flags == .control:
            model.moveSelection(-1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if flags == .command { model.searchTranscripts() } else { model.activateSelection() }
        case kVK_Escape:
            if !model.stepBack() { hide() }
        case kVK_ANSI_W where flags == .command:
            hide()
        default:
            return false
        }
        return true
    }
}
