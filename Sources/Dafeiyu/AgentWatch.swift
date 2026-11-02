import Darwin

/// Summed CPU share of local coding agents (processes named `claude` or `codex`).
/// Reads only process names and CPU time; the pet's own quota helper is excluded.
final class AgentCPU {
    private var previous: [pid_t: UInt64] = [:]
    private var previousTime: Double?
    private let nanosecondsPerTick: Double = {
        var base = mach_timebase_info_data_t(); mach_timebase_info(&base)
        return Double(base.numer) / Double(base.denom)
    }()
    /// Percent of one core used by agents since the previous call (0 on the first call).
    func sample(now: Double) -> Double {
        var pids = [pid_t](repeating: 0, count: 8192)
        let count = Int(proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.stride * pids.count)))
        let me = getpid()
        var seen: [pid_t: UInt64] = [:]
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            var name = [CChar](repeating: 0, count: 64)
            guard proc_name(pid, &name, 64) > 0 else { continue }
            let process = String(cString: name)
            guard process == "claude" || process == "codex" else { continue }
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
                  info.pbi_ppid != UInt32(me) else { continue }
            var usage = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            if ok == 0 { seen[pid] = usage.ri_user_time + usage.ri_system_time }
        }
        defer { previous = seen; previousTime = now }
        guard let last = previousTime, now > last else { return 0 }
        var ticks: UInt64 = 0
        for (pid, time) in seen { if let before = previous[pid], time >= before { ticks += time - before } }
        return Double(ticks) * nanosecondsPerTick / 1e9 / (now - last) * 100
    }
}
