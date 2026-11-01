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
    /// "Jess" with a capital J (founder, 2026-10-23), whatever name the catalog sends (the server's
    /// listing still says "jess"; its test changes only through test-guardian).
    static let displayName = "Jess"

    static func isJess(_ sidekick: SidekickEntry) -> Bool {
        sidekick.id == id
    }
}

/// Press and hold on a tile, like removing an app on iOS (founder, 2026-10-31): the tiles jiggle,
/// every Sidekick but jess, Make and the Inbox gets a minus badge, the minus opens C3. "Done" at
/// the top right or a tap on the empty grid ends it. The home screen owns this state and hands it
/// to the grid through the environment.
@MainActor
@Observable
final class HomeArrangement {
    private(set) var isArranging = false
    /// Opens a Sidekick's page (every tile but jess's).
    @ObservationIgnored var openSidekick: @MainActor (SidekickEntry) -> Void = HomeArrangement.ignoreSidekick
    /// The minus: C3 for this Sidekick.
    @ObservationIgnored var askDelete: @MainActor (SidekickEntry) -> Void = HomeArrangement.ignoreSidekick

    private static func ignoreSidekick(_ sidekick: SidekickEntry) {}

    func startArranging() {
        guard !isArranging else {
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isArranging = true
    }

    func stopArranging() {
        isArranging = false
    }

    /// A tap on a tile: opens it, or does nothing while the tiles jiggle (as on iOS).
    func tapped(_ sidekick: SidekickEntry, openJess: () -> Void) {
        if isArranging {
            return
        }
        if JessSidekick.isJess(sidekick) {
            openJess()
        } else {
            openSidekick(sidekick)
        }
    }

    /// The minus badge shows only while arranging, and never on jess, Make or the Inbox.
    func showsMinus(on sidekick: SidekickEntry) -> Bool {
        isArranging && SidekickDeletion.canDelete(sidekick)
    }
}

struct SidekickHomeGrid: View {
    let entries: [SidekickEntry]
    var onOpenJess: () -> Void = {}
    /// R2 (Make, founder 2026-10-23): the grid reports where each tile sits, and keeps a newly
    /// built Sidekick's slot empty while its tile moves in. Nil: neither.
    @Environment(MakeBuiltStage.self) private var builtStage: MakeBuiltStage?
    /// Press and hold to delete. Nil (previews, tests): tiles open on tap only.
    @Environment(HomeArrangement.self) private var arrangement: HomeArrangement?

    private var columns: [GridItem] {
        let column = GridItem(.flexible(), spacing: 8, alignment: .top)
        return Array(repeating: column, count: SidekickHomeLayout.columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 22) {
            // Make after jess in a DEBUG build before the server lists it (MakeSidekick)
            let tiles = MakeSidekick.listedEntries(SidekickHomeLayout.tiles(from: entries))
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, sidekick in
                tile(for: sidekick, index: index)
            }
        }
        .padding(.horizontal, 20)
    }

    /// jess opens its Listening screen; every other tile (Make and the Inbox included, which open
    /// their own native screens) pushes its Sidekick. A long press starts arranging.
    @ViewBuilder
    private func tile(for sidekick: SidekickEntry, index: Int) -> some View {
        let isArranging = arrangement?.isArranging ?? false
        let showsMinus = arrangement?.showsMinus(on: sidekick) ?? false
        SidekickHomeTile(sidekick: sidekick, isHidden: builtStage?.hidesTile(sidekick.id) ?? false, onIconFrame: slotRecorder(for: sidekick.id), onDelete: showsMinus ? deleteAction(for: sidekick) : nil)
            .modifier(HomeTileJiggle(isOn: isArranging, index: index))
            .contentShape(Rectangle())
            .onTapGesture(perform: tapAction(for: sidekick))
            .onLongPressGesture(minimumDuration: 0.5, perform: startArranging)
            .accessibilityAddTraits(.isButton)
            .accessibilityActions {
                // VoiceOver reaches the minus as an action of the tile
                if showsMinus {
                    Button(SettingsCopy.deleteSidekickLabel(sidekick.name), action: deleteAction(for: sidekick))
                }
            }
    }

    private func tapAction(for sidekick: SidekickEntry) -> () -> Void {
        func tap() {
            guard let arrangement else {
                if JessSidekick.isJess(sidekick) {
                    onOpenJess()
                }
                return
            }
            arrangement.tapped(sidekick, openJess: onOpenJess)
        }
        return tap
    }

    private func deleteAction(for sidekick: SidekickEntry) -> () -> Void {
        func askDelete() {
            arrangement?.askDelete(sidekick)
        }
        return askDelete
    }

    private func startArranging() {
        arrangement?.startArranging()
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
    /// While the tiles jiggle: the minus badge at the icon's top left, and what it does.
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            icon
                .onGeometryChange(for: CGRect.self, of: Self.globalFrame, action: reportIconFrame)
                .opacity(isHidden ? 0 : 1)
                .overlay(alignment: .topLeading) {
                    if let onDelete {
                        HomeTileMinusBadge(sidekickName: sidekick.name, action: onDelete)
                            // The badge's centre sits on the icon's corner; 8 pt of the target pads it
                            .offset(x: -(HomeTileMinusBadge.diameter / 2 + 8) + 4, y: -(HomeTileMinusBadge.diameter / 2 + 8) + 4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
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
    /// is the written "Make" (K1 until the founder picks the tile). SidekickTileIcon draws both.
    private var icon: some View {
        SidekickTileIcon(sidekick: sidekick, size: SidekickHomeLayout.iconSize)
    }
}

struct JessTileIcon: View {
    /// The asset: "Jess" in Caveat Bold, ink on paper with a dark variant, shared with every other
    /// place jess's icon shows (SidekickIcon.swift, `JessTileArtwork`).
    static let imageName = JessTileArtwork.imageName

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
    /// (`shell/icon-source/make-tile.py`). The tile pick (K5-K7 open) swaps this one asset, shared
    /// with every other place Make's icon shows (SidekickIcon.swift, `MakeTileArtwork`).
    static let imageName = MakeTileArtwork.imageName

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
