import AppKit
import CCIDCore
import SwiftUI

enum Metrics {
    static let width: CGFloat = 680
    static let corner: CGFloat = 24
    static let searchHeight: CGFloat = 58
    static let sessionRowHeight: CGFloat = 52
    static let actionRowHeight: CGFloat = 42
    static let rowSpacing: CGFloat = 2
    static let listInset: CGFloat = 6
    static let footerHeight: CGFloat = 34
    static let maxVisibleRows = 8
    /// Transparent margin around the panel, so its shadow isn't cut off by the window edge.
    static let margin: CGFloat = 36

    static var windowSize: NSSize {
        let list = CGFloat(maxVisibleRows) * sessionRowHeight + CGFloat(maxVisibleRows) * rowSpacing
            + sessionRowHeight / 2 + listInset * 2
        return NSSize(width: width + margin * 2, height: searchHeight + list + footerHeight + 2 + margin * 2)
    }
}

struct PanelView: View {
    @Bindable var model: PanelModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(query: $model.query, loading: !model.hasLoaded, focus: $fieldFocused)
            if !model.rows.isEmpty {
                Hairline()
                ResultList(model: model)
                Hairline()
                Footer(model: model)
            } else if model.hasLoaded, model.sessions.isEmpty {
                Hairline()
                EmptyLibrary()
            }
        }
        .frame(width: Metrics.width)
        .panelSurface()
        .padding(Metrics.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { fieldFocused = true }
        .onChange(of: model.focusRequest) { fieldFocused = true }
    }
}

// MARK: - Search field

private struct SearchBar: View {
    @Binding var query: String
    let loading: Bool
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", text: $query, prompt: Text("Find a session by title, folder, or what you said"))
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused(focus)
            if loading {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Metrics.searchHeight)
        .animation(.easeOut(duration: 0.15), value: loading)
    }
}

// MARK: - List

private struct ResultList: View {
    let model: PanelModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Metrics.rowSpacing) {
                    ForEach(model.rows) { row in
                        RowView(row: row, model: model).id(row.id)
                    }
                }
                .padding(Metrics.listInset)
            }
            .scrollIndicators(.automatic)
            .frame(height: height)
            .onChange(of: model.selectedID) { _, id in
                guard model.selectionFollowsKeyboard, let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    /// Fits the rows exactly; when there are more than fit, the last one peeks out halfway.
    private var height: CGFloat {
        let visible = model.rows.prefix(Metrics.maxVisibleRows)
        var total = visible.reduce(0) { $0 + $1.height } + CGFloat(max(0, visible.count - 1)) * Metrics.rowSpacing
        if model.rows.count > Metrics.maxVisibleRows { total += Metrics.rowSpacing + Metrics.sessionRowHeight / 2 }
        return total + Metrics.listInset * 2
    }
}

private struct RowView: View {
    let row: PanelModel.Row
    let model: PanelModel

    var body: some View {
        let selected = row.isSelectable && row.id == model.selectedID
        content(selected: selected)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.primary.opacity(0.075))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.activate(row) }
            .onContinuousHover { phase in
                if case .active = phase, row.isSelectable { model.pointerEntered(row.id) }
            }
    }

    @ViewBuilder
    private func content(selected: Bool) -> some View {
        switch row {
        case .session(let session):
            SessionRow(
                session: session, selected: selected, copied: model.copiedID == session.id,
                hit: model.hits[session.id], phrase: phrase, now: model.now)
                .contextMenu {
                    Button("Copy ID") { model.copy(session.id, for: session) }
                    Button("Copy Resume Command") { model.copy(session.resumeCommand, for: session) }
                    Divider()
                    Button("Show Transcript in Finder") { model.reveal(session) }
                        .disabled(session.transcript == nil)
                }
        case .searchTranscripts(let text):
            SearchTranscriptsRow(text: text, selected: selected)
        case .note(let text, let busy):
            NoteRow(text: text, busy: busy)
        }
    }

    private var phrase: String? {
        if case .found(let phrase) = model.mode { return phrase }
        return nil
    }
}

private struct SessionRow: View {
    let session: Session
    let selected: Bool
    let copied: Bool
    let hit: TranscriptHit?
    let phrase: String?
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if session.isFork {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .help(Text("Forked from “\(session.parentTitle ?? "")”"))
                    }
                    if session.source == .cli {
                        Image(systemName: "terminal")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .help(Text("Ran in Terminal"))
                    }
                    Text(session.title.isEmpty ? String(localized: "Untitled") : session.displayTitle)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if session.isArchived {
                        Text("Archived")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(.primary.opacity(0.07)))
                    }
                }
                detail
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                IDLabel(shortID: session.shortID, selected: selected, copied: copied)
                Text(Formatting.relative(session.lastActive, now: now))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: Metrics.sessionRowHeight)
    }

    private var detail: Text {
        if let hit {
            let speaker: Text
            switch hit.speaker {
            case .you: speaker = Text("You")
            case .claude: speaker = Text(verbatim: "Claude")
            case .tool: speaker = Text("Tool output")
            }
            return speaker.foregroundStyle(.secondary) + Text(verbatim: "  ") + Snippet.text(hit.snippet, phrase: phrase)
        }
        let project = Text(verbatim: session.project.isEmpty ? "—" : session.project).foregroundStyle(.secondary)
        guard let said = session.lastPrompt else { return project }
        return project + Text(verbatim: "  ·  ").foregroundStyle(.tertiary) + Text(verbatim: said).foregroundStyle(.tertiary)
    }
}

private struct IDLabel: View {
    let shortID: String
    let selected: Bool
    let copied: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(verbatim: shortID)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .opacity(copied ? 0 : 1)
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text("Copied")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(.tint)
            .opacity(copied ? 1 : 0)
            .scaleEffect(copied ? 1 : 0.8, anchor: .trailing)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: copied)
    }
}

private enum Snippet {
    static func text(_ snippet: String, phrase: String?) -> Text {
        var attributed = AttributedString(snippet)
        attributed.foregroundColor = Color.secondary.opacity(0.9)
        if let phrase, !phrase.isEmpty, let range = attributed.range(of: phrase, options: .caseInsensitive) {
            attributed[range].foregroundColor = .primary
            attributed[range].font = .system(size: 12, weight: .semibold)
        }
        return Text(attributed)
    }
}

private struct SearchTranscriptsRow: View {
    let text: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            Text("Search all transcripts for “\(text)”")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            KeyCap(selected ? "↩" : "⌘↩")
        }
        .padding(.horizontal, 14)
        .frame(height: Metrics.actionRowHeight)
    }
}

private struct NoteRow: View {
    let text: String
    let busy: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18)
            Text(verbatim: text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: Metrics.actionRowHeight)
    }
}

// MARK: - Footer and small parts

private struct Footer: View {
    let model: PanelModel

    var body: some View {
        HStack(spacing: 16) {
            if let action { Hint("↩", action) }
            Hint(secondary.key, secondary.label)
            Spacer(minLength: 16)
            if let session = model.selectedSession {
                Text(verbatim: session.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: Metrics.footerHeight)
    }

    /// What Return does to the selected row.
    private var action: LocalizedStringKey? {
        switch model.selectedRow {
        case .session?: "Copy ID"
        case .searchTranscripts?: "Search transcripts"
        case .note?, nil: nil
        }
    }

    private var secondary: (key: String, label: LocalizedStringKey) {
        guard model.mode == .browse else { return ("esc", "Back") }
        if model.query.isEmpty { return ("esc", "Close") }
        if case .session? = model.selectedRow { return ("⌘↩", "Search transcripts") }
        return ("esc", "Clear")
    }
}

private struct Hint: View {
    let key: String
    let label: LocalizedStringKey

    init(_ key: String, _ label: LocalizedStringKey) {
        self.key = key
        self.label = label
    }

    var body: some View {
        HStack(spacing: 6) {
            KeyCap(key)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }
}

private struct KeyCap: View {
    let symbol: String

    init(_ symbol: String) { self.symbol = symbol }

    var body: some View {
        Text(verbatim: symbol)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 19, minHeight: 17)
            .background(RoundedRectangle(cornerRadius: 4.5, style: .continuous).fill(.primary.opacity(0.07)))
    }
}

private struct Hairline: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(height: 1 / max(scale, 1))
    }
}

private struct EmptyLibrary: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("No Claude Code sessions yet")
                .font(.system(size: 13, weight: .medium))
            Text("ccid lists sessions from the Claude app and from ~/.claude/projects.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 30)
    }
}

private extension Session {
    /// The Claude app adds " (fork)" to a fork's title; the row marks forks with an icon instead.
    var displayTitle: String {
        guard isFork, title.hasSuffix(" (fork)") else { return title }
        return String(title.dropLast(" (fork)".count))
    }
}

// MARK: - Surface

enum Appearance {
    /// `CCID_CLASSIC=1` forces the pre-Tahoe material, to check how it looks on older systems.
    static let classic = ProcessInfo.processInfo.environment["CCID_CLASSIC"] == "1"
}

extension View {
    /// Liquid Glass on macOS 26; the popover material everywhere else, including builds made with
    /// an Xcode older than 26, whose SDK doesn't have glass.
    @ViewBuilder
    func panelSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !Appearance.classic {
            self.clipShape(shape).glassEffect(.regular, in: shape)
        } else {
            materialSurface(shape)
        }
        #else
        materialSurface(shape)
        #endif
    }

    private func materialSurface(_ shape: RoundedRectangle) -> some View {
        self.background { VisualEffectBackground().clipShape(shape) }
            .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
