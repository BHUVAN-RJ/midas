import SwiftUI

// Swipe sideways to delete (founder, 2026-10-31, docs/briefs/build-22-2026-10-31.md): a home card
// or a Workdesk card follows the finger sideways and, let go far or fast enough, slides off the
// screen and is gone; otherwise it springs back. Either direction, as iOS's own cards do.

enum CardSwipeDelete {
    /// Dragged this far sideways, or flung to here, the card goes.
    static let distance: CGFloat = 100
    static let flingDistance: CGFloat = 220
    /// The card slides this far out before it is removed.
    static let offscreen: CGFloat = 500
    static let slideOut = Animation.easeIn(duration: 0.22)
    static let springBack = Animation.spring(response: 0.3, dampingFraction: 0.8)

    enum Decision: Equatable {
        /// Off to the right (+1) or the left (-1).
        case delete(direction: CGFloat)
        case springBack
    }

    /// A drag counts only once it is more sideways than up or down.
    static func isSideways(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height)
    }

    static func decision(translation: CGSize, predicted: CGSize) -> Decision {
        guard isSideways(translation) else {
            return .springBack
        }
        let farEnough = abs(translation.width) >= distance
        let flungFar = abs(predicted.width) >= flingDistance && (predicted.width > 0) == (translation.width > 0)
        guard farEnough || flungFar else {
            return .springBack
        }
        return .delete(direction: translation.width >= 0 ? 1 : -1)
    }
}

/// The swipe on one card: follows the finger sideways, then deletes or springs back.
struct CardSwipeDeleteModifier: ViewModifier {
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(1 - min(Double(abs(offset)) / Double(CardSwipeDelete.offscreen), 0.6))
            .gesture(DragGesture(minimumDistance: 12).onChanged(follow).onEnded(finish))
            .accessibilityAction(named: Text(CardSwipeDeleteCopy.delete), onDelete)
    }

    private func follow(_ value: DragGesture.Value) {
        guard CardSwipeDelete.isSideways(value.translation) else {
            return
        }
        offset = value.translation.width
    }

    private func finish(_ value: DragGesture.Value) {
        let decision = CardSwipeDelete.decision(translation: value.translation, predicted: value.predictedEndTranslation)
        switch decision {
        case .delete(let direction):
            withAnimation(CardSwipeDelete.slideOut) {
                offset = direction * CardSwipeDelete.offscreen
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.22))
                onDelete()
                offset = 0
            }
        case .springBack:
            withAnimation(CardSwipeDelete.springBack) {
                offset = 0
            }
        }
    }
}

enum CardSwipeDeleteCopy {
    static let delete = "Delete"
}

extension View {
    /// Swipe sideways to delete this card.
    func swipeSidewaysToDelete(_ onDelete: @escaping () -> Void) -> some View {
        modifier(CardSwipeDeleteModifier(onDelete: onDelete))
    }
}
