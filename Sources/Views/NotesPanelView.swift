import AppKit
import SwiftUI

/// Right-hand markdown scratchpad: write notes, then run fenced code blocks in the active terminal.
struct NotesPanelView: View {
  @AppStorage("notesMarkdown") private var notes = ""
  @State private var isEditing = true

  /// Sends text to the active terminal; nil when there is no session.
  let onRun: ((String) -> Void)?

  var body: some View {
    VStack(spacing: 0) {
      Picker("Mode", selection: $isEditing) {
        Text("Edit").tag(true)
        Text("Preview").tag(false)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(8)

      Divider()

      if isEditing {
        MarkdownEditor(text: $notes)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            let segments = Self.segments(of: notes)
            ForEach(Array(segments.enumerated()), id: \.offset) { offset, segment in
              switch segment {
              case .text(let text):
                ProseView(text: text)
              case .code(let code):
                let index = segments[..<offset].filter { if case .code = $0 { true } else { false } }.count
                CodeBlockView(
                  code: Binding(
                    get: { code },
                    set: { notes = Self.replacingCode(at: index, with: $0, in: notes) }
                  ),
                  onRun: onRun
                )
              }
            }

            Button {
              notes += (notes.isEmpty || notes.hasSuffix("\n") ? "" : "\n") + "```sh\n\n```\n"
            } label: {
              Label("Add command", systemImage: "plus")
            }
            .buttonStyle(.borderless)
          }
          .padding(12)
        }
      }
    }
  }

  enum Segment: Equatable {
    case text(String)
    case code(String)
  }

  /// Splits markdown into prose and ``` fenced blocks; an unclosed fence runs to the end.
  static func segments(of source: String) -> [Segment] {
    var result: [Segment] = []
    var buffer: [Substring] = []
    var inCode = false

    func flush() {
      let joined = buffer.joined(separator: "\n")
      // Empty code blocks stay: they are boxes waiting to be filled.
      if inCode || !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.append(inCode ? .code(joined) : .text(joined))
      }
      buffer = []
    }

    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
        flush()
        inCode.toggle()
      } else {
        buffer.append(line)
      }
    }
    flush()
    return result
  }

  /// Rewrites the body of the nth fenced block (same numbering as `segments`), keeping its opening fence.
  static func replacingCode(at index: Int, with code: String, in source: String) -> String {
    var out: [Substring] = []
    var seen = -1
    var inCode = false
    var replacing = false

    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
      let isFence = line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
      if isFence {
        inCode.toggle()
        if inCode {
          seen += 1
          replacing = seen == index
          out.append(line)
          if replacing { out.append(Substring(code)) }
        } else {
          replacing = false
          out.append(line)
        }
      } else if !replacing {
        out.append(line)
      }
    }
    // An unclosed fence being replaced loses its body; close it so the edit stays in the block.
    if replacing { out.append("```") }
    return out.joined(separator: "\n")
  }
}

/// Prose of the preview: headings styled, the rest as inline markdown with coloured `code`.
// shortcut: headings + inline marks only (no lists/tables), upgrade to a block renderer if needed.
private struct ProseView: View {
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
        if let heading = Self.heading(line) {
          Text(heading.text)
            .font(heading.level == 1 ? .title2.bold() : heading.level == 2 ? .title3.bold() : .headline)
            .foregroundStyle(.purple)
            .padding(.top, 4)
        } else {
          Text(Self.inline(line.isEmpty ? " " : String(line)))
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .textSelection(.enabled)
  }

  private static func heading(_ line: Substring) -> (level: Int, text: String)? {
    let level = line.prefix { $0 == "#" }.count
    guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
    return (level, line.dropFirst(level + 1).trimmingCharacters(in: .whitespaces))
  }

  private static func inline(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    var attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
      attributed[run.range].foregroundColor = .orange
    }
    return attributed
  }
}

/// Fenced code block: highlighted editable box with copy and run buttons.
private struct CodeBlockView: View {
  @Binding var code: String
  let onRun: ((String) -> Void)?
  @State private var copied = false

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      CodeEditor(text: $code)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 10) {
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(code, forType: .string)
          copied = true
          Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
          }
        } label: {
          Image(systemName: copied ? "checkmark" : "doc.on.doc")
        }
        .help("Copy")

        Button {
          onRun?(code + "\n")
        } label: {
          Image(systemName: "play.fill")
        }
        .disabled(onRun == nil)
        .help("Run in the active terminal")
      }
      .buttonStyle(.borderless)
    }
    .padding(8)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
  }
}

// MARK: - Highlighting

private struct Rule {
  let regex: NSRegularExpression
  let color: NSColor
  let weight: NSFont.Weight
  /// Rules applied again inside each match (code inside a fence).
  let inner: [Rule]

  init(
    _ pattern: String,
    _ color: NSColor,
    _ weight: NSFont.Weight = .regular,
    inner: [Rule] = []
  ) {
    regex = try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
    self.color = color
    self.weight = weight
    self.inner = inner
  }
}

private enum Highlighter {
  static func font(_ weight: NSFont.Weight) -> NSFont {
    .monospacedSystemFont(ofSize: 12, weight: weight)
  }

  /// Later rules override earlier ones.
  // shortcut: generic regex rules shared by shell/SQL/Clojure, not a parser; swap for Lambda's tree-sitter if accuracy matters.
  static let code: [Rule] = [
    Rule(#"(?<![\w-])--?[A-Za-z][\w-]*"#, .systemTeal),
    Rule(#"\b\d+(?:\.\d+)?\b"#, .systemOrange),
    Rule(#"\$\{?[A-Za-z_]\w*\}?|\$[@#?!*0-9]|(?<![\w:]):[A-Za-z][\w?!./-]*"#, .systemCyan),
    Rule(
      #"\b(?:sudo|docker|echo|if|then|else|elif|fi|for|in|do|done|while|case|esac|export|local|read|set|return|exit|"#
        + #"function|java|ssh|cd|ls|cat|grep|chmod|tee|bash|ALTER|ROLE|WITH|PASSWORD|UPDATE|SET|SELECT|FROM|WHERE|"#
        + #"INSERT|INTO|DELETE|CREATE|DROP|TABLE|defn-?|def|let|fn|ns|require|comment|when|cond)\b"#,
      .systemPurple, .semibold),
    Rule(#""(?:[^"\\\n]|\\.)*"|'[^'\n]*'"#, .systemGreen),
    Rule(#"(?:^|(?<=\s))(?:#|;;|--\s|//).*$"#, .systemGray),
  ]

  static let markdown: [Rule] = [
    Rule(#"^\s*(?:[-*+]|\d+\.)\s"#, .systemPink),
    Rule(#"\[[^\]\n]+\]\([^)\n]+\)"#, .systemBlue),
    Rule(#"\*\*[^*\n]+\*\*"#, .systemYellow, .bold),
    Rule(#"`[^`\n]+`"#, .systemOrange),
    Rule(#"^#{1,6}\s.*$"#, .systemPurple, .bold),
    // Code bodies get code colours; only the fence lines are green.
    Rule(#"^[ \t]*```[\s\S]*?(?:^[ \t]*```|\z)"#, .textColor, inner: code),
    Rule(#"^[ \t]*```.*$"#, .systemGreen),
  ]

  static func apply(_ rules: [Rule], to storage: NSTextStorage, in range: NSRange) {
    for rule in rules {
      rule.regex.enumerateMatches(in: storage.string, range: range) { match, _, _ in
        guard let found = match?.range else { return }
        storage.addAttributes([.foregroundColor: rule.color, .font: font(rule.weight)], range: found)
        apply(rule.inner, to: storage, in: found)
      }
    }
  }

  static func highlight(_ textView: NSTextView, rules: [Rule]) {
    guard let storage = textView.textStorage else { return }
    let full = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    storage.setAttributes([.font: font(.regular), .foregroundColor: NSColor.textColor], range: full)
    apply(rules, to: storage, in: full)
    storage.endEditing()
  }
}

/// Shared NSTextView plumbing: binding sync, no "smart" substitutions (notes hold commands).
private final class HighlightingCoordinator: NSObject, NSTextViewDelegate {
  var text: Binding<String>
  let rules: [Rule]

  init(text: Binding<String>, rules: [Rule]) {
    self.text = text
    self.rules = rules
  }

  func textDidChange(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView else { return }
    text.wrappedValue = textView.string
    Highlighter.highlight(textView, rules: rules)
  }

  func configure(_ textView: NSTextView, text: String) {
    textView.delegate = self
    textView.isRichText = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.font = Highlighter.font(.regular)
    textView.string = text
    Highlighter.highlight(textView, rules: rules)
  }

  func sync(_ textView: NSTextView, text: String) {
    if textView.string != text {
      textView.string = text
      Highlighter.highlight(textView, rules: rules)
    }
  }
}

/// Scrolling editor for the whole notes text, markdown-coloured.
private struct MarkdownEditor: NSViewRepresentable {
  @Binding var text: String

  func makeCoordinator() -> HighlightingCoordinator {
    HighlightingCoordinator(text: $text, rules: Highlighter.markdown)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.drawsBackground = false
    let textView = scrollView.documentView as! NSTextView
    textView.textContainerInset = NSSize(width: 8, height: 8)
    context.coordinator.configure(textView, text: text)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.text = $text
    context.coordinator.sync(scrollView.documentView as! NSTextView, text: text)
  }
}

/// Self-sizing editor for one code block, code-coloured.
private struct CodeEditor: NSViewRepresentable {
  @Binding var text: String

  func makeCoordinator() -> HighlightingCoordinator {
    HighlightingCoordinator(text: $text, rules: Highlighter.code)
  }

  func makeNSView(context: Context) -> NSTextView {
    // Explicit TextKit 1 stack: sizeThatFits needs the layout manager.
    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layoutManager.addTextContainer(container)
    storage.addLayoutManager(layoutManager)
    let textView = NSTextView(frame: .zero, textContainer: container)
    textView.isVerticallyResizable = false
    textView.isHorizontallyResizable = false
    textView.textContainerInset = .zero
    container.lineFragmentPadding = 0
    context.coordinator.configure(textView, text: text)
    return textView
  }

  func updateNSView(_ textView: NSTextView, context: Context) {
    context.coordinator.text = $text
    context.coordinator.sync(textView, text: text)
  }

  /// Sizes like `Text`: at most its unwrapped width, wrapping at whatever width the parent offers.
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
    guard let container = nsView.textContainer, let layoutManager = nsView.layoutManager else { return nil }
    container.containerSize = NSSize(width: 1_000_000, height: CGFloat.greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: container)
    let natural = ceil(layoutManager.usedRect(for: container).width) + 1
    let width = min(proposal.width ?? natural, natural)
    container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: container)
    let lineHeight = Highlighter.font(.regular).boundingRectForFont.height
    return CGSize(width: width, height: max(ceil(layoutManager.usedRect(for: container).height), lineHeight))
  }
}
