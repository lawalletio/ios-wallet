import Lottie
import SwiftUI

/// withdraw/claim-celebration.tsx + treasure-chest.tsx: the chest wobbles while the claim is charging, then opens,
/// sprays coins and counts the sats into the balance.
struct ClaimCelebration: View {
    let charging: Bool
    let amountSats: Int
    let settled: Bool
    /// Balance captured when Withdraw was tapped (nil if unknown).
    let snapshot: Int?
    let liveBalance: Int?
    let onDone: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var locked: (before: Int?, after: Int?)?
    @State private var opened = false
    @State private var landed = false
    @State private var counted = 0.0
    @State private var wobble = false

    private static let amber = Color(hex: "fde68a")
    private static let gold = LinearGradient(colors: [Color(hex: "fef3c7"), Color(hex: "fbbf24"), Color(hex: "d97706")],
                                             startPoint: .top, endPoint: .bottom)

    var body: some View {
        let celebrate = !charging
        let before = locked?.before
        let final = reduced || landed
        ZStack {
            Color(hex: "070604").ignoresSafeArea()
            atmosphere(glow: celebrate && opened)

            ZStack {
                chest(play: celebrate && !reduced)
                    .rotationEffect(.degrees(!celebrate && !reduced && wobble ? 2.5 : 0))
                    .animation(celebrate ? .default : .easeInOut(duration: 0.18).repeatForever(), value: wobble)
                if celebrate && opened && !reduced { CoinBurst() }
            }
            .offset(y: -96)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                HStack {
                    Button(action: celebrate ? onDone : onDismiss) {
                        Icon("x").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(t(celebrate ? "common.close" : "common.back"))
                    .accessibilityIdentifier("withdraw.close")
                    Spacer()
                }
                .foregroundStyle(Self.amber.opacity(0.8))
                .padding(.horizontal, 12).padding(.top, 4)

                VStack(spacing: 8) {
                    Text(t(celebrate ? "withdraw.celebration.eyebrowClaimed" : "withdraw.celebration.eyebrowClaiming").uppercased())
                        .font(LW.font(10, .semibold)).tracking(3.2).foregroundStyle(Self.amber.opacity(0.7))
                    Text(t(celebrate ? (settled ? "withdraw.celebration.won" : "withdraw.celebration.onItsWay") : "withdraw.celebration.opening"))
                        .font(LW.font(30, .semibold)).foregroundStyle(Color(hex: "fffbeb"))
                        .accessibilityIdentifier("withdraw.celebration.title")
                    if !(celebrate && settled) {
                        Text(celebrate ? t("withdraw.celebration.pendingBody")
                                       : t("withdraw.celebration.calling", ["amount": amountSats.formatted()]))
                            .font(LW.font(14)).foregroundStyle(Self.amber.opacity(0.6)).multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }
                }
                .opacity(celebrate && !reduced && !opened ? 0 : 1)
                .padding(.horizontal, 20)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("+" + Int(final ? Double(amountSats) : counted).formatted())
                        .font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Self.gold)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text("sats").font(LW.font(18, .medium)).foregroundStyle(Self.amber.opacity(0.8))
                }
                .scaleEffect(landed && !reduced ? 1.08 : 1)
                .animation(.spring(duration: 0.4, bounce: 0.5), value: landed)
                .opacity(celebrate && (reduced || opened) ? 1 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(t(settled ? "withdraw.celebration.srLanded" : "withdraw.celebration.srOnTheWay", ["amount": amountSats.formatted()]))
                .padding(.bottom, 8)

                balanceCard(celebrate: celebrate, before: before, final: final)

                Group {
                    if celebrate {
                        Button(t("withdraw.celebration.collect"), action: onDone)
                            .font(LW.font(16, .semibold))
                            .foregroundStyle(Color(hex: "451a03"))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(LinearGradient(colors: [Color(hex: "fcd34d"), Color(hex: "f59e0b")], startPoint: .top, endPoint: .bottom))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: Color(hex: "fbbf24").opacity(0.5), radius: 16, y: 8)
                            .accessibilityIdentifier("withdraw.done")
                    } else {
                        Text(t("withdraw.celebration.listening").uppercased())
                            .font(LW.font(12)).tracking(2.6).foregroundStyle(Self.amber.opacity(0.5))
                            .opacity(wobble ? 0.4 : 1)
                            .animation(.easeInOut(duration: 1).repeatForever(), value: wobble)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { wobble = true }
        .onChange(of: charging, initial: true) { _, isCharging in
            guard !isCharging, locked == nil else { return }
            locked = Self.balances(snapshot: snapshot, live: liveBalance, amount: amountSats, settled: settled)
            Task { await run() }
        }
    }

    /// Chest opens ~1.2 s in, the count runs ~2.4 s, then lands with a haptic.
    private func run() async {
        guard !reduced else { landed = true; Haptics.success(); return }
        try? await Task.sleep(for: .seconds(1.2))
        withAnimation(.easeOut(duration: 0.5)) { opened = true }
        // ~2.4 s ease-out count, written per frame like the web's rAF loop.
        let steps = 60
        for i in 1...steps {
            try? await Task.sleep(for: .milliseconds(40))
            let p = Double(i) / Double(steps)
            counted = Double(amountSats) * (1 - pow(1 - p, 3))
        }
        landed = true
        Haptics.success()
    }

    // MARK: pieces

    private func chest(play: Bool) -> some View {
        LottieView { try await DotLottieFile.named("treasure-chest") }
            .playbackMode(play ? .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)) : .paused(at: .progress(0)))
            .animationSpeed(1.3)
            .resizable()
            .frame(width: 560, height: 560)
            .allowsHitTesting(false)
            .accessibilityLabel(t("withdraw.celebration.chest"))
    }

    private func atmosphere(glow: Bool) -> some View {
        ZStack {
            RadialGradient(colors: [Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255).opacity(0.16), .clear],
                           center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color(red: 1, green: 186 / 255, blue: 72 / 255).opacity(0.12), .clear],
                           center: .bottom, startRadius: 0, endRadius: 300)
            RadialGradient(colors: [Color(red: 1, green: 214 / 255, blue: 107 / 255).opacity(0.22), .clear],
                           center: UnitPoint(x: 0.5, y: 0.34), startRadius: 0, endRadius: 260)
                .opacity(glow ? 1 : 0)
                .animation(.easeInOut(duration: 0.7), value: glow)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func balanceCard(celebrate: Bool, before: Int?, final: Bool) -> some View {
        let after = locked?.after
        let shown: Int? = !celebrate ? liveBalance : before.map { b in final ? (after ?? b) : b + (settled ? Int(counted) : 0) }
        let hasBase = celebrate ? before != nil : liveBalance != nil
        let share = hasBase ? Self.pourShare(before ?? 0, amountSats) : 1
        let filled = celebrate && settled ? (final ? 1 : (amountSats > 0 ? counted / Double(amountSats) : 0)) : (celebrate && final ? 1 : 0)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(t("withdraw.celebration.balance").uppercased()).font(LW.font(10, .semibold)).tracking(2.2)
                    .foregroundStyle(Self.amber.opacity(0.6))
                Spacer()
                if !celebrate {
                    Text(t("withdraw.celebration.holding")).font(LW.font(12)).foregroundStyle(Self.amber.opacity(0.7))
                } else if !settled {
                    Text(t("withdraw.celebration.pending")).font(LW.font(12)).foregroundStyle(Self.amber.opacity(0.7))
                } else if final {
                    Text("+\(amountSats.formatted()) sats").font(LW.font(12, .semibold)).foregroundStyle(Color(hex: "fde68a"))
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Color(hex: "fcd34d").opacity(0.15)).clipShape(Capsule())
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(shown.map { $0.formatted() } ?? t("withdraw.celebration.syncing"))
                    .font(LW.font(24, .semibold)).monospacedDigit().foregroundStyle(Color(hex: "fffbeb"))
                    .accessibilityIdentifier("withdraw.celebration.balance")
                Text("sats").font(LW.font(14)).foregroundStyle(Self.amber.opacity(0.6))
            }
            GeometryReader { geo in
                let w = geo.size.width - 6
                HStack(spacing: 3) {
                    if hasBase && share < 1 {
                        Capsule().fill(Color(hex: "78716c").opacity(0.5)).frame(width: max(0, w * (1 - share) - 3))
                    }
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.04))
                        Capsule().fill(LinearGradient(colors: [Color(hex: "f59e0b"), Color(hex: "fde68a")], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, w * share * filled))
                            .opacity(settled ? 1 : 0.55)
                    }
                }
                .padding(3)
            }
            .frame(height: 16)
            .background(Color.black.opacity(0.4)).clipShape(Capsule())
            .accessibilityLabel(t("withdraw.celebration.meter"))
            if celebrate, let before {
                HStack {
                    Text(t("withdraw.celebration.before", ["amount": before.formatted()]))
                    Spacer()
                    Text(t("withdraw.celebration.claimed", ["amount": amountSats.formatted()])).foregroundStyle(Self.amber.opacity(0.8))
                }
                .font(LW.font(11)).monospacedDigit().foregroundStyle(Self.amber.opacity(0.5))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color(hex: final && settled && celebrate ? "fcd34d" : "fde68a").opacity(final && settled && celebrate ? 0.4 : 0.15)))
    }

    // MARK: math (resolveClaimBalances / claimPourShare)

    static func balances(snapshot: Int?, live: Int?, amount: Int, settled: Bool) -> (before: Int?, after: Int?) {
        let before: Int?
        if let snapshot { before = max(0, snapshot) }
        else if let live, settled, live >= amount { before = live - amount }
        else { before = live.map { max(0, $0) } }
        guard let before else { return (nil, nil) }
        return (before, settled ? before + amount : before)
    }

    static func pourShare(_ before: Int, _ added: Int) -> Double {
        guard added > 0 else { return 0 }
        guard before > 0 else { return 1 }
        return min(0.78, max(Double(added) / Double(before + added), 0.26))
    }
}

/// 22 coins sprayed up from the chest, then falling (fixed spray so every run looks the same).
private struct CoinBurst: View {
    @State private var go = false
    var body: some View {
        ZStack {
            ForEach(0..<22, id: \.self) { i in
                let jitter = sin(Double(i) * 12.9898) * 0.5 + 0.5
                let angle = (-90 + (jitter - 0.5) * 150) * .pi / 180
                let dist = 150 + Double((i * 37) % 120)
                let size = CGFloat(14 + (i * 7) % 12)
                let delay = Double(i % 11) * 0.08 + Double(i / 11) * 0.45
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "fef3c7"), Color(hex: "f59e0b")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(Color(hex: "b45309"), lineWidth: 1.5))
                    .frame(width: size, height: size)
                    .rotation3DEffect(.degrees(go ? Double((i % 2 == 0 ? -1 : 1) * (240 + (i * 71) % 300)) : 0), axis: (x: 0, y: 1, z: 0))
                    .offset(x: go ? cos(angle) * dist : 0, y: go ? sin(angle) * dist + Double(360 + (i * 53) % 140) : 0)
                    .opacity(go ? 0 : 1)
                    .animation(.timingCurve(0.2, 0.6, 0.4, 1, duration: 1.35 + Double((i * 13) % 50) / 100).delay(delay), value: go)
            }
        }
        .offset(y: 16)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { go = true }
    }
}
