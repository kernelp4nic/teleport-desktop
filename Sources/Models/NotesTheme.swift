import AppKit

/// Colour theme for the notes panel. Palettes are copied from Lambda's `ThemeCatalog` (the roles the notes use).
struct NotesTheme: Identifiable {
  let id: String
  let name: String
  /// nil follows the macOS appearance (the "System" theme).
  let dark: Bool?
  let background: NSColor
  let foreground: NSColor
  let selection: NSColor
  let comment: NSColor
  let keyword: NSColor
  let string: NSColor
  let number: NSColor
  let cyan: NSColor
  let blue: NSColor
  let magenta: NSColor
  let yellow: NSColor
  let orange: NSColor
  let green: NSColor

  private init(
    _ id: String, _ name: String, dark: Bool,
    bg: UInt32, fg: UInt32, sel: UInt32, comment: UInt32, keyword: UInt32, string: UInt32, number: UInt32,
    cyan: UInt32, blue: UInt32, magenta: UInt32, yellow: UInt32, orange: UInt32, green: UInt32
  ) {
    self.id = id
    self.name = name
    self.dark = dark
    background = NSColor(hex: bg)
    foreground = NSColor(hex: fg)
    selection = NSColor(hex: sel)
    self.comment = NSColor(hex: comment)
    self.keyword = NSColor(hex: keyword)
    self.string = NSColor(hex: string)
    self.number = NSColor(hex: number)
    self.cyan = NSColor(hex: cyan)
    self.blue = NSColor(hex: blue)
    self.magenta = NSColor(hex: magenta)
    self.yellow = NSColor(hex: yellow)
    self.orange = NSColor(hex: orange)
    self.green = NSColor(hex: green)
  }

  static func named(_ id: String) -> NotesTheme { all.first { $0.id == id } ?? system }

  static let system = NotesTheme(
    id: "system", name: "System", dark: nil,
    background: .clear, foreground: .textColor, selection: .selectedTextBackgroundColor,
    comment: .systemGray, keyword: .systemPurple, string: .systemGreen, number: .systemOrange,
    cyan: .systemTeal, blue: .systemBlue, magenta: .systemPink, yellow: .systemYellow, orange: .systemOrange,
    green: .systemGreen)

  private init(
    id: String, name: String, dark: Bool?, background: NSColor, foreground: NSColor, selection: NSColor,
    comment: NSColor, keyword: NSColor, string: NSColor, number: NSColor, cyan: NSColor, blue: NSColor,
    magenta: NSColor, yellow: NSColor, orange: NSColor, green: NSColor
  ) {
    self.id = id
    self.name = name
    self.dark = dark
    self.background = background
    self.foreground = foreground
    self.selection = selection
    self.comment = comment
    self.keyword = keyword
    self.string = string
    self.number = number
    self.cyan = cyan
    self.blue = blue
    self.magenta = magenta
    self.yellow = yellow
    self.orange = orange
    self.green = green
  }

  static let all: [NotesTheme] = [
    system,
    NotesTheme("islands-dark", "Islands Dark", dark: true,
      bg: 0x191A1C, fg: 0xC7C1C6, sel: 0x2D456B, comment: 0x858999, keyword: 0xC76AE6, string: 0x97D172, number: 0x4D9FF8,
      cyan: 0x62C6C2, blue: 0x568EF2, magenta: 0xC76AE6, yellow: 0xE5C07B, orange: 0xE09D56, green: 0x97D172),
    NotesTheme("catppuccin-mocha", "Catppuccin Mocha", dark: true,
      bg: 0x1E1E2E, fg: 0xCDD6F4, sel: 0x45475A, comment: 0x9399B2, keyword: 0xCBA6F7, string: 0xA6E3A1, number: 0xFAB387,
      cyan: 0x94E2D5, blue: 0x89B4FA, magenta: 0xCBA6F7, yellow: 0xF9E2AF, orange: 0xFAB387, green: 0xA6E3A1),
    NotesTheme("dracula", "Dracula", dark: true,
      bg: 0x282A36, fg: 0xF8F8F2, sel: 0x44475A, comment: 0x6272A4, keyword: 0xFF79C6, string: 0xF1FA8C, number: 0xBD93F9,
      cyan: 0x8BE9FD, blue: 0xBD93F9, magenta: 0xFF79C6, yellow: 0xF1FA8C, orange: 0xFFB86C, green: 0x50FA7B),
    NotesTheme("github-dark", "GitHub Dark", dark: true,
      bg: 0x0D1117, fg: 0xE6EDF3, sel: 0x264F78, comment: 0x8B949E, keyword: 0xFF7B72, string: 0xA5D6FF, number: 0x79C0FF,
      cyan: 0x76E3EA, blue: 0x79C0FF, magenta: 0xD2A8FF, yellow: 0xE3B341, orange: 0xFFA657, green: 0x7EE787),
    NotesTheme("gruvbox-dark", "Gruvbox", dark: true,
      bg: 0x282828, fg: 0xEBDBB2, sel: 0x504945, comment: 0x928374, keyword: 0xFB4934, string: 0xB8BB26, number: 0xD3869B,
      cyan: 0x8EC07C, blue: 0x83A598, magenta: 0xD3869B, yellow: 0xFABD2F, orange: 0xFE8019, green: 0xB8BB26),
    NotesTheme("kanagawa", "Kanagawa", dark: true,
      bg: 0x1F1F28, fg: 0xDCD7BA, sel: 0x2D4F67, comment: 0x727169, keyword: 0x957FB8, string: 0x98BB6C, number: 0xD27E99,
      cyan: 0x7AA89F, blue: 0x7E9CD8, magenta: 0x957FB8, yellow: 0xE6C384, orange: 0xFFA066, green: 0x98BB6C),
    NotesTheme("monokai", "Monokai", dark: true,
      bg: 0x272822, fg: 0xF8F8F2, sel: 0x49483E, comment: 0x75715E, keyword: 0xF92672, string: 0xE6DB74, number: 0xAE81FF,
      cyan: 0xA1EFE4, blue: 0x66D9EF, magenta: 0xAE81FF, yellow: 0xE6DB74, orange: 0xFD971F, green: 0xA6E22E),
    NotesTheme("nord", "Nord", dark: true,
      bg: 0x2E3440, fg: 0xD8DEE9, sel: 0x434C5E, comment: 0x616E88, keyword: 0x81A1C1, string: 0xA3BE8C, number: 0xB48EAD,
      cyan: 0x8FBCBB, blue: 0x81A1C1, magenta: 0xB48EAD, yellow: 0xEBCB8B, orange: 0xD08770, green: 0xA3BE8C),
    NotesTheme("one-dark", "One Dark", dark: true,
      bg: 0x282C34, fg: 0xABB2BF, sel: 0x3E4451, comment: 0x5C6370, keyword: 0xC678DD, string: 0x98C379, number: 0xD19A66,
      cyan: 0x56B6C2, blue: 0x61AFEF, magenta: 0xC678DD, yellow: 0xE5C07B, orange: 0xD19A66, green: 0x98C379),
    NotesTheme("rose-pine", "Rosé Pine", dark: true,
      bg: 0x191724, fg: 0xE0DEF4, sel: 0x403D52, comment: 0x6E6A86, keyword: 0x31748F, string: 0xF6C177, number: 0xF6C177,
      cyan: 0x9CCFD8, blue: 0x31748F, magenta: 0xC4A7E7, yellow: 0xF6C177, orange: 0xEBBCBA, green: 0x31748F),
    NotesTheme("solarized-dark", "Solarized Dark", dark: true,
      bg: 0x002B36, fg: 0x839496, sel: 0x274642, comment: 0x586E75, keyword: 0x859900, string: 0x2AA198, number: 0xD33682,
      cyan: 0x2AA198, blue: 0x268BD2, magenta: 0xD33682, yellow: 0xB58900, orange: 0xCB4B16, green: 0x859900),
    NotesTheme("tokyo-night", "Tokyo Night", dark: true,
      bg: 0x1A1B26, fg: 0xC0CAF5, sel: 0x283457, comment: 0x565F89, keyword: 0xBB9AF7, string: 0x9ECE6A, number: 0xFF9E64,
      cyan: 0x7DCFFF, blue: 0x7AA2F7, magenta: 0xBB9AF7, yellow: 0xE0AF68, orange: 0xFF9E64, green: 0x9ECE6A),
    NotesTheme("catppuccin-latte", "Catppuccin Latte", dark: false,
      bg: 0xEFF1F5, fg: 0x4C4F69, sel: 0xCCD0DA, comment: 0x7C7F93, keyword: 0x8839EF, string: 0x40A02B, number: 0xFE640B,
      cyan: 0x179299, blue: 0x1E66F5, magenta: 0x8839EF, yellow: 0xDF8E1D, orange: 0xFE640B, green: 0x40A02B),
    NotesTheme("github-light", "GitHub Light", dark: false,
      bg: 0xFFFFFF, fg: 0x1F2328, sel: 0xCCE0F7, comment: 0x6E7781, keyword: 0xCF222E, string: 0x0A3069, number: 0x0550AE,
      cyan: 0x1B7C83, blue: 0x0969DA, magenta: 0x8250DF, yellow: 0x9A6700, orange: 0xBC4C00, green: 0x116329),
    NotesTheme("one-light", "One Light", dark: false,
      bg: 0xFAFAFA, fg: 0x383A42, sel: 0xE5E5E6, comment: 0xA0A1A7, keyword: 0xA626A4, string: 0x50A14F, number: 0x986801,
      cyan: 0x0184BC, blue: 0x4078F2, magenta: 0xA626A4, yellow: 0xC18401, orange: 0x986801, green: 0x50A14F),
    NotesTheme("solarized-light", "Solarized Light", dark: false,
      bg: 0xFDF6E3, fg: 0x657B83, sel: 0xE4DCC4, comment: 0x93A1A1, keyword: 0x859900, string: 0x2AA198, number: 0xD33682,
      cyan: 0x2AA198, blue: 0x268BD2, magenta: 0xD33682, yellow: 0xB58900, orange: 0xCB4B16, green: 0x859900),
  ]
}

private extension NSColor {
  convenience init(hex: UInt32) {
    self.init(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1)
  }
}
