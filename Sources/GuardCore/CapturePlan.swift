import Foundation

public struct CapturePlan: Sendable {
    public var interface: String
    public var destination: String
    public var seconds: Int
    public init(interface: String, destination: String, seconds: Int) {
        self.interface = interface; self.destination = destination; self.seconds = seconds
    }
    public var valid: Bool {
        interface.range(
            of: #"^(en|utun|pdp_ip)[0-9]{1,3}$"#,
            options: .regularExpression
        ) != nil &&
        IPAddress.normalized(destination) != nil && (5...60).contains(seconds)
    }
    /// All interpolated values are validated. Root creates its own exclusive temporary file.
    public func administratorScript(uid: UInt32) -> String? {
        guard valid, uid > 0, let ip = IPAddress.normalized(destination) else { return nil }
        return """
        set -eu
        umask 077
        capture=$(/usr/bin/mktemp /private/tmp/routekeeper-capture.XXXXXXXX)
        # alarm survives exec in the same process; no delayed root kill of a potentially reused PID.
        /usr/bin/perl -e 'alarm shift; exec @ARGV or die "exec failed"' \(seconds) /usr/sbin/tcpdump -nn -q -l -i \(interface) -c 200 'host \(ip) and (tcp or udp)' >"$capture" 2>&1 || true
        /usr/sbin/chown \(uid) "$capture"
        /bin/echo "$capture"
        """
    }
    public static func appleScript(_ script: String) -> String {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        return "do shell script \"\(escaped)\" with prompt \"Routekeeper: capture packet headers on the selected interface for at most 60 seconds\" with administrator privileges"
    }
}
