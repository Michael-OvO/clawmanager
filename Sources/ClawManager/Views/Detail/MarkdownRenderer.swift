import SwiftUI

// MARK: - Block Model

/// Represents a parsed block-level markdown element.
struct MarkdownBlock: Identifiable, Sendable {
    /// Stable identity assigned at parse time (index-based, never recomputed).
    let id: String
    let kind: Kind

    enum Kind: Sendable {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case codeBlock(language: String?, code: String)
        case unorderedList(items: [ListItem])
        case orderedList(items: [ListItem])
        case blockquote(text: String)
        case horizontalRule
        case table(headers: [String], rows: [[String]])
    }

    struct ListItem: Hashable, Sendable {
        let text: String
        let depth: Int
    }
}

// MARK: - Parser

enum MarkdownParser {

    static func parse(_ input: String) -> [MarkdownBlock] {
        let lines = input.components(separatedBy: "\n")
        var kinds: [MarkdownBlock.Kind] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line — skip
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code block
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                kinds.append(.codeBlock(
                    language: lang.isEmpty ? nil : lang,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            // Horizontal rule
            if isHorizontalRule(trimmed) {
                kinds.append(.horizontalRule)
                i += 1
                continue
            }

            // Heading
            if let (level, text) = parseHeading(trimmed) {
                kinds.append(.heading(level: level, text: text))
                i += 1
                continue
            }

            // Table
            if isTableRow(trimmed) && i + 1 < lines.count && isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                let (table, newIndex) = parseTable(lines: lines, startIndex: i)
                if let table = table {
                    kinds.append(table)
                }
                i = newIndex
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix(">") {
                        let content = String(l.dropFirst()).trimmingCharacters(in: .whitespaces)
                        quoteLines.append(content)
                    } else if l.isEmpty && !quoteLines.isEmpty {
                        break
                    } else {
                        break
                    }
                    i += 1
                }
                kinds.append(.blockquote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // Unordered list
            if isUnorderedListItem(trimmed) {
                var items: [MarkdownBlock.ListItem] = []
                while i < lines.count {
                    let l = lines[i]
                    let lt = l.trimmingCharacters(in: .whitespaces)
                    if isUnorderedListItem(lt) {
                        let depth = listIndentDepth(l)
                        let text = stripListMarker(lt, ordered: false)
                        items.append(.init(text: text, depth: depth))
                    } else if lt.isEmpty {
                        // empty line might end the list
                        if i + 1 < lines.count && isUnorderedListItem(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                            i += 1
                            continue
                        }
                        break
                    } else {
                        break
                    }
                    i += 1
                }
                kinds.append(.unorderedList(items: items))
                continue
            }

            // Ordered list
            if isOrderedListItem(trimmed) {
                var items: [MarkdownBlock.ListItem] = []
                while i < lines.count {
                    let l = lines[i]
                    let lt = l.trimmingCharacters(in: .whitespaces)
                    if isOrderedListItem(lt) {
                        let depth = listIndentDepth(l)
                        let text = stripListMarker(lt, ordered: true)
                        items.append(.init(text: text, depth: depth))
                    } else if lt.isEmpty {
                        if i + 1 < lines.count && isOrderedListItem(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                            i += 1
                            continue
                        }
                        break
                    } else {
                        break
                    }
                    i += 1
                }
                kinds.append(.orderedList(items: items))
                continue
            }

            // Paragraph — collect contiguous non-blank, non-special lines
            var paraLines: [String] = []
            while i < lines.count {
                let l = lines[i]
                let lt = l.trimmingCharacters(in: .whitespaces)
                if lt.isEmpty || lt.hasPrefix("```") || lt.hasPrefix("#") || lt.hasPrefix(">")
                    || isUnorderedListItem(lt) || isOrderedListItem(lt) || isHorizontalRule(lt) {
                    break
                }
                paraLines.append(lt)
                i += 1
            }
            if !paraLines.isEmpty {
                kinds.append(.paragraph(text: paraLines.joined(separator: "\n")))
            }
        }

        // Assign stable index-based IDs
        return kinds.enumerated().map { index, kind in
            MarkdownBlock(id: "mb-\(index)", kind: kind)
        }
    }

    // MARK: - Helpers

    private static func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6, line.count > level else { return nil }
        let idx = line.index(line.startIndex, offsetBy: level)
        guard line[idx] == " " else { return nil }
        let text = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        return (stripped.allSatisfy({ $0 == "-" }) && stripped.count >= 3) ||
               (stripped.allSatisfy({ $0 == "*" }) && stripped.count >= 3) ||
               (stripped.allSatisfy({ $0 == "_" }) && stripped.count >= 3)
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        guard let dotIndex = line.firstIndex(of: ".") else { return false }
        let prefix = line[line.startIndex..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isNumber }) else { return false }
        let afterDot = line.index(after: dotIndex)
        return afterDot < line.endIndex && line[afterDot] == " "
    }

    private static func listIndentDepth(_ line: String) -> Int {
        var spaces = 0
        for ch in line {
            if ch == " " { spaces += 1 }
            else if ch == "\t" { spaces += 4 }
            else { break }
        }
        return spaces / 2
    }

    private static func stripListMarker(_ line: String, ordered: Bool) -> String {
        if ordered {
            if let dotIndex = line.firstIndex(of: ".") {
                let afterDot = line.index(after: dotIndex)
                if afterDot < line.endIndex {
                    return String(line[line.index(after: afterDot)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            return line
        } else {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|") && line.filter({ $0 == "|" }).count >= 2
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }
        let cells = parseTableCells(line)
        return cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: .whitespaces)
            return stripped.allSatisfy({ $0 == "-" || $0 == ":" }) && stripped.count >= 1
        }
    }

    private static func parseTableCells(_ line: String) -> [String] {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        let inner: String
        if stripped.hasPrefix("|") && stripped.hasSuffix("|") {
            inner = String(stripped.dropFirst().dropLast())
        } else {
            inner = stripped
        }
        return inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseTable(lines: [String], startIndex: Int) -> (MarkdownBlock.Kind?, Int) {
        var i = startIndex
        let headers = parseTableCells(lines[i])
        i += 1 // skip header row
        i += 1 // skip separator row

        var rows: [[String]] = []
        while i < lines.count {
            let lt = lines[i].trimmingCharacters(in: .whitespaces)
            guard isTableRow(lt) else { break }
            rows.append(parseTableCells(lt))
            i += 1
        }
        return (.table(headers: headers, rows: rows), i)
    }
}

// MARK: - Inline Markdown Text

/// Renders inline markdown (bold, italic, code, links) using AttributedString.
/// Caches the parsed AttributedString in @State to avoid recomputing on every body evaluation.
struct InlineMarkdownText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var cachedAttributed: AttributedString?
    @State private var cachedInput: String = ""

    init(_ text: String, font: Font = DS.Typography.body, color: Color = DS.Color.Text.primary) {
        self.text = text
        self.font = font
        self.color = color
    }

    var body: some View {
        Text(cachedAttributed ?? AttributedString(text))
            .font(font)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .onAppear { updateIfNeeded() }
            .onChange(of: text) { _, _ in updateIfNeeded() }
    }

    private func updateIfNeeded() {
        guard text != cachedInput else { return }
        cachedInput = text
        if var attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            for run in attributed.runs {
                if run.inlinePresentationIntent?.contains(.code) == true {
                    attributed[run.range].foregroundColor = NSColor(DS.Color.Accent.primary)
                }
            }
            cachedAttributed = attributed
        } else {
            cachedAttributed = AttributedString(text)
        }
    }
}

// MARK: - Main Renderer View

struct MarkdownRenderer: View {
    let text: String

    @State private var cachedBlocks: [MarkdownBlock] = []
    @State private var cachedText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ForEach(cachedBlocks) { block in
                blockView(for: block.kind)
            }
        }
        .onAppear { updateIfNeeded() }
        .onChange(of: text) { _, _ in updateIfNeeded() }
    }

    private func updateIfNeeded() {
        guard text != cachedText else { return }
        cachedText = text
        cachedBlocks = MarkdownParser.parse(text)
    }

    @ViewBuilder
    private func blockView(for kind: MarkdownBlock.Kind) -> some View {
        switch kind {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .paragraph(let text):
            InlineMarkdownText(text)

        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)

        case .unorderedList(let items):
            unorderedListView(items: items)

        case .orderedList(let items):
            orderedListView(items: items)

        case .blockquote(let text):
            blockquoteView(text: text)

        case .horizontalRule:
            horizontalRuleView()

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
        }
    }

    // MARK: - Heading

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let font: Font = switch level {
        case 1: DS.Typography.mdH1
        case 2: DS.Typography.mdH2
        case 3: DS.Typography.mdH3
        default: DS.Typography.mdH4
        }

        VStack(alignment: .leading, spacing: DS.Space.xs) {
            InlineMarkdownText(text, font: font, color: DS.Color.Text.primary)

            if level <= 2 {
                Rectangle()
                    .fill(DS.Color.Border.subtle)
                    .frame(height: 1)
            }
        }
        .padding(.top, level <= 2 ? DS.Space.sm : DS.Space.xs)
    }

    // MARK: - Code Block

    @ViewBuilder
    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label + copy button
            if let lang = language, !lang.isEmpty {
                HStack {
                    Text(lang)
                        .font(DS.Typography.micro)
                        .foregroundStyle(DS.Color.Text.tertiary)
                    Spacer()
                    CopyButton(text: code)
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.xs)
                .background(DS.Color.Surface.elevated)
            } else {
                HStack {
                    Spacer()
                    CopyButton(text: code)
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.xs)
                .background(DS.Color.Surface.elevated)
            }

            Divider().overlay(DS.Color.Border.subtle)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(DS.Typography.mdCodeBlock)
                    .foregroundStyle(DS.Color.Text.secondary)
                    .textSelection(.enabled)
                    .padding(DS.Space.md)
            }
        }
        .background(DS.Color.Surface.raised)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.Border.default, lineWidth: 1)
        )
    }

    // MARK: - Unordered List

    @ViewBuilder
    private func unorderedListView(items: [MarkdownBlock.ListItem]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                    Text(item.depth > 0 ? "◦" : "•")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Color.Text.tertiary)

                    InlineMarkdownText(item.text)
                }
                .padding(.leading, CGFloat(item.depth) * DS.Space.lg)
            }
        }
    }

    // MARK: - Ordered List

    @ViewBuilder
    private func orderedListView(items: [MarkdownBlock.ListItem]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                    Text("\(index + 1).")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Color.Text.tertiary)
                        .frame(minWidth: 18, alignment: .trailing)

                    InlineMarkdownText(item.text)
                }
                .padding(.leading, CGFloat(item.depth) * DS.Space.lg)
            }
        }
    }

    // MARK: - Blockquote

    @ViewBuilder
    private func blockquoteView(text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(DS.Color.Accent.secondary)
                .frame(width: 3)

            InlineMarkdownText(text, color: DS.Color.Text.secondary)
                .padding(.leading, DS.Space.md)
        }
        .padding(.vertical, DS.Space.xs)
    }

    // MARK: - Horizontal Rule

    @ViewBuilder
    private func horizontalRuleView() -> some View {
        Rectangle()
            .fill(DS.Color.Border.default)
            .frame(height: 1)
            .padding(.vertical, DS.Space.xs)
    }

    // MARK: - Table

    @ViewBuilder
    private func tableView(headers: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(header)
                            .font(DS.Typography.small)
                            .foregroundStyle(DS.Color.Text.primary)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, DS.Space.sm)
                            .frame(minWidth: 80, alignment: .leading)
                    }
                }
                .background(DS.Color.Surface.elevated)

                Divider().overlay(DS.Color.Border.default)

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            InlineMarkdownText(cell, font: DS.Typography.caption)
                                .padding(.horizontal, DS.Space.md)
                                .padding(.vertical, DS.Space.xs + 2)
                                .frame(minWidth: 80, alignment: .leading)
                        }
                    }
                    .background(rowIdx % 2 == 1 ? DS.Color.Surface.raised : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(DS.Color.Border.default, lineWidth: 1)
            )
        }
    }
}

// MARK: - Copy Button

struct CopyButton: View {
    let text: String
    var label: String? = nil
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                Text(copied ? "Copied" : (label ?? ""))
                    .font(DS.Typography.micro)
                    .opacity(copied || label != nil ? 1 : 0)
                    .frame(width: copied || label != nil ? nil : 0)
            }
            .foregroundStyle(copied ? DS.Color.Status.activeText : DS.Color.Text.tertiary)
        }
        .buttonStyle(.plain)
    }
}
