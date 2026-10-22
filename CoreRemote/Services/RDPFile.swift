import Foundation

nonisolated enum RDPFile {
    /// Contents of a `.rdp` file understood by Microsoft Windows App.
    static func contents(for target: ConnectionTarget) -> String {
        let host = target.host.contains(":") && !target.host.hasPrefix("[") ? "[\(target.host)]" : target.host
        let options = target.rdp
        var lines = [
            "full address:s:\(host):\(target.port)",
            "username:s:\(target.username)",
            "screen mode id:i:\(options.display == .fullScreen ? 2 : 1)",
            // On by default, and it overrides the screen mode.
            "use multimon:i:\(options.usesAllScreens ? 1 : 0)",
            "dynamic resolution:i:\(options.resize == .resolution ? 1 : 0)",
            "smart sizing:i:\(options.resize == .scale ? 1 : 0)",
            "session bpp:i:32",
            "redirectclipboard:i:\(options.clipboard ? 1 : 0)",
            "audiomode:i:\(options.audio.rdpFileValue)",
            "prompt for credentials on client:i:0",
            // 0: connect without warning, 2: warn when the certificate can't be verified.
            "authentication level:i:\(target.ignoreCertificateErrors ? 0 : 2)",
        ]
        if let size = options.display.size {
            lines += ["desktopwidth:i:\(size.width)", "desktopheight:i:\(size.height)"]
        }
        // Windows App can share whole drives only, not a single folder.
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}

nonisolated private extension RDPAudio {
    var rdpFileValue: Int {
        switch self {
        case .mac: 0
        case .server: 1
        case .off: 2
        }
    }
}
