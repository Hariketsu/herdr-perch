import Foundation

/// Strips the prompt prefix and icons agents write into terminal titles, e.g. OMP's
/// "π > 󰈙 DOCS: …" (architecture.md §4.4). Only the start of the title is touched.
public enum TitleCleaner {
    public static func clean(_ title: String) -> String {
        var rest = Substring(title).drop(while: \.isWhitespace)
        if rest.first == "π", rest.dropFirst().first?.isWhitespace == true {
            rest = rest.dropFirst().drop(while: \.isWhitespace)
        }
        if let first = rest.first, first == ">" || isBraille(first) {
            rest = rest.dropFirst().drop(while: \.isWhitespace)
        }
        while let first = rest.first, isIcon(first) {
            rest = rest.dropFirst().drop(while: \.isWhitespace)
        }
        let cleaned = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? title.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }

    /// U+2800–U+28FF: the spinner some agents show while working.
    private static func isBraille(_ character: Character) -> Bool {
        character.unicodeScalars.first.map { (0x2800...0x28FF).contains($0.value) } ?? false
    }

    /// Nerd Font glyphs (private use areas) and emoji/symbols; a grapheme carries its
    /// variation selector, so "📄\u{FE0F}" goes as one.
    private static func isIcon(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.properties.generalCategory {
        case .privateUse, .otherSymbol: return true
        default: return false
        }
    }
}
