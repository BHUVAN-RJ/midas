import Observation
import SwiftUI
import UIKit

// No repair on Make, the Inbox or jess (founder, 2026-10-23, docs/briefs/make.md): the three-finger
// swipe there plays X2 (docs/mockups/make-2026-10-23.html, Confirmed): a Volt rim flash and the
// toast "Repair not available for this Sidekick.", and logs the try (`POST /repairs/blocked`, fire
// and forget) so the founder sees how many people want repair there.

/// X2's numbers, from the mockup: the rim flashes in 900 ms (full at 30%), the toast shows for
/// 2.6 s (in by 14%, out from 85%). Inset 4 pt, radius 52 pt, 3 pt Volt with a 12 pt glow; on
/// white a 1.5 pt ink line round it.
enum RepairUnavailableSpec {
    static let rimSeconds = 0.9
    static let toastSeconds = 2.6
    static let rimInset: CGFloat = 4
    static let rimCornerRadius: CGFloat = 52
    static let rimWidth: CGFloat = 3
    static let rimGlow: CGFloat = 12
    static let rimKeyline: CGFloat = 1.5
    /// Above Make's pill; jess's screen puts it above the orb.
    static let toastBottom: CGFloat = 130
    static let jessToastBottom: CGFloat = 330

    /// 0 → 1 over the first 30%, then back to 0.
    static func rimOpacity(at seconds: Double) -> Double {
        guard seconds >= 0, seconds < rimSeconds else {
            return 0
        }
        let progress = seconds / rimSeconds
        if progress < 0.3 {
            return progress / 0.3
        }
        return 1 - (progress - 0.3) / 0.7
    }

    /// In over the first 14%, out over the last 15%.
    static func toastOpacity(at seconds: Double) -> Double {
        guard seconds >= 0, seconds < toastSeconds else {
            return 0
        }
        let progress = seconds / toastSeconds
        if progress < 0.14 {
            return progress / 0.14
        }
        if progress > 0.85 {
            return max(0, 1 - (progress - 0.85) / 0.15)
        }
        return 1
    }
}

/// `POST /repairs/blocked` (contract section 6): who tried, on which Sidekick, from which build.
/// A new client id per try; the server keeps each id once.
struct RepairBlockedLog: Sendable {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    struct Body: Codable, Equatable {
        let sidekickId: String
        let clientId: String
        let appVersion: String?
        let appBuild: String?
    }

    static func request(platformOrigin: URL, token: String?, body: Body) throws -> URLRequest {
        var request = URLRequest(url: platformOrigin.appending(path: "repairs/blocked"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    @MainActor
    static func body(sidekickId: String, device: RepairDeviceInfo = .current()) -> Body {
        Body(sidekickId: sidekickId, clientId: MakeIds.new(), appVersion: device.appVersion, appBuild: device.appBuild)
    }

    /// Sent once; any answer (a 404 before the server has the route included) is ignored.
    func send(_ body: Body) async {
        guard let token = sessionToken(), let request = try? Self.request(platformOrigin: platformOrigin, token: token, body: body) else {
            return
        }
        _ = try? await session.data(for: request)
    }
}

/// One screen's X2: when the flash started; drawn from that by the overlay.
@MainActor
@Observable
final class RepairUnavailableFlash {
    private(set) var startedAt: Date?
    @ObservationIgnored var log: (@MainActor (String) -> Void)?
    @ObservationIgnored var haptic: @MainActor () -> Void = RepairHaptics.lock

    /// The swipe fired: flash, tap the phone, log the try.
    func play(sidekickId: String, now: Date = Date()) {
        startedAt = now
        haptic()
        log?(sidekickId)
        let duration = max(RepairUnavailableSpec.rimSeconds, RepairUnavailableSpec.toastSeconds)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            self?.finish(startedAt: now)
        }
    }

    func finish(startedAt: Date) {
        guard self.startedAt == startedAt else {
            return
        }
        self.startedAt = nil
    }

    var isShowing: Bool {
        startedAt != nil
    }

    func secondsIn(at date: Date) -> Double {
        guard let startedAt else {
            return -1
        }
        return date.timeIntervalSince(startedAt)
    }
}

/// The live log: the shell's session and server, fire and forget.
@MainActor
enum RepairUnavailableLogging {
    static func live(sidekickId: String) {
        let log = RepairBlockedLog(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        let body = RepairBlockedLog.body(sidekickId: sidekickId)
        Task {
            await log.send(body)
        }
    }
}

private struct RepairUnavailableSwipeModifier: ViewModifier {
    let sidekickId: String
    let toastBottom: CGFloat
    @State private var flash = RepairUnavailableFlash()

    func body(content: Content) -> some View {
        content
            .background {
                RepairUnavailableSwipeInstaller(onSwipe: swiped)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .overlay {
                if flash.isShowing {
                    TimelineView(.animation) { timeline in
                        RepairUnavailableOverlay(seconds: flash.secondsIn(at: timeline.date), toastBottom: toastBottom)
                    }
                    .allowsHitTesting(false)
                }
            }
    }

    private func swiped() {
        if flash.log == nil {
            flash.log = RepairUnavailableLogging.live
        }
        flash.play(sidekickId: sidekickId)
    }
}

/// X2 over the screen: the Volt rim and the toast.
struct RepairUnavailableOverlay: View {
    let seconds: Double
    let toastBottom: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        let shape = RoundedRectangle(cornerRadius: RepairUnavailableSpec.rimCornerRadius, style: .continuous)
        let volt = RepairVolt.color.color
        ZStack(alignment: .bottom) {
            ZStack {
                if RepairRimSpec.hasKeyline(for: colorScheme) {
                    shape
                        .stroke(RepairVolt.ink.color, lineWidth: RepairUnavailableSpec.rimWidth + RepairUnavailableSpec.rimKeyline * 2)
                }
                shape
                    .stroke(volt, lineWidth: RepairUnavailableSpec.rimWidth)
                    .shadow(color: volt, radius: RepairUnavailableSpec.rimGlow / 2)
            }
            .padding(RepairUnavailableSpec.rimInset)
            .opacity(RepairUnavailableSpec.rimOpacity(at: seconds))
            .ignoresSafeArea()
            toast(tokens)
                .padding(.bottom, toastBottom)
                .opacity(RepairUnavailableSpec.toastOpacity(at: seconds))
                .ignoresSafeArea()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MakeCopy.notAvailable())
    }

    private func toast(_ tokens: RepairTokens) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.system(size: 15, weight: .semibold))
            Text(MakeCopy.notAvailable())
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tokens.ink.color)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? JessOrbColor(hex: 0x2A2A2A).color : tokens.paper2.color, in: Capsule())
        .shadow(color: tokens.shadow.color, radius: 10, y: 6)
        .padding(.horizontal, 16)
    }
}

/// Puts a passive `ThreeFingerSwipeRecognizer` on the screen this view sits in: the root view of
/// the nearest view controller (a pushed screen or a full-screen cover each have their own), so
/// the swipe is caught anywhere on that screen and nowhere else. Passive: taps, scrolls and the
/// text field work as before.
struct RepairUnavailableSwipeInstaller: UIViewRepresentable {
    let onSwipe: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipe: onSwipe)
    }

    func makeUIView(context: Context) -> ProbeView {
        let probe = ProbeView()
        probe.coordinator = context.coordinator
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ probe: ProbeView, context: Context) {
        context.coordinator.onSwipe = onSwipe
    }

    static func dismantleUIView(_ probe: ProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSwipe: () -> Void
        private(set) var recognizer: ThreeFingerSwipeRecognizer?
        private weak var host: UIView?

        init(onSwipe: @escaping () -> Void) {
            self.onSwipe = onSwipe
        }

        func attach(to host: UIView) {
            guard self.host !== host else {
                return
            }
            detach()
            let recognizer = ThreeFingerSwipeRecognizer(target: self, action: #selector(swiped(_:)))
            host.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
            self.host = host
        }

        func detach() {
            if let recognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            host = nil
        }

        @objc func swiped(_ recognizer: ThreeFingerSwipeRecognizer) {
            guard recognizer.state == .recognized else {
                return
            }
            onSwipe()
        }
    }

    /// Finds its screen once it is in a window.
    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let host = Self.screenView(above: self) else {
                return
            }
            coordinator?.attach(to: host)
        }

        /// The root view of the nearest view controller up the chain (not a navigation or tab
        /// container, whose view would hold other screens too).
        static func screenView(above view: UIView) -> UIView? {
            var current: UIView? = view.superview
            while let candidate = current {
                if let controller = candidate.next as? UIViewController, !(controller is UINavigationController), !(controller is UITabBarController) {
                    return candidate
                }
                current = candidate.superview
            }
            return nil
        }
    }
}

extension View {
    /// The three-finger swipe on a built-in Sidekick's screen: X2 and the log, no repair.
    func repairUnavailableSwipe(sidekickId: String, toastBottom: CGFloat = RepairUnavailableSpec.toastBottom) -> some View {
        modifier(RepairUnavailableSwipeModifier(sidekickId: sidekickId, toastBottom: toastBottom))
    }
}
