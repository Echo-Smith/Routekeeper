import Foundation
import AppKit
import Observation
import Security
import GuardCore

@MainActor @Observable
final class CredentialController {
    enum Status: Equatable {
        case missing
        case saved
        case error(String)
    }

    private static let service = "com.routekeeper.claude-code.oauth"
    private static let account = NSUserName()
    var status: Status = .missing
    var message = "尚未保存 Claude Code 登录凭证"
    var savedAt: Date?
    var tokenInput = ""
    var busy = false

    init() {
        refresh()
    }

    func refresh() {
        var query = baseQuery()
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let result = SecItemCopyMatching(query as CFDictionary, nil)
        switch result {
        case errSecSuccess:
            status = .saved
            savedAt = UserDefaults.standard.object(forKey: "routekeeper.claude-token-saved-at") as? Date
            message = "登录凭证已保存在这台 Mac 的系统钥匙串中，可以用它启动 Claude Code。"
        case errSecItemNotFound:
            status = .missing
            savedAt = nil
            message = "尚未保存 Claude Code 登录凭证"
        default:
            status = .error("无法读取钥匙串（\(result)）")
            message = "无法读取 macOS 钥匙串，请在“钥匙串访问”中检查 Routekeeper。"
        }
    }

    func save() {
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy else { return }
        guard token.count >= 20, !token.contains(where: \.isNewline) else {
            status = .error("登录凭证格式无效")
            message = "请粘贴完整的 Claude Code 登录凭证；凭证不会写入日志或导出报告。"
            return
        }
        busy = true
        defer { busy = false }
        let query = baseQuery()
        let data = Data(token.utf8)
        let updateAttributes = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ] as CFDictionary
        let update = SecItemUpdate(query as CFDictionary, updateAttributes)
        let result: OSStatus
        if update == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            result = SecItemAdd(add as CFDictionary, nil)
        } else {
            result = update
        }
        guard result == errSecSuccess else {
            status = .error("保存失败（\(result)）")
            message = "macOS 钥匙串保存失败，登录凭证未被记录到应用日志。"
            return
        }
        tokenInput = ""
        savedAt = Date()
        UserDefaults.standard.set(savedAt, forKey: "routekeeper.claude-token-saved-at")
        status = .saved
        message = "登录凭证已保存。下次启动时可以直接使用。"
    }

    @discardableResult
    func delete() -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        let result = SecItemDelete(baseQuery() as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            status = .error("删除失败（\(result)）")
            message = "macOS 钥匙串删除失败，请在“钥匙串访问”中检查。"
            return false
        }
        tokenInput = ""
        savedAt = nil
        UserDefaults.standard.removeObject(forKey: "routekeeper.claude-token-saved-at")
        status = .missing
        message = "已删除 Claude Code 登录凭证。"
        return true
    }

    func openTokenSetup() {
        guard let installation = currentClaudeCodeInstallation() else {
            message = "未检测到可执行的 claude 命令。请先安装 Claude Code，或在“实验性沙箱”中选择命令位置。"
            return
        }
        let command = "\(shellQuote(installation.executableURL.path)) setup-token"
        message = openTerminal(command: command)
            ? "已打开 Terminal；完成官方认证后，把生成的登录凭证粘贴到下方。"
            : "无法打开“终端”；请在“隐私与安全性 > 自动化”中允许 Routekeeper 控制“终端”，或手动运行 \(installation.executableURL.path) setup-token。"
    }

    func launchClaudeCode() {
        guard status == .saved else {
            message = "请先完成 claude setup-token，并保存登录凭证。"
            return
        }
        guard let token = readToken() else {
            message = "无法从 macOS 钥匙串读取认证；请确认应用已解锁后重试。"
            return
        }
        guard let installation = currentClaudeCodeInstallation() else {
            message = "未找到可用的 claude 命令；请先安装 Claude Code，或在“实验性沙箱”中选择命令位置。"
            return
        }
        let task = Process()
        task.executableURL = installation.executableURL
        task.environment = [
            "CLAUDE_CODE_OAUTH_TOKEN": token,
            "CLAUDE_CODE_SUBPROCESS_ENV_SCRUB": "1",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            "HOME": NSHomeDirectory()
        ]
        do {
            try task.run()
            message = "已从 macOS 钥匙串读取认证并启动 Claude Code。"
        } catch {
            message = "无法启动 Claude Code，认证未写入日志。"
        }
    }

    func launchToken() -> String? {
        readToken()
    }

    private func currentClaudeCodeInstallation() -> ClaudeCodeInstallation? {
        ClaudeCodeDiscovery.locate(
            manualPath: UserDefaults.standard.string(
                forKey: ClaudeCodeDiscovery.manualPathPreferenceKey
            )
        )
    }

    private func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    private func openTerminal(command: String) -> Bool {
        let source = """
        tell application "Terminal"
        activate
        do script \(appleScriptString(command))
        end tell
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }


}
