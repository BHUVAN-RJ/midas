import SwiftUI
import UIKit

// SidekickArtwork, SidekickIconContent, SidekickIconView and RemindersListIcon live in
// shell/Shared/SidekickIcon.swift (shared with the widget).

/// Layout of the home grid (founder, 2026-10-10): like the iPhone home screen.
enum SidekickHomeLayout {
    static let columnCount = 4
    static let iconSize: CGFloat = 60
    static let cornerRatio: CGFloat = SidekickIconShape.cornerRatio

    /// One tile per Sidekick, in the order the server lists them.
    static func tiles(from entries: [SidekickEntry]) -> [SidekickEntry] {
        return entries
    }
}

/// jess, a Sidekick every user has (founder, 2026-10-22): built into the shell, not a web bundle.
/// Its tile opens the same Listening screen as the Action button; no tools, no repair.
enum JessSidekick {
    static let id = "jess"

    static func isJess(_ sidekick: SidekickEntry) -> Bool {
        sidekick.id == id
    }
}

struct SidekickHomeGrid: View {
    let entries: [SidekickEntry]
    var onOpenJess: () -> Void = {}
    /// R2 (Make, founder 2026-10-23): the grid reports where each tile sits, and keeps a newly
    /// built Sidekick's slot empty while its tile moves in. Nil: neither.
    @Environment(MakeBuiltStage.self) private var builtStage: MakeBuiltStage?

    private var columns: [GridItem] {
        let column = GridItem(.flexible(), spacing: 8, alignment: .top)
        return Array(repeating: column, count: SidekickHomeLayout.columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 22) {
            // Make after jess in a DEBUG build before the server lists it (MakeSidekick)
            ForEach(MakeSidekick.listedEntries(SidekickHomeLayout.tiles(from: entries))) { sidekick in
                tile(for: sidekick)
            }
        }
        .padding(.horizontal, 20)
    }

    /// jess opens its Listening screen; every other tile (Make and the Inbox included, which open
    /// their own native screens) pushes its Sidekick.
    @ViewBuilder
    private func tile(for sidekick: SidekickEntry) -> some View {
        if JessSidekick.isJess(sidekick) {
            Button(action: onOpenJess) {
                SidekickHomeTile(sidekick: sidekick)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: sidekick) {
                SidekickHomeTile(sidekick: sidekick, isHidden: builtStage?.hidesTile(sidekick.id) ?? false, onIconFrame: slotRecorder(for: sidekick.id))
            }
            .buttonStyle(.plain)
        }
    }

    private func slotRecorder(for sidekickId: String) -> ((CGRect) -> Void)? {
        guard let builtStage else {
            return nil
        }
        func record(_ frame: CGRect) {
            builtStage.recordSlot(sidekickId, frame: frame)
        }
        return record
    }
}

struct SidekickHomeTile: View {
    let sidekick: SidekickEntry
    /// While R2's tile moves into this slot: the slot stays empty.
    var isHidden = false
    /// The icon's frame in window points (R2's landing spot).
    var onIconFrame: ((CGRect) -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            icon
                .onGeometryChange(for: CGRect.self, of: Self.globalFrame, action: reportIconFrame)
                .opacity(isHidden ? 0 : 1)
            Text(sidekick.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .opacity(isHidden ? 0 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sidekick.name)
    }

    nonisolated private static func globalFrame(_ proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .global)
    }

    private func reportIconFrame(_ frame: CGRect) {
        onIconFrame?(frame)
    }

    /// jess's tile is the written "Jess", in the Midas icon's hand (founder, 2026-10-22); Make's
    /// is the written "Make" (K1 until the founder picks the tile).
    @ViewBuilder
    private var icon: some View {
        if JessSidekick.isJess(sidekick) {
            JessTileIcon(size: SidekickHomeLayout.iconSize)
        } else if MakeSidekick.isMake(sidekick) {
            MakeTileIcon(size: SidekickHomeLayout.iconSize)
        } else {
            SidekickIconView(content: SidekickIconContent.content(for: sidekick), size: SidekickHomeLayout.iconSize)
        }
    }
}

struct JessTileIcon: View {
    /// The asset: "Jess" in Caveat Bold, ink on paper with a dark variant
    /// (`shell/icon-source/jess-tile.py`, README there).
    static let imageName = "JessTile"

    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * SidekickHomeLayout.cornerRatio, style: .continuous)
        Image(Self.imageName)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

struct MakeTileIcon: View {
    /// The asset: K1, "Make" in Caveat Bold, ink on paper with a dark variant
    /// (`shell/icon-source/make-tile.py`). The tile pick (K5-K7 open) swaps this one asset.
    static let imageName = "MakeTile"

    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * SidekickHomeLayout.cornerRatio, style: .continuous)
        Image(Self.imageName)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Inside a Sidekick there is no back button (founder, 2026-10-10); the left-edge swipe goes home.
enum SidekickSwipeBack {
    /// The swipe only starts when a Sidekick is open on top of the home grid.
    static func shouldBegin(navigationStackDepth: Int) -> Bool {
        return navigationStackDepth > 1
    }
}

/// Hiding the navigation bar also switches off iOS's edge swipe back; this turns it back on for
/// the navigation controller that hosts it.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeCoordinator() -> SwipeBackGestureDelegate {
        SwipeBackGestureDelegate()
    }

    func makeUIViewController(context: Context) -> SwipeBackHostController {
        let controller = SwipeBackHostController()
        controller.gestureDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SwipeBackHostController, context: Context) {}
}

final class SwipeBackHostController: UIViewController {
    var gestureDelegate: SwipeBackGestureDelegate?

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        attachToNavigationController()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachToNavigationController()
    }

    private func attachToNavigationController() {
        guard let navigationController, let gestureDelegate else {
            return
        }
        gestureDelegate.navigationController = navigationController
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
        navigationController.interactivePopGestureRecognizer?.delegate = gestureDelegate
    }
}

final class SwipeBackGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let depth = navigationController?.viewControllers.count ?? 0
        return SidekickSwipeBack.shouldBegin(navigationStackDepth: depth)
    }

    // The edge swipe wins over the Sidekick page's own touches that start at the edge
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer is UIScreenEdgePanGestureRecognizer
    }
}
