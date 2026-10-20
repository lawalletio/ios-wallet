import AVFoundation
import BackgroundTasks
import LaWalletKit
import UIKit
import UserNotifications

/// Local notifications for incoming payments. Live while the app runs (NIP-47 notifications),
/// plus a best-effort BGAppRefresh poll of `list_transactions` when suspended. No APNs.
enum Notifier {
    static let refreshTaskId = "io.lawallet.wallet.refresh"
    private static let lastSeenKey = "lawallet-last-seen-incoming"

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    @MainActor static func notifyIncoming(sats: Int, description: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSeenKey)
        guard UIApplication.shared.applicationState != .active else { return }
        post(sats: sats, description: description)
    }

    static func post(sats: Int, description: String) {
        let c = UNMutableNotificationContent()
        c.title = t("ios.notify.received", ["sats": sats.formatted()])
        c.body = description.isEmpty ? t("ios.notify.body") : description
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: nil) { bgTask in
            schedule()
            let box = TaskBox(task: bgTask)
            let work = Task.detached {
                await pollIncoming()
                box.task.setTaskCompleted(success: true)
            }
            bgTask.expirationHandler = { work.cancel() }
        }
    }

    private final class TaskBox: @unchecked Sendable {
        let task: BGTask
        init(task: BGTask) { self.task = task }
    }

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    /// Notifies for incoming payments settled since the last one we saw.
    static func pollIncoming() async {
        guard let uri = Keychain.get("nwc-uri"), let client = try? NWCClient(uri: uri) else { return }
        let since = UserDefaults.standard.double(forKey: lastSeenKey)
        let from = since > 0 ? Date(timeIntervalSince1970: since) : Date(timeIntervalSinceNow: -3600)
        guard let txs = try? await client.listTransactions(limit: 10, from: from, type: .incoming) else { return }
        let fresh = txs.filter { $0.state == .settled && ($0.settledAt ?? $0.createdAt) > from }
        for tx in fresh { post(sats: tx.amountSats, description: tx.description) }
        if let newest = fresh.map({ ($0.settledAt ?? $0.createdAt).timeIntervalSince1970 }).max() {
            UserDefaults.standard.set(newest, forKey: lastSeenKey)
        }
    }
}

/// Payment sounds (`payment-sound.ts`): `chime` (synthesized), `bananero` (bundled mp3), `off`.
@MainActor
enum SoundPlayer {
    private static var player: AVAudioPlayer?

    static func play(_ sound: String) {
        let data: Data?
        switch sound {
        case "chime": data = chimeData
        case "bananero": data = Bundle.main.url(forResource: "sapeee-el-bananero", withExtension: "mp3").flatMap { try? Data(contentsOf: $0) }
        default: return
        }
        guard let data else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        player = try? AVAudioPlayer(data: data)
        player?.play()
    }

    private static let chimeData = chime()

    /// Two-note sine chime (E6 → A6) rendered as a 16-bit WAV.
    static func chime() -> Data {
        let rate = 44_100.0
        var samples: [Int16] = []
        for (freq, dur) in [(1318.5, 0.12), (1760.0, 0.32)] {
            let n = Int(rate * dur)
            for i in 0..<n {
                let env = exp(-4.5 * Double(i) / Double(n))
                samples.append(Int16(sin(2 * .pi * freq * Double(i) / rate) * env * 0.35 * Double(Int16.max)))
            }
        }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        samples.forEach { withUnsafeBytes(of: $0.littleEndian) { d.append(contentsOf: $0) } }
        return d
    }
}
