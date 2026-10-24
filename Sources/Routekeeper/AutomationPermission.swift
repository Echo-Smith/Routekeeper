import AppKit
import CoreServices

enum TerminalAutomationPermission: Equatable {
    case checking
    case authorized
    case needsConsent
    case denied
    case terminalNotRunning
    case unavailable

    var showsAuthorizationCard: Bool {
        switch self {
        case .needsConsent, .denied, .unavailable:
            return true
        case .checking, .authorized, .terminalNotRunning:
            return false
        }
    }
}

enum TerminalAutomationPermissionProbe {
    static let terminalBundleIdentifier = "com.apple.Terminal"

    static func current() async -> TerminalAutomationPermission {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: check())
            }
        }
    }

    private static func check() -> TerminalAutomationPermission {
        guard let terminal = NSRunningApplication.runningApplications(
            withBundleIdentifier: terminalBundleIdentifier
        ).first else {
            return .terminalNotRunning
        }

        var processID = terminal.processIdentifier
        var address = AEAddressDesc()
        let createStatus = AECreateDesc(
            typeKernelProcessID,
            &processID,
            MemoryLayout<pid_t>.size,
            &address
        )
        guard createStatus == noErr else { return .unavailable }
        defer { AEDisposeDesc(&address) }

        let status = AEDeterminePermissionToAutomateTarget(
            &address,
            AEEventClass(kAECoreSuite),
            AEEventID(kAEOpenApplication),
            false
        )
        switch status {
        case noErr:
            return .authorized
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .needsConsent
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .unavailable
        }
    }
}
