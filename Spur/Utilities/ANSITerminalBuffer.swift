import AppKit
import os

private let logger = Logger(subsystem: "com.spur.app", category: "ANSITerminalBuffer")

/// Parses a stream of raw terminal bytes (with ANSI escape sequences) into
/// an NSMutableAttributedString, handling colors, cursor-forward spacing,
/// and screen-clear commands.
final class ANSITerminalBuffer {

    private(set) var attributedText = NSMutableAttributedString()
    private var fg: NSColor = NSColor(white: 0.85, alpha: 1)
    private var bg: NSColor? = nil
    private var bold = false
    private var italic = false
    private var dim = false
    private let fontSize: CGFloat

    init(fontSize: CGFloat = 11) {
        self.fontSize = fontSize
    }

    /// Appends raw terminal text (may contain ANSI escape sequences).
    /// Returns true if a screen-clear command was encountered and the buffer was cleared.
    @discardableResult
    func append(_ raw: String) -> Bool {
        var cleared = false
        var i = raw.startIndex
        var pendingText = ""

        func flushPending() {
            guard !pendingText.isEmpty else { return }
            attributedText.append(NSAttributedString(string: pendingText, attributes: makeAttributes()))
            pendingText = ""
        }

        while i < raw.endIndex {
            let c = raw[i]
            if c == "\u{1B}" {
                flushPending()
                let j = raw.index(after: i)
                guard j < raw.endIndex else { i = raw.endIndex; break }
                switch raw[j] {
                case "[":
                    // CSI sequence — collect params until final byte 0x40–0x7E
                    var k = raw.index(after: j)
                    var params = ""
                    var foundFinal = false
                    while k < raw.endIndex {
                        let ch = raw[k]
                        if let a = ch.asciiValue, a >= 0x40 && a <= 0x7E {
                            handleCSI(params: params, final: ch, pendingText: &pendingText)
                            if ch == "J" && (params == "2" || params == "") {
                                cleared = true
                            }
                            i = raw.index(after: k)
                            foundFinal = true
                            break
                        } else {
                            params.append(ch)
                            k = raw.index(after: k)
                        }
                    }
                    if !foundFinal { i = raw.endIndex }
                case "]":
                    // OSC — skip to BEL (0x07) or ESC
                    var k = raw.index(after: j)
                    while k < raw.endIndex && raw[k] != "\u{07}" && raw[k] != "\u{1B}" {
                        k = raw.index(after: k)
                    }
                    i = k < raw.endIndex ? raw.index(after: k) : raw.endIndex
                default:
                    // Two-byte sequence — skip
                    i = raw.index(j, offsetBy: 1, limitedBy: raw.endIndex) ?? raw.endIndex
                }
            } else if c == "\r" {
                i = raw.index(after: i)
            } else {
                pendingText.append(c)
                i = raw.index(after: i)
            }
        }
        flushPending()
        return cleared
    }

    func clear() {
        attributedText = NSMutableAttributedString()
        resetStyle()
    }

    // MARK: - CSI dispatch

    private func handleCSI(params: String, final f: Character, pendingText: inout String) {
        switch f {
        case "m":
            handleSGR(params: params)
        case "C":
            // Cursor Forward — insert spaces to preserve visual spacing
            let n = max(1, Int(params) ?? 1)
            pendingText += String(repeating: " ", count: n)
        case "J":
            if params == "2" || params == "" {
                attributedText = NSMutableAttributedString()
            }
        case "H", "f":
            // Cursor Position — if home (1;1 or empty), treat as nothing
            break
        case "K", "A", "B", "D", "G", "l", "h", "r", "n", "s", "u", "p":
            break  // Ignore erase-line, cursor movement, mode sets
        default:
            break
        }
    }

    // MARK: - SGR (Select Graphic Rendition)

    private func handleSGR(params: String) {
        if params.isEmpty { resetStyle(); return }
        let parts = params.split(separator: ";", omittingEmptySubsequences: false)
        let codes = parts.compactMap { Int($0) }
        if codes.isEmpty { resetStyle(); return }

        var idx = 0
        while idx < codes.count {
            switch codes[idx] {
            case 0:  resetStyle()
            case 1:  bold = true
            case 2:  dim = true
            case 3:  italic = true
            case 22: bold = false; dim = false
            case 23: italic = false
            case 39: fg = NSColor(white: 0.85, alpha: 1)
            case 49: bg = nil
            // Standard foreground colors
            case 30: fg = NSColor(white: 0.15, alpha: 1)
            case 31: fg = NSColor(red: 0.85, green: 0.25, blue: 0.20, alpha: 1)
            case 32: fg = NSColor(red: 0.20, green: 0.75, blue: 0.35, alpha: 1)
            case 33: fg = NSColor(red: 0.90, green: 0.75, blue: 0.20, alpha: 1)
            case 34: fg = NSColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 1)
            case 35: fg = NSColor(red: 0.80, green: 0.35, blue: 0.85, alpha: 1)
            case 36: fg = NSColor(red: 0.25, green: 0.80, blue: 0.85, alpha: 1)
            case 37: fg = NSColor(white: 0.85, alpha: 1)
            // Bright foreground colors
            case 90: fg = NSColor(white: 0.50, alpha: 1)
            case 91: fg = NSColor(red: 1.0,  green: 0.45, blue: 0.40, alpha: 1)
            case 92: fg = NSColor(red: 0.45, green: 1.0,  blue: 0.55, alpha: 1)
            case 93: fg = NSColor(red: 1.0,  green: 1.0,  blue: 0.45, alpha: 1)
            case 94: fg = NSColor(red: 0.55, green: 0.75, blue: 1.0,  alpha: 1)
            case 95: fg = NSColor(red: 1.0,  green: 0.55, blue: 1.0,  alpha: 1)
            case 96: fg = NSColor(red: 0.55, green: 1.0,  blue: 1.0,  alpha: 1)
            case 97: fg = .white
            // Standard background colors
            case 40: bg = .black
            case 41: bg = NSColor(red: 0.55, green: 0.10, blue: 0.10, alpha: 1)
            case 42: bg = NSColor(red: 0.10, green: 0.40, blue: 0.15, alpha: 1)
            case 43: bg = NSColor(red: 0.45, green: 0.38, blue: 0.05, alpha: 1)
            case 44: bg = NSColor(red: 0.10, green: 0.20, blue: 0.55, alpha: 1)
            case 45: bg = NSColor(red: 0.45, green: 0.10, blue: 0.45, alpha: 1)
            case 46: bg = NSColor(red: 0.05, green: 0.40, blue: 0.45, alpha: 1)
            case 47: bg = NSColor(white: 0.75, alpha: 1)
            case 100: bg = NSColor(white: 0.30, alpha: 1)
            case 101...107: bg = NSColor(white: 0.50, alpha: 1) // simplified bright bg
            // Extended colors: 38;5;n or 38;2;r;g;b
            case 38:
                if idx + 2 < codes.count && codes[idx + 1] == 5 {
                    fg = color256(codes[idx + 2]); idx += 2
                } else if idx + 4 < codes.count && codes[idx + 1] == 2 {
                    fg = NSColor(red: CGFloat(codes[idx+2])/255,
                                 green: CGFloat(codes[idx+3])/255,
                                 blue: CGFloat(codes[idx+4])/255, alpha: 1)
                    idx += 4
                }
            case 48:
                if idx + 2 < codes.count && codes[idx + 1] == 5 {
                    bg = color256(codes[idx + 2]); idx += 2
                } else if idx + 4 < codes.count && codes[idx + 1] == 2 {
                    bg = NSColor(red: CGFloat(codes[idx+2])/255,
                                 green: CGFloat(codes[idx+3])/255,
                                 blue: CGFloat(codes[idx+4])/255, alpha: 1)
                    idx += 4
                }
            default: break
            }
            idx += 1
        }
    }

    private func resetStyle() {
        fg = NSColor(white: 0.85, alpha: 1)
        bg = nil
        bold = false
        italic = false
        dim = false
    }

    private func makeAttributes() -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]
        let weight: NSFont.Weight = bold ? .bold : .regular
        attrs[.font] = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        attrs[.foregroundColor] = dim ? fg.withAlphaComponent(0.55) : fg
        if let b = bg { attrs[.backgroundColor] = b }
        return attrs
    }

    // MARK: - 256-color lookup

    private func color256(_ n: Int) -> NSColor {
        guard n >= 0 && n <= 255 else { return .white }
        if n < 16 { return ansi16[n] }
        if n < 232 {
            let i = n - 16
            let b = i % 6, g = (i / 6) % 6, r = i / 36
            func v(_ x: Int) -> CGFloat { x == 0 ? 0 : (CGFloat(x) * 40 + 55) / 255 }
            return NSColor(red: v(r), green: v(g), blue: v(b), alpha: 1)
        }
        let v = CGFloat(8 + (n - 232) * 10) / 255
        return NSColor(white: v, alpha: 1)
    }

    private let ansi16: [NSColor] = [
        NSColor(white: 0.0, alpha: 1),                                          // 0  black
        NSColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1),                 // 1  red
        NSColor(red: 0.20, green: 0.70, blue: 0.30, alpha: 1),                 // 2  green
        NSColor(red: 0.85, green: 0.75, blue: 0.20, alpha: 1),                 // 3  yellow
        NSColor(red: 0.25, green: 0.50, blue: 0.90, alpha: 1),                 // 4  blue
        NSColor(red: 0.75, green: 0.30, blue: 0.80, alpha: 1),                 // 5  magenta
        NSColor(red: 0.20, green: 0.75, blue: 0.80, alpha: 1),                 // 6  cyan
        NSColor(white: 0.75, alpha: 1),                                         // 7  white
        NSColor(white: 0.50, alpha: 1),                                         // 8  bright black
        NSColor(red: 1.00, green: 0.40, blue: 0.40, alpha: 1),                 // 9  bright red
        NSColor(red: 0.40, green: 1.00, blue: 0.50, alpha: 1),                 // 10 bright green
        NSColor(red: 1.00, green: 1.00, blue: 0.40, alpha: 1),                 // 11 bright yellow
        NSColor(red: 0.50, green: 0.70, blue: 1.00, alpha: 1),                 // 12 bright blue
        NSColor(red: 1.00, green: 0.50, blue: 1.00, alpha: 1),                 // 13 bright magenta
        NSColor(red: 0.50, green: 1.00, blue: 1.00, alpha: 1),                 // 14 bright cyan
        NSColor(white: 1.00, alpha: 1),                                         // 15 bright white
    ]
}
