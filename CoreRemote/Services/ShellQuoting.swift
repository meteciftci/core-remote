import Foundation

extension String {
    /// Quotes the string for POSIX shells so it is passed as a single literal word.
    nonisolated var shellQuoted: String {
        if !isEmpty, allSatisfy({ $0.isLetter && $0.isASCII || $0.isNumber || "@%+=:,./-_".contains($0) }) {
            return self
        }
        return "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
