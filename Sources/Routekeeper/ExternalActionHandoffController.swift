import AppKit
import Foundation
import GuardCore
import Observation

enum HandoffApprovalState: Equatable {
    case pending
    case running
    case completed(String)
    case failed(String)
    case rejected

    var isActionable: Bool {
        switch self {
        case .pending, .failed: return true
        case .running, .completed, .rejected: return false
        }
    }
}

struct HandoffActionItem: Equatable, Identifiable {
    var package: HandoffActionPackage
    var state: HandoffApprovalState = .pending

    var id: String { package.id }
}

@MainActor
@Observable
final class ExternalActionController {
    var items: [HandoffActionItem] = []
    var issues: [HandoffScanIssue] = []
    var scannedAt: Date?
    var message = "Claude 尚未提交外部操作请求。"
    var directoryURL: URL?

    var pendingCount: Int {
        items.filter { $0.state == .pending || isFailed($0.state) }.count
    }

    var isRunning: Bool {
        items.contains { $0.state == .running }
    }

    @ObservationIgnored private var exchangeURL: URL?
    @ObservationIgnored private var scanLoop: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var sessionStartedAt: Date?

    func start(exchange: URL) {
        stopScanning()
        exchangeURL = exchange
        sessionStartedAt = Date().addingTimeInterval(-1)
        items = []
        issues = []
        scannedAt = nil
        do {
            let directory = try HandoffActionScanner.prepareDirectory(in: exchange)
            directoryURL = directory
            message = L10n.resolvedEnglish
                ? "Claude can submit handoff requests; the host performs them only after your approval."
                : "Claude 可以提交交接请求；只有在用户批准后，宿主才会执行。"
            refresh()
            scanLoop = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.refresh()
                }
            }
        } catch {
            directoryURL = nil
            items = []
            issues = []
            message = "无法建立外部操作交接目录：\(error.localizedDescription)"
        }
    }

    func stopScanning() {
        scanLoop?.cancel()
        scanLoop = nil
        scanTask?.cancel()
        scanTask = nil
        generation += 1
        scanning = false
    }

    func clear() {
        stopScanning()
        exchangeURL = nil
        sessionStartedAt = nil
        directoryURL = nil
        items = []
        issues = []
        scannedAt = nil
        message = "Claude 尚未提交外部操作请求。"
    }

    func refresh() {
        guard !scanning, let exchangeURL else { return }
        scanning = true
        generation += 1
        let requestGeneration = generation
        let notBefore = sessionStartedAt
        scanTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                HandoffActionScanner.scan(exchange: exchangeURL, notBefore: notBefore)
            }.value
            guard let self, self.generation == requestGeneration else { return }
            self.scanning = false
            self.apply(result)
        }
    }

    func openDirectory() {
        guard let directoryURL else { return }
        NSWorkspace.shared.open(directoryURL)
    }

    func reject(_ item: HandoffActionItem) {
        update(item.id) { _ in .rejected }
        message = L10n.resolvedEnglish
            ? "The handoff request was rejected."
            : "已拒绝该外部操作请求。"
    }

    func export(_ item: HandoffActionItem, to destination: URL) {
        guard item.package.request.kind == .exportFile, begin(item) else { return }
        do {
            try item.package.payloadData.write(to: destination, options: .atomic)
            complete(item, message: L10n.resolvedEnglish
                ? "Saved the reviewed payload to the selected location."
                : "已将审阅后的交付文件保存到所选位置。")
        } catch {
            fail(item, message: "保存失败：\(error.localizedDescription)")
        }
    }

    func applyGitPatch(_ item: HandoffActionItem, repository: URL) {
        guard item.package.request.kind == .applyGitPatch, begin(item) else { return }
        let package = item.package
        Task { [weak self] in
            do {
                let detail = try await Task.detached(priority: .userInitiated) {
                    try ExternalActionExecutor.applyGitPatch(package, repository: repository)
                }.value
                self?.complete(item, message: detail)
            } catch {
                self?.fail(item, message: error.localizedDescription)
            }
        }
    }

    private func begin(_ item: HandoffActionItem) -> Bool {
        guard let current = items.first(where: { $0.id == item.id }),
              current.state.isActionable else { return false }
        update(item.id) { _ in .running }
        return true
    }

    private func complete(_ item: HandoffActionItem, message: String) {
        update(item.id) { _ in .completed(message) }
        self.message = message
    }

    private func fail(_ item: HandoffActionItem, message: String) {
        update(item.id) { _ in .failed(message) }
        self.message = message
    }

    private func update(_ id: String, transform: (HandoffApprovalState) -> HandoffApprovalState) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = transform(items[index].state)
    }

    private func apply(_ result: HandoffScanResult) {
        let existing = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.state) })
        items = result.packages.map { package in
            .init(package: package, state: existing[package.id] ?? .pending)
        }
        issues = result.issues
        scannedAt = Date()
        if items.isEmpty {
            message = L10n.resolvedEnglish
                ? "Waiting for a valid handoff request from Claude."
                : "正在等待 Claude 提交有效的交接请求。"
        } else if pendingCount > 0 {
            message = L10n.resolvedEnglish
                ? "\(pendingCount) handoff request(s) need review."
                : "\(pendingCount) 个外部操作请求等待确认。"
        } else if isRunning {
            message = L10n.resolvedEnglish
                ? "A host-side handoff operation is running."
                : "宿主正在执行外部操作。"
        } else {
            message = L10n.resolvedEnglish
                ? "No handoff requests are waiting."
                : "当前没有待确认的外部操作。"
        }
    }

    private func isFailed(_ state: HandoffApprovalState) -> Bool {
        if case .failed = state { return true }
        return false
    }
}

enum ExternalActionExecutor {
    static func applyGitPatch(_ package: HandoffActionPackage, repository: URL) throws -> String {
        guard package.request.kind == .applyGitPatch else {
            throw ExternalActionExecutionError.wrongActionKind
        }
        let repository = repository.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repository.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ExternalActionExecutionError.invalidRepository
        }

        let rootResult = runGit(repository: repository, arguments: ["rev-parse", "--show-toplevel"])
        guard rootResult.status == 0 else {
            throw ExternalActionExecutionError.notGitRepository(rootResult.output)
        }
        let rootPath = rootResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard rootPath.hasPrefix("/") else {
            throw ExternalActionExecutionError.notGitRepository(rootResult.output)
        }
        try validatePatchPaths(package.payloadData)

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Routekeeper-Git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let patchURL = temporaryRoot.appendingPathComponent("reviewed.patch", isDirectory: false)
        try package.payloadData.write(to: patchURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: patchURL.path)

        let commonArguments = [
            "apply", "--no-unsafe-paths", "--whitespace=nowarn", patchURL.path
        ]
        let checkArguments = ["apply", "--check"] + Array(commonArguments.dropFirst())
        let check = runGit(repository: root, arguments: checkArguments)
        guard check.status == 0 else {
            throw ExternalActionExecutionError.patchCheckFailed(check.output)
        }
        let apply = runGit(repository: root, arguments: commonArguments)
        guard apply.status == 0 else {
            throw ExternalActionExecutionError.applyFailed(apply.output)
        }
        return L10n.resolvedEnglish
            ? "Patch applied to \(root.lastPathComponent). Changes are unstaged; no commit or push was performed."
            : "补丁已应用到 \(root.lastPathComponent)。改动尚未提交，也未推送。"
    }

    private static func validatePatchPaths(_ data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let forbidden = [
            "diff --git a/.git/",
            "diff --git a/.git ",
            "--- a/.git/",
            "+++ b/.git/",
            "rename from .git/",
            "rename to .git/"
        ]
        guard !forbidden.contains(where: { text.contains($0) }) else {
            throw ExternalActionExecutionError.unsafePatchPath
        }
    }

    private static func runGit(repository: URL, arguments: [String]) -> GitRunResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repository.path] + arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "LC_ALL": "C",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0"
        ]
        do {
            try process.run()
        } catch {
            return .init(status: -1, output: error.localizedDescription)
        }
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.025)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data.prefix(64_000), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(status: process.terminationStatus, output: output)
    }
}

private struct GitRunResult {
    var status: Int32
    var output: String
}

enum ExternalActionExecutionError: Error, LocalizedError {
    case wrongActionKind
    case invalidRepository
    case notGitRepository(String)
    case unsafePatchPath
    case patchCheckFailed(String)
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .wrongActionKind:
            return L10n.resolvedEnglish ? "This is not a Git patch request." : "这不是 Git 补丁请求。"
        case .invalidRepository:
            return L10n.resolvedEnglish ? "Choose an accessible repository folder." : "请选择可访问的 Git 仓库文件夹。"
        case .notGitRepository(let output):
            return L10n.resolvedEnglish
                ? "The selected folder is not a Git repository. \(output)"
                : "所选文件夹不是 Git 仓库。\(output)"
        case .unsafePatchPath:
            return L10n.resolvedEnglish
                ? "The patch attempts to modify Git metadata and was rejected."
                : "补丁尝试修改 Git 元数据，已拒绝执行。"
        case .patchCheckFailed(let output):
            return L10n.resolvedEnglish
                ? "The patch does not apply cleanly. \(output)"
                : "补丁无法干净应用。\(output)"
        case .applyFailed(let output):
            return L10n.resolvedEnglish
                ? "Git could not apply the patch. \(output)"
                : "Git 无法应用补丁。\(output)"
        }
    }
}
