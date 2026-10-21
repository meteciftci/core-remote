import Foundation

nonisolated enum RDPFile {
    /// Contents of a `.rdp` file understood by Microsoft Windows App.
    static func contents(for target: ConnectionTarget) -> String {
        let host = target.host.contains(":") && !target.host.hasPrefix("[") ? "[\(target.host)]" : target.host
        let lines = [
            "full address:s:\(host):\(target.port)",
            "username:s:\(target.username)",
            "screen mode id:i:1", // windowed
            "dynamic resolution:i:1",
            "session bpp:i:32",
            "redirectclipboard:i:1",
            "audiomode:i:0",
            "prompt for credentials on client:i:0",
            // 0: connect without warning, 2: warn when the certificate can't be verified.
            "authentication level:i:\(target.ignoreCertificateErrors ? 0 : 2)",
        ]
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
