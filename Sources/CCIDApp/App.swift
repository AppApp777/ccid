import AppKit
import CCIDCore
import ServiceManagement

@main
enum CCIDApp {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            // No Dock icon: Info.plist sets LSUIElement, so the app lives in the menu bar.
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = ProcessInfo.processInfo.environment
    private lazy var model = PanelModel(
        store: SessionStore(demo: environment["CCID_DEMO"] == "1"),
        // Tests point this at a private pasteboard so they never touch the real clipboard.
        pasteboard: environment["CCID_PASTEBOARD"].map { NSPasteboard(name: .init($0)) } ?? .general)
    private lazy var panel = PanelController(model: model)
    private let hotKey = GlobalHotKey()
    private var statusItem: NSStatusItem?
    private var shortcut = Shortcut.saved

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        hotKey.onPress = { [weak self] in self?.panel.toggle() }
        if !hotKey.register(shortcut) { shortcutUnavailable(shortcut) }
        model.refresh()
        if CommandLine.arguments.contains("--show") { panel.show() }
    }

    /// Opening the app again (Finder, Spotlight, `open -a ccid`) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Glyph.menuBarImage()
            button.toolTip = NSLocalizedString("ccid — Claude Code session IDs", comment: "")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
            || event?.modifierFlags.contains(.option) == true {
            showMenu()
        } else {
            panel.toggle()
        }
    }

    private func showMenu() {
        guard let statusItem else { return }
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let find = item(NSLocalizedString("Find a Session…", comment: ""), #selector(openPanel))
        if let equivalent = shortcut.menuEquivalent {
            find.keyEquivalent = equivalent.key
            find.keyEquivalentModifierMask = equivalent.modifiers
        }
        menu.addItem(find)
        menu.addItem(.separator())

        let shortcuts = NSMenu()
        for option in Shortcut.allCases {
            let title = option == .none ? NSLocalizedString("None", comment: "shortcut") : option.symbols
            let entry = item(title, #selector(chooseShortcut(_:)))
            entry.representedObject = option.rawValue
            entry.state = option == shortcut ? .on : .off
            shortcuts.addItem(entry)
        }
        let shortcutItem = NSMenuItem(title: NSLocalizedString("Keyboard Shortcut", comment: ""), action: nil, keyEquivalent: "")
        shortcutItem.submenu = shortcuts
        menu.addItem(shortcutItem)

        let login = item(NSLocalizedString("Open at Login", comment: ""), #selector(toggleOpenAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item(NSLocalizedString("Install Command Line Tool…", comment: ""), #selector(installCommandLineTool)))
        menu.addItem(.separator())
        menu.addItem(item(NSLocalizedString("About ccid", comment: ""), #selector(showAbout)))
        let quit = NSMenuItem(title: NSLocalizedString("Quit ccid", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openPanel() { panel.show() }

    @objc private func chooseShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = Shortcut(rawValue: raw) else { return }
        guard hotKey.register(choice) else { return shortcutUnavailable(choice) }
        shortcut = choice
        Shortcut.saved = choice
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            alert(NSLocalizedString("Couldn’t change the login item", comment: ""), error.localizedDescription)
        }
    }

    @objc private func installCommandLineTool() {
        let tool = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ccid").path
        // /usr/local/bin is on the default PATH but doesn't exist on a fresh Mac.
        let command = "sudo mkdir -p /usr/local/bin && sudo ln -sf \(ShellQuote.quote(tool)) /usr/local/bin/ccid"
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Use ccid in Terminal", comment: "")
        alert.informativeText = NSLocalizedString("Run this once in Terminal, then type ccid anywhere:", comment: "") + "\n\n" + command
        alert.addButton(withTitle: NSLocalizedString("Copy Command", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Done", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    @objc private func showAbout() {
        NSApp.activate()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: NSLocalizedString("Find any Claude Code session ID in a keystroke.", comment: "") + "\n"
                + NSLocalizedString("An independent project, not affiliated with Anthropic.", comment: ""),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private func shortcutUnavailable(_ choice: Shortcut) {
        alert(
            NSLocalizedString("Shortcut unavailable", comment: ""),
            String(format: NSLocalizedString("%@ is already used by another app. Pick another one from the ccid menu.", comment: ""), choice.symbols))
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
