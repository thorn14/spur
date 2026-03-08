import Foundation

/// Sanitizes arbitrary user-provided names into valid git branch name segments.
/// Output: lowercase ASCII alphanumeric characters and hyphens only, max `maxLength` chars.
enum SlugGenerator {

    /// - Parameters:
    ///   - name: The raw name to sanitize.
    ///   - maxLength: Maximum character length of the output. Default 50.
    /// - Returns: A slug string, or `"option"` if no valid characters remain.
    static func generate(from name: String, maxLength: Int = 50) -> String {
        var result = ""

        for char in name.lowercased() {
            if let ascii = char.asciiValue {
                // a-z or 0-9 → keep as-is
                if (ascii >= 97 && ascii <= 122) || (ascii >= 48 && ascii <= 57) {
                    result.append(char)
                } else {
                    // Everything else (space, underscore, punctuation, etc.) → hyphen
                    result.append("-")
                }
            } else {
                // Non-ASCII (accented letters, CJK, emoji, …) → hyphen
                result.append("-")
            }
        }

        // Collapse consecutive hyphens
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }

        // Strip leading/trailing hyphens
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Truncate to maxLength, then re-strip in case the cut landed on a hyphen
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
            result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        return result.isEmpty ? "option" : result
    }
}
