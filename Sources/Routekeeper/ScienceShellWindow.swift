import AppKit
import GuardCore
import WebKit

enum ScienceShellError: LocalizedError {
    case loginURLTimeout
    case contentRulesUnavailable

    var errorDescription: String? {
        switch self {
        case .loginURLTimeout:
            return "等待 Claude Science 本地窗口地址超时。"
        case .contentRulesUnavailable:
            return "无法建立 Claude Science 窗口的 WebKit 网络白名单。"
        }
    }
}

/// Captures the Science CLI output, removes single-use secrets before writing
/// session diagnostics, and exposes only the loopback login URL to the app.
actor ScienceProcessLog {
    let pipe = Pipe()

    private let logHandle: FileHandle
    private var buffer = Data()
    private var loginURL: URL?

    init(logURL: URL) throws {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try FileHandle(forWritingTo: logURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: logURL.path
        )
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            Task { await self.ingest(data) }
        }
    }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        let remaining = pipe.fileHandleForReading.availableData
        if !remaining.isEmpty {
            ingest(remaining)
        }
        flushBuffer()
        try? logHandle.close()
    }

    func waitForLoginURL(timeout: TimeInterval = 30) async throws -> URL {
        let attempts = max(1, Int(timeout / 0.1))
        for _ in 0..<attempts {
            if let loginURL { return loginURL }
            try await Task.sleep(for: .milliseconds(100))
        }
        if let loginURL { return loginURL }
        throw ScienceShellError.loginURLTimeout
    }

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            appendLine(String(decoding: line, as: UTF8.self))
        }
        if buffer.count > 64 * 1024 {
            flushBuffer()
        }
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }
        let text = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        if ScienceWebBoundary.loginURL(in: text) != nil {
            loginURL = ScienceWebBoundary.loginURL(in: text)
        }
        writeLogLine(ScienceWebBoundary.redactSecrets(in: text))
    }

    private func appendLine(_ line: String) {
        if loginURL == nil {
            loginURL = ScienceWebBoundary.loginURL(in: line)
        }
        writeLogLine(ScienceWebBoundary.redactSecrets(in: line) + "\n")
    }

    private func writeLogLine(_ line: String) {
        try? logHandle.write(contentsOf: Data(line.utf8))
    }
}

@MainActor
final class ScienceShellWindowController: NSWindowController, NSWindowDelegate,
    WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private let webView: WKWebView
    private let exchangeURL: URL
    private let statusLabel: NSTextField
    private let progress: NSProgressIndicator
    private var allowedPorts: Set<Int>
    private var boundaryGeneration = 0
    private var didAutoSignIn = false
    private var suppressCloseCallback = false
    private var progressObservation: NSKeyValueObservation?

    var onClose: ((ScienceShellWindowController) -> Void)?

    static func present(
        loginURL: URL,
        ports: Set<Int>,
        exchangeURL: URL
    ) async throws -> ScienceShellWindowController {
        let controller = try await ScienceShellWindowController(
            loginURL: loginURL,
            ports: ports,
            exchangeURL: exchangeURL
        )
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return controller
    }

    private init(loginURL: URL, ports: Set<Int>, exchangeURL: URL) async throws {
        self.exchangeURL = exchangeURL
        allowedPorts = ports

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = true
        let rules = try await Self.compileContentRules(ports: ports)
        configuration.userContentController.add(rules)

        webView = WKWebView(frame: .zero, configuration: configuration)
        statusLabel = NSTextField(labelWithString: "正在连接本机服务…")
        progress = NSProgressIndicator()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Science · Routekeeper"
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        super.init(window: window)

        window.delegate = self
        configureContent()
        configureWebView(loginURL: loginURL)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAllowedPorts(_ ports: Set<Int>) {
        let valid = ports.filter { (1...65535).contains($0) }
        guard !valid.isEmpty, valid != allowedPorts else { return }
        boundaryGeneration += 1
        let generation = boundaryGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let rules = try await Self.compileContentRules(ports: valid)
                guard generation == self.boundaryGeneration else { return }
                self.webView.configuration.userContentController.removeAllContentRuleLists()
                self.webView.configuration.userContentController.add(rules)
                self.allowedPorts = valid
            } catch {
                self.statusLabel.stringValue = "更新 WebKit 网络白名单失败：\(error.localizedDescription)"
                self.statusLabel.textColor = .systemOrange
            }
        }
    }

    func closeFromRoutekeeper() {
        suppressCloseCallback = true
        progressObservation?.invalidate()
        webView.stopLoading()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        progressObservation?.invalidate()
        guard !suppressCloseCallback else { return }
        onClose?(self)
    }

    private func configureContent() {
        guard let window else { return }
        let root = NSView()
        let header = NSVisualEffectView()
        header.material = .headerView
        header.blendingMode = .withinWindow
        header.state = .active

        let lock = NSImageView(image: NSImage(
            systemSymbolName: "lock.shield.fill",
            accessibilityDescription: "Sandboxed"
        ) ?? NSImage())
        lock.contentTintColor = .controlAccentColor
        lock.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)

        let title = NSTextField(labelWithString: "Claude Science")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let labels = NSStackView(views: [title, statusLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.isHidden = true
        progress.controlSize = .small
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let reload = makeHeaderButton(
            symbol: "arrow.clockwise",
            toolTip: "重新载入 Science 窗口",
            action: #selector(reloadPage)
        )
        let exchange = makeHeaderButton(
            symbol: "folder",
            toolTip: "在 Finder 中打开交换文件夹",
            action: #selector(openExchange)
        )

        let row = NSStackView(views: [lock, labels, NSView(), progress, reload, exchange])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(row)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.underPageBackgroundColor = .windowBackgroundColor
        root.addSubview(header)
        root.addSubview(webView)
        header.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),
            row.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            row.topAnchor.constraint(equalTo: header.topAnchor),
            row.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        window.contentView = root
    }

    private func makeHeaderButton(
        symbol: String,
        toolTip: String,
        action: Selector
    ) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
            ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.toolTip = toolTip
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func configureWebView(loginURL: URL) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) {
            [weak self] webView, _ in
            Task { @MainActor in
                guard let self else { return }
                self.progress.doubleValue = webView.estimatedProgress
                self.progress.isHidden = webView.estimatedProgress >= 1
            }
        }
        progress.isHidden = false
        webView.load(URLRequest(url: loginURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    private static func compileContentRules(ports: Set<Int>) async throws -> WKContentRuleList {
        guard let encoded = ScienceWebBoundary.contentRuleListJSON(ports: ports) else {
            throw ScienceShellError.contentRulesUnavailable
        }
        let identifier = "RoutekeeperScience-\(ports.sorted().map(String.init).joined(separator: "-"))"
        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: encoded
            ) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(
                        throwing: error ?? ScienceShellError.contentRulesUnavailable
                    )
                }
            }
        }
    }

    @objc private func reloadPage() {
        webView.reload()
    }

    @objc private func openExchange() {
        NSWorkspace.shared.activateFileViewerSelecting([exchangeURL])
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              ScienceWebBoundary.isAllowedNavigation(url, ports: allowedPorts) else {
            statusLabel.stringValue = "已阻止窗口访问本机服务以外的网络地址"
            statusLabel.textColor = .systemOrange
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let url = navigationResponse.response.url,
           url.scheme != nil,
           url.scheme != "about",
           url.scheme != "blob",
           !ScienceWebBoundary.isAllowedNavigation(url, ports: allowedPorts) {
            statusLabel.stringValue = "已阻止响应来自本机服务以外的地址"
            statusLabel.textColor = .systemOrange
            decisionHandler(.cancel)
            return
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        progress.isHidden = false
            statusLabel.stringValue = "正在连接本机服务…"
        statusLabel.textColor = .secondaryLabelColor
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progress.isHidden = true
            statusLabel.stringValue = "隔离窗口仅允许访问本机服务端口"
        statusLabel.textColor = .secondaryLabelColor
        guard !didAutoSignIn else { return }
        let script = """
        (() => {
          const form = document.querySelector('#op-signin form');
          if (!form || form.dataset.routekeeperSubmitted === '1') return false;
          form.dataset.routekeeperSubmitted = '1';
          if (typeof form.requestSubmit === 'function') form.requestSubmit();
          else form.submit();
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            guard let self, (value as? Bool) == true else { return }
            self.didAutoSignIn = true
            self.statusLabel.stringValue = "正在完成本机服务登录…"
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        showLoadFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        showLoadFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        statusLabel.stringValue = "Science 窗口进程已退出，可点刷新重新载入"
        statusLabel.textColor = .systemOrange
    }

    private func showLoadFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        progress.isHidden = true
        statusLabel.stringValue = "窗口载入失败：\(error.localizedDescription)"
        statusLabel.textColor = .systemOrange
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        statusLabel.stringValue = "已阻止 Science 打开的额外浏览窗口"
        statusLabel.textColor = .systemOrange
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Claude Science"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window!) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Claude Science"
        alert.informativeText = message
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window!) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let input = NSTextField(string: defaultText ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        let alert = NSAlert()
        alert.messageText = "Claude Science"
        alert.informativeText = prompt
        alert.accessoryView = input
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window!) { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let name = ScienceWebBoundary.safeDownloadName(suggestedFilename)
        completionHandler(uniqueDestination(for: name))
    }

    func downloadDidFinish(_ download: WKDownload) {
        statusLabel.stringValue = "下载已保存到本会话交换文件夹"
        statusLabel.textColor = .secondaryLabelColor
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        statusLabel.stringValue = "下载失败：\(error.localizedDescription)"
        statusLabel.textColor = .systemOrange
    }

    private func uniqueDestination(for filename: String) -> URL {
        let base = URL(fileURLWithPath: filename)
        let stem = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        var candidate = exchangeURL.appendingPathComponent(filename)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = index == 1 ? " copy" : " copy \(index)"
            let name = stem + suffix + (ext.isEmpty ? "" : "." + ext)
            candidate = exchangeURL.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}
