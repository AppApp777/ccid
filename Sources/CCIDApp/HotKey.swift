import AppKit
import Carbon.HIToolbox

/// The shortcuts on offer. A short list beats a recorder: nothing to configure, nothing to get wrong.
enum Shortcut: String, CaseIterable {
    case controlCommandI
    case controlOptionCommandI
    case shiftCommandSpace
    case optionSpace
    case none

    static let standard: Shortcut = .controlCommandI
    private static let defaultsKey = "shortcut"

    static var saved: Shortcut {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(Shortcut.init(rawValue:)) ?? standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var symbols: String {
        switch self {
        case .controlCommandI: "⌃⌘I"
        case .controlOptionCommandI: "⌃⌥⌘I"
        case .shiftCommandSpace: "⇧⌘Space"
        case .optionSpace: "⌥Space"
        case .none: ""
        }
    }

    var keyCode: UInt32? {
        switch self {
        case .controlCommandI, .controlOptionCommandI: UInt32(kVK_ANSI_I)
        case .shiftCommandSpace, .optionSpace: UInt32(kVK_Space)
        case .none: nil
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .controlCommandI: UInt32(controlKey | cmdKey)
        case .controlOptionCommandI: UInt32(controlKey | optionKey | cmdKey)
        case .shiftCommandSpace: UInt32(shiftKey | cmdKey)
        case .optionSpace: UInt32(optionKey)
        case .none: 0
        }
    }

    /// Shown next to “Find a Session…” in the menu.
    var menuEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        switch self {
        case .controlCommandI: ("i", [.control, .command])
        case .controlOptionCommandI: ("i", [.control, .option, .command])
        case .shiftCommandSpace: (" ", [.shift, .command])
        case .optionSpace: (" ", [.option])
        case .none: nil
        }
    }
}

/// A system-wide shortcut through Carbon's hot key API: no Accessibility permission needed.
@MainActor
final class GlobalHotKey {
    var onPress: (() -> Void)?
    private var handler: EventHandlerRef?
    private var reference: EventHotKeyRef?
    private static let signature: OSType = 0x6363_6964 // "ccid"

    /// Returns false when another app already owns the combination; the old one stays registered then.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        installHandlerIfNeeded()
        guard let keyCode = shortcut.keyCode else {
            unregister()
            return true
        }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, shortcut.carbonModifiers, EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr, let replacement else { return false }
        unregister()
        reference = replacement
        return true
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard identifier.signature == GlobalHotKey.signature else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { owner.onPress?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}
