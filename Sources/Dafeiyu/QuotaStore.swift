import Foundation
import AppKit
import Combine
import DafeiyuCore

struct ProviderStatus {
    var snapshot: QuotaSnapshot?
    var loading = false
    var error: String?
    var lastAttempt: Date?
    var title: String { snapshot?.provider == "claude" ? "Claude" : "Codex" }
}

@MainActor final class QuotaStore: ObservableObject {
    @Published var providers: [String: ProviderStatus] = ["claude": .init(), "codex": .init()]
    @Published var isRefreshing = false
    @Published var history = QuotaHistory()
    private let model: AppModel
    private var timer: Timer?
    private var task: Task<Void, Never>?
    // Each provider backs off on its own: a lapsed Claude login must not slow the Codex bowl.
    private var failures: [String: Int] = [:]
    private var receipts = QuotaReceipts()
    private var sleeping = false
    private var observerTokens: [NSObjectProtocol] = []
    private var generation = 0
    private var stopped = false
    var onReset: (() -> Void)?
    var notify: ((String, String) -> Void)?
    let disabled: Bool
    private let readProvider: (String) async throws -> QuotaSnapshot
    init(model: AppModel, disabled: Bool,
         readProvider: @escaping (String) async throws -> QuotaSnapshot = { try await DirectQuotaReader.read(provider: $0) }) {
        self.model = model; self.disabled = disabled
        self.readProvider = readProvider
        if let data = try? Data(contentsOf: model.directory.appendingPathComponent("quota-history.json")), let loaded = try? JSONDecoder().decode(QuotaHistory.self, from: data) { history = loaded }
        if let data = try? Data(contentsOf: model.directory.appendingPathComponent("quota-receipts.json")), let loaded = try? JSONDecoder().decode(QuotaReceipts.self, from: data) { receipts = loaded }
        for provider in ["claude", "codex"] {
            if let data = try? Data(contentsOf: model.directory.appendingPathComponent("quota-\(provider).json")),
               let cached = try? JSONDecoder().decode(QuotaSnapshot.self, from: data), cached.provider == provider {
                providers[provider]?.snapshot = cached
                providers[provider]?.error = "上次保存的数据，正在等待更新。"
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observerTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.sleeping = true; self?.timer?.invalidate() } })
        observerTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.sleeping = false; self?.schedule(after: 20) } })
        schedule()
    }
    func settingsChanged() {
        schedule()
    }
    private func interval(_ provider: String) -> Double {
        Double(model.preferences.refreshMinutes * 60) * pow(2, Double(min(3, failures[provider] ?? 0)))
    }
    /// Wake up when the first enabled provider is due; `after` forces an earlier check (system wake).
    func schedule(after override: Double? = nil) {
        timer?.invalidate()
        guard !disabled, !sleeping, !stopped, model.preferences.refreshMinutes > 0 else { return }
        let due = enabledProviders.map { (providers[$0]?.lastAttempt ?? .distantPast).addingTimeInterval(interval($0)).timeIntervalSinceNow }
        let delay = override ?? max(10, due.min() ?? interval("codex"))
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.refresh(scheduled: true) } }
        timer?.tolerance = min(15, delay * 0.05)
    }
    func refreshIfStale() {
        guard model.preferences.refreshOnOpen else { return }
        let age = Double(max(2, model.preferences.refreshMinutes) * 60)
        let enabled = enabledProviders
        if enabled.contains(where: { Date().timeIntervalSince(providers[$0]?.snapshot?.fetchedAt ?? .distantPast) > age }) { refresh() }
    }
    private var enabledProviders: [String] {
        [model.preferences.claudeEnabled ? "claude" : nil, model.preferences.codexEnabled ? "codex" : nil].compactMap { $0 }
    }
    func refresh(scheduled: Bool = false) {
        guard !disabled, !sleeping, !stopped, !isRefreshing else { return }
        // A timer only reads providers that are due; opening the card reads any not tried in 10 s.
        let enabled = enabledProviders.filter { Date().timeIntervalSince(providers[$0]?.lastAttempt ?? .distantPast) >= (scheduled ? interval($0) - 20 : 10) }
        guard !enabled.isEmpty else { if scheduled { schedule() }; return }
        generation += 1; let requestGeneration = generation
        isRefreshing = true
        task = Task { [weak self] in
            guard let self else { return }
            for provider in enabled {
                if Task.isCancelled || sleeping || stopped { break }
                guard enabledProviders.contains(provider) else { continue }
                providers[provider]?.loading = true; providers[provider]?.lastAttempt = Date()
                defer { providers[provider]?.loading = false }
                do {
                    let snapshot = try await readProvider(provider)
                    guard requestGeneration == generation, enabledProviders.contains(provider) else { continue }
                    providers[provider] = .init(snapshot: snapshot, loading: false, error: nil, lastAttempt: Date()); failures[provider] = 0
                    try? FileManager.default.createDirectory(at: model.directory, withIntermediateDirectories: true)
                    history.record(snapshot)
                    try? JSONEncoder().encode(history).write(to: model.directory.appendingPathComponent("quota-history.json"), options: .atomic)
                    let event = receipts.observe(snapshot, threshold: model.preferences.lowQuotaThreshold)
                    if event.reset {
                        onReset?()
                        if model.preferences.resetReminder { notify?("额度已更新", "\(provider == "claude" ? "Claude" : "Codex") 已进入新的额度窗口。") }
                    }
                    if event.low && model.preferences.lowQuotaReminder { notify?("额度快用完了", "\(provider == "claude" ? "Claude" : "Codex") 有窗口剩余低于 \(Int(model.preferences.lowQuotaThreshold))%。") }
                    try? FileManager.default.createDirectory(at: model.directory, withIntermediateDirectories: true)
                    try? JSONEncoder().encode(snapshot).write(to: model.directory.appendingPathComponent("quota-\(provider).json"), options: .atomic)
                    try? JSONEncoder().encode(receipts).write(to: model.directory.appendingPathComponent("quota-receipts.json"), options: .atomic)
                } catch {
                    guard requestGeneration == generation, !Task.isCancelled, enabledProviders.contains(provider) else { continue }
                    failures[provider, default: 0] += 1; providers[provider]?.error = error.localizedDescription; providers[provider]?.loading = false
                }
            }
            guard requestGeneration == generation, !stopped else { return }
            isRefreshing = false; schedule()
        }
    }
    func stop() {
        stopped = true; generation += 1; task?.cancel(); task = nil; timer?.invalidate(); timer = nil
        isRefreshing = false
        for provider in providers.keys { providers[provider]?.loading = false }
        for token in observerTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        observerTokens.removeAll(); DirectQuotaReader.cancelAll()
    }
}
