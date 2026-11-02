import Foundation
import DafeiyuCore

// Read-only providers. No conversations, model requests, credits purchases, or token writes.
enum DirectQuotaReader {
    static let lock = NSLock()
    private static var running: [Process] = []
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static var codexExecutable: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                "/Applications/Codex.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", home + "/.local/bin/codex"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func cancelAll() {
        lock.lock(); let items = running; lock.unlock()
        items.filter(\.isRunning).forEach { $0.terminate() }
    }
    private static func track(_ process: Process) { lock.lock(); running.append(process); lock.unlock() }
    private static func untrack(_ process: Process) { lock.lock(); running.removeAll { $0 === process }; lock.unlock() }
    private static func watchdog(_ process: Process, seconds: Double) -> DispatchWorkItem {
        let work = DispatchWorkItem {
            guard process.isRunning else { return }; process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: work); return work
    }
    static func read(provider: String) async throws -> QuotaSnapshot {
        if provider == "codex" { return try await Task.detached(priority: .utility) { try codex() }.value }
        let credentials = try await Task.detached(priority: .utility) { try claudeAccess() }.value
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer " + credentials.token, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Dafeiyu/" + version, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 18
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config, delegate: NoQuotaRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw QuotaFailure.invalid }
        switch response.statusCode {
        case 200: return try QuotaParser.parseClaude(data, account: credentials.account)
        case 401, 403: throw QuotaFailure.unavailable("Claude 登录已失效或缺少额度权限。打开一次 Claude Code 让它续期（仍不行就在其中运行 /login），再回来刷新。")
        case 429: throw QuotaFailure.unavailable("Claude 暂时限制查询频率，稍后会自动重试。")
        default: throw QuotaFailure.unavailable("Claude 额度服务暂时不可用（\(response.statusCode)）。")
        }
    }
    private static func claudeAccess() throws -> (token: String, account: String?) {
        // The system utility honors Keychain access controls. Its output never leaves this function.
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); track(process)
        let timeout = watchdog(process, seconds: 15)
        defer { timeout.cancel(); untrack(process) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw QuotaFailure.unavailable("未能读取 Claude 登录。请先在 Claude Code 登录，并允许系统钥匙串访问。")
        }
        // Claude Code renews its short-lived token only while it runs. Never renew it here:
        // that would rotate the user's stored login. Report the lapse without a network call.
        if let expires = oauth["expiresAt"] as? Double, expires / 1000 < Date().timeIntervalSince1970 {
            let when = Date(timeIntervalSince1970: expires / 1000).formatted(.dateTime.month().day().hour().minute())
            throw QuotaFailure.unavailable("Claude Code 的登录已于 \(when) 过期。打开一次 Claude Code 让它自动续期（仍不行就在其中运行 /login），再回来刷新。")
        }
        // Account identity separates reminder history. No login token is persisted.
        let profileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        let profile = (try? Data(contentsOf: profileURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let account = (profile?["oauthAccount"] as? [String: Any])?["emailAddress"] as? String
        return (token, account)
    }
    private static func codex() throws -> QuotaSnapshot {
        guard let path = codexExecutable else { throw QuotaFailure.unavailable("未找到 Codex。请安装 Codex 或 Codex CLI 并登录。") }
        let process = Process(); let input = Pipe(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = ["app-server"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run(); track(process)
        let timeout = watchdog(process, seconds: 20)
        defer {
            timeout.cancel(); try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            untrack(process)
        }
        var buffer = Data()
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func receive(_ id: Int) throws -> [String: Any] {
            while true {
                while let end = buffer.firstIndex(of: 10) {
                    let line = buffer[..<end]; buffer.removeSubrange(...end)
                    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], object["id"] as? Int == id else { continue }
                    guard object["error"] == nil, let result = object["result"] as? [String: Any] else {
                        throw QuotaFailure.unavailable("Codex 暂未提供额度，请确认本机 Codex 已登录。")
                    }
                    return result
                }
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty else { throw QuotaFailure.unavailable("Codex 额度查询超时或连接已结束。") }
                buffer.append(chunk); guard buffer.count < 1_048_576 else { throw QuotaFailure.invalid }
            }
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "dafeiyu", "version": version], "capabilities": ["experimentalApi": false]]])
        _ = try receive(1); try send(["method": "initialized"])
        try send(["id": 2, "method": "account/read", "params": ["refreshToken": false]])
        let accountResult = try receive(2)
        let account = (accountResult["account"] as? [String: Any])?["email"] as? String
        try send(["id": 3, "method": "account/rateLimits/read"])
        return try QuotaParser.parseCodex(JSONSerialization.data(withJSONObject: receive(3)), account: account)
    }
}

private final class NoQuotaRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
