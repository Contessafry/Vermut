import Foundation

/// Normalizes and compares component release tags (e.g. `v0.80`, `0.80`, `11.18`).
public enum ComponentVersion {
    /// Strips a leading `v`/`V` and trims whitespace.
    public static func normalize(_ tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value = String(value.dropFirst())
        }
        return value
    }

    /// Canonical folder / display id: prefers a leading `v` when the source had one,
    /// otherwise returns the normalized numeric form.
    public static func canonicalTag(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalize(trimmed)
        guard !normalized.isEmpty else { return trimmed }
        if trimmed.lowercased().hasPrefix("v") {
            return "v" + normalized
        }
        // DXMT tags on GitHub always use a leading `v`.
        if normalized.contains(".") || normalized.allSatisfy(\.isNumber) {
            return "v" + normalized
        }
        return trimmed
    }

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalize(lhs).split(separator: ".").map(parsePart)
        let right = normalize(rhs).split(separator: ".").map(parsePart)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : Part(number: 0, suffix: "")
            let r = index < right.count ? right[index] : Part(number: 0, suffix: "")
            if l.number != r.number {
                return l.number < r.number ? .orderedAscending : .orderedDescending
            }
            if l.suffix != r.suffix {
                if l.suffix.isEmpty { return .orderedDescending }
                if r.suffix.isEmpty { return .orderedAscending }
                return l.suffix.localizedStandardCompare(r.suffix)
            }
        }
        return .orderedSame
    }

    public static func isAtLeast(_ tag: String, minimum: String) -> Bool {
        compare(tag, minimum) != .orderedAscending
    }

    private struct Part {
        var number: Int
        var suffix: String
    }

    private static func parsePart(_ raw: Substring) -> Part {
        var digits = ""
        var suffix = ""
        var inSuffix = false
        for character in raw {
            if !inSuffix, character.isNumber {
                digits.append(character)
            } else {
                inSuffix = true
                suffix.append(character)
            }
        }
        return Part(number: Int(digits) ?? 0, suffix: suffix)
    }
}
