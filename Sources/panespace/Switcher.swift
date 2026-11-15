import AppKit
import PanespaceCore

/// The window switcher (leader + Space or K): a search box over every window, command-palette style.
/// Type to filter (fuzzy, app names count most), ↑/↓ or ⌃N/⌃P to pick, Return to jump there, Esc to leave.
final class SwitcherPanel: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var panel: KeyPanel?
    private var scrim: NSWindow?
    private let field = NSTextField()
    private let table = NSTableView()
    private let section = NSTextField(labelWithString: "")
    private let empty = NSTextField(labelWithString: "No windows match")
    private let scroll = NSScrollView()
    private var scrollHeight: NSLayoutConstraint?
    private var all: [SwitcherEntry] = []
    private var shown: [SwitcherEntry] = []
    private var icons: [pid_t: NSImage] = [:]
    private var onPick: ((WindowID?) -> Void)?
    private var screenFrame = NSRect.zero
    private var anchorTop: CGFloat = 0
    var isOpen: Bool { panel?.isVisible ?? false }

    private static let width: CGFloat = 680
    private static let rowHeight: CGFloat = 50
    private static let maxRows = 8
    private static let headerHeight: CGFloat = 62
    private static let sectionHeight: CGFloat = 30
    private static let listBottom: CGFloat = 8
    private static let footerHeight: CGFloat = 46
    private static let radius: CGFloat = 18

    /// Opens on `screenFrame` (Cocoa coordinates). `pick` gets the chosen window, or nil when dismissed.
    func show(_ entries: [SwitcherEntry], on screenFrame: NSRect, pick: @escaping (WindowID?) -> Void) {
        if isOpen { return close(nil) }  // the same key again closes it
        all = entries
        shown = entries
        onPick = pick
        icons = [:]
        self.screenFrame = screenFrame
        anchorTop = screenFrame.minY + screenFrame.height * 0.72
        let p = panel ?? build()
        panel = p
        field.stringValue = ""
        reload()
        showScrim(on: screenFrame)
        NSApp.activate(ignoringOtherApps: true)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(field)
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.14
            c.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
            scrim?.animator().alphaValue = 1
        }
    }

    /// A soft dim over the whole display behind the panel, so the palette reads as the one thing in front.
    /// Click-through: a click anywhere still lands in the app under it, which dismisses the switcher.
    private func showScrim(on visible: NSRect) {
        let full = NSScreen.screens.first { $0.visibleFrame == visible }?.frame ?? visible
        let w = scrim ?? {
            let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = NSColor.black.withAlphaComponent(0.28)
            w.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue - 1)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            scrim = w
            return w
        }()
        w.setFrame(full, display: false)
        w.alphaValue = 0
        w.orderFrontRegardless()
    }

    private func build() -> KeyPanel {
        let p = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                         backing: .buffered, defer: false)
        p.level = .modalPanel
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.delegate = self
        p.onKey = { [weak self] e in self?.key(e) ?? false }

        let bg = PanelBackground(radius: Self.radius)
        p.contentView = bg
        let tint = Tint()
        let rim = Rim(radius: Self.radius)

        let glass = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        glass.symbolConfiguration = .init(pointSize: 17, weight: .regular)
        glass.contentTintColor = .secondaryLabelColor
        field.placeholderAttributedString = NSAttributedString(string: "Search windows…", attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
        field.font = .systemFont(ofSize: 17, weight: .regular)
        field.textColor = .labelColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.delegate = self
        field.cell?.isScrollable = true

        section.font = .systemFont(ofSize: 12, weight: .medium)
        section.textColor = .secondaryLabelColor

        let col = NSTableColumn(identifier: .init("w"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clickedRow)

        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        empty.textColor = .tertiaryLabelColor
        empty.font = .systemFont(ofSize: 13.5)
        empty.alignment = .center

        let line = Hairline()
        let footer = Self.footer()

        for v in [tint, glass, field, section, scroll, empty, line, footer, rim] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            bg.addSubview(v)
        }
        let h = Self.headerHeight
        scrollHeight = scroll.heightAnchor.constraint(equalToConstant: Self.rowHeight)
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: bg.topAnchor),
            tint.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            rim.topAnchor.constraint(equalTo: bg.topAnchor),
            rim.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
            rim.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            rim.trailingAnchor.constraint(equalTo: bg.trailingAnchor),

            glass.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 22),
            glass.centerYAnchor.constraint(equalTo: bg.topAnchor, constant: h / 2 + 2),
            field.leadingAnchor.constraint(equalTo: glass.trailingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -22),
            field.centerYAnchor.constraint(equalTo: glass.centerYAnchor),

            section.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 22),
            section.trailingAnchor.constraint(lessThanOrEqualTo: bg.trailingAnchor, constant: -22),
            section.bottomAnchor.constraint(equalTo: bg.topAnchor, constant: h + Self.sectionHeight - 8),

            scroll.topAnchor.constraint(equalTo: bg.topAnchor, constant: h + Self.sectionHeight),
            scroll.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -8),
            scrollHeight!,
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),

            line.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: Self.listBottom),
            line.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            footer.topAnchor.constraint(equalTo: line.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: bg.trailingAnchor, constant: -18),
            footer.heightAnchor.constraint(equalToConstant: Self.footerHeight),
        ])
        return p
    }

    /// ↑ ↓ Navigate   Enter Select   Esc Close
    private static func footer() -> NSStackView {
        func hint(_ keys: [String], _ label: String) -> NSStackView {
            let caps = keys.map { Keycap($0) as NSView }
            let text = NSTextField(labelWithString: label)
            text.font = .systemFont(ofSize: 13, weight: .regular)
            text.textColor = .secondaryLabelColor
            let s = NSStackView(views: caps + [text])
            s.orientation = .horizontal
            s.spacing = 6
            s.setCustomSpacing(9, after: caps.last!)
            return s
        }
        let s = NSStackView(views: [hint(["↑", "↓"], "Navigate"), hint(["Enter"], "Select"), hint(["Esc"], "Close")])
        s.orientation = .horizontal
        s.alignment = .centerY
        s.spacing = 22
        return s
    }

    private func reload() {
        shown = Fuzzy.filter(field.stringValue, all)
        let rows = max(1, min(Self.maxRows, shown.count))
        scrollHeight?.constant = CGFloat(rows) * Self.rowHeight
        table.reloadData()
        section.stringValue = field.stringValue.isEmpty ? "Windows" : "Results"
        empty.stringValue = field.stringValue.isEmpty ? "No windows" : "No windows match"
        empty.isHidden = !shown.isEmpty
        if !shown.isEmpty { select(0) }
        layoutPanel()
    }

    private func layoutPanel() {
        guard let p = panel else { return }
        let rows = max(1, min(Self.maxRows, shown.count))
        let height = Self.headerHeight + Self.sectionHeight + CGFloat(rows) * Self.rowHeight + Self.listBottom
            + 1 + Self.footerHeight
        p.setFrame(NSRect(x: screenFrame.midX - Self.width / 2, y: anchorTop - height,
                          width: Self.width, height: height), display: true)
    }

    private func select(_ row: Int) {
        guard !shown.isEmpty else { return }
        let r = (row + shown.count) % shown.count
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
    }

    /// Navigation keys, wherever the focus is in the panel. True = handled.
    private func key(_ e: NSEvent) -> Bool {
        let ctrl = e.modifierFlags.contains(.control)
        switch (e.keyCode, ctrl, e.charactersIgnoringModifiers) {
        case (125, _, _), (_, true, "n"), (_, true, "j"): select(table.selectedRow + 1)
        case (126, _, _), (_, true, "p"), (_, true, "k"): select(table.selectedRow - 1)
        case (36, _, _), (76, _, _): close(shown.indices.contains(table.selectedRow) ? shown[table.selectedRow].id : nil)
        case (53, _, _): close(nil)
        default: return false
        }
        return true
    }

    @objc private func clickedRow() {
        if shown.indices.contains(table.clickedRow) { close(shown[table.clickedRow].id) }
    }

    private func close(_ id: WindowID?) {
        guard let p = panel, p.isVisible else { return }
        let pick = onPick
        onPick = nil
        p.orderOut(nil)
        scrim?.orderOut(nil)
        all = []
        shown = []
        table.reloadData()
        icons = [:]
        pick?(id)
    }

    // Clicking elsewhere dismisses it.
    func windowDidResignKey(_ notification: Notification) { close(nil) }

    func controlTextDidChange(_ obj: Notification) { reload() }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SwitcherRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard shown.indices.contains(row) else { return nil }  // asked after close() emptied the list
        let e = shown[row]
        let cell = (tableView.makeView(withIdentifier: .init("row"), owner: nil) as? SwitcherRow) ?? SwitcherRow()
        cell.identifier = .init("row")
        let icon = icons[e.pid] ?? NSRunningApplication(processIdentifier: e.pid)?.icon
        icons[e.pid] = icon
        let redundantApp = e.title.compare(e.app, options: .caseInsensitive) == .orderedSame
        let badge = e.isFullScreen ? "Full Screen" : e.isAway ? "Minimized" : e.workspace ?? "Scratchpad"
        cell.set(icon: icon, title: e.title.isEmpty ? e.app : e.title,
                 detail: e.title.isEmpty || redundantApp ? "" : e.app,
                 badge: badge, floating: e.isFloating, query: field.stringValue)
        return cell
    }
}

private extension NSColor {
    /// One color per appearance, resolved whenever it's drawn.
    static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    static let paletteBackground = adaptive(dark: NSColor(srgbRed: 0.055, green: 0.055, blue: 0.06, alpha: 0.86),
                                            light: NSColor(srgbRed: 0.985, green: 0.985, blue: 0.99, alpha: 0.86))
    static let paletteRim = adaptive(dark: NSColor.white.withAlphaComponent(0.10), light: NSColor.black.withAlphaComponent(0.10))
    static let paletteLine = adaptive(dark: NSColor.white.withAlphaComponent(0.07), light: NSColor.black.withAlphaComponent(0.07))
    static let paletteSelection = adaptive(dark: NSColor.white.withAlphaComponent(0.075), light: NSColor.black.withAlphaComponent(0.055))
    static let paletteChip = adaptive(dark: NSColor.white.withAlphaComponent(0.08), light: NSColor.black.withAlphaComponent(0.06))
}

/// The rounded blur behind the switcher.
private final class PanelBackground: NSVisualEffectView {
    init(radius: CGFloat) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// A near-opaque neutral tint over the blur: the wallpaper's color no longer decides whether text is readable.
private final class Tint: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.paletteBackground.setFill()
        dirtyRect.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The hairline around the panel's edge, drawn inside its rounded corners.
private final class Rim: NSView {
    private let radius: CGFloat
    init(radius: CGFloat) {
        self.radius = radius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        path.lineWidth = 1
        NSColor.paletteRim.setStroke()
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class Hairline: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.paletteLine.setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A rounded key: footer hints (↑, Enter, Esc) and the workspace a window lives on.
private final class Keycap: NSView {
    private let label: NSTextField

    init(_ text: String, size: CGFloat = 12, minWidth: CGFloat = 24, height: CGFloat = 24) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: size, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { false }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.paletteChip.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A borderless panel that can take the keyboard and hands navigation keys to the switcher first.
final class KeyPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override func sendEvent(_ e: NSEvent) {
        if e.type == .keyDown, onKey?(e) == true { return }
        super.sendEvent(e)
    }
}

/// Inset, rounded, neutral highlight instead of the raw full-width (accent-blue) table selection.
private final class SwitcherRowView: NSTableRowView {
    // Never the emphasized (white-text) style: the highlight is light, so text keeps its own colors.
    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.paletteSelection.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 10, yRadius: 10).fill()
    }
}

private final class SwitcherRow: NSTableCellView {
    private let icon = NSImageView()
    private let text = NSStackView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let badge = Keycap("", size: 11.5, minWidth: 26, height: 24)

    init() {
        super.init(frame: .zero)
        detail.font = .systemFont(ofSize: 12.5)
        detail.textColor = .secondaryLabelColor

        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.addArrangedSubview(title)
        text.addArrangedSubview(detail)
        text.distribution = .fill

        for v in [icon, text, badge] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        for label in [title, detail] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.usesSingleLineMode = true
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
        }
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            text.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -14),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(icon img: NSImage?, title t: String, detail d: String, badge b: String, floating: Bool, query: String) {
        icon.image = img
        title.attributedStringValue = Self.highlighted(t, query: query)
        let subtitle = d.isEmpty ? (floating ? "Floating" : "") : (floating ? d + " · Floating" : d)
        detail.stringValue = subtitle
        detail.isHidden = subtitle.isEmpty
        badge.text = b
    }

    /// The query's characters in order: the ones that matched in full white (or black), the rest a step dimmer.
    private static func highlighted(_ text: String, query: String) -> NSAttributedString {
        let size: CGFloat = 14.5
        let base: NSColor = query.isEmpty ? .labelColor : .secondaryLabelColor
        let s = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .regular), .foregroundColor: base,
        ])
        var from = text.startIndex
        for ch in query where !ch.isWhitespace {
            guard let r = text.range(of: String(ch), options: .caseInsensitive, range: from..<text.endIndex) else { break }
            let range = NSRange(r, in: text)
            s.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.labelColor],
                            range: range)
            from = r.upperBound
        }
        return s
    }
}
