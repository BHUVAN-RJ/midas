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

struct SidekickHomeGrid: View {
    let entries: [SidekickEntry]

    private var columns: [GridItem] {
        let column = GridItem(.flexible(), spacing: 8, alignment: .top)
        return Array(repeating: column, count: SidekickHomeLayout.columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(SidekickHomeLayout.tiles(from: entries)) { sidekick in
                NavigationLink(value: sidekick) {
                    SidekickHomeTile(sidekick: sidekick)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }
}

struct SidekickHomeTile: View {
    let sidekick: SidekickEntry

    var body: some View {
        VStack(spacing: 6) {
            SidekickIconView(content: SidekickIconContent.content(for: sidekick), size: SidekickHomeLayout.iconSize)
            Text(sidekick.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sidekick.name)
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
