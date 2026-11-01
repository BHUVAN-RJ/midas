import SwiftUI

// Work log entries are links (founder, 2026-10-31; docs/mockups/jess-worklog-links-2026-10-31.html):
// a tap on a done card pushes its Sidekick over jess, a normal push from the right. A swipe in from
// the left edge goes back one level: the Sidekick to jess, then jess to Midas's home. jess still
// opens as it does today (the tile, the Action button); it carries its own navigation stack so the
// Sidekick goes back to jess, not to the home grid.

/// A Sidekick opened from a Workdesk card.
struct JessOpenedSidekick: Hashable {
    let entry: SidekickEntry
    /// The record was deleted since: "Already Deleted" over the page.
    let isGone: Bool
    /// Each tap is its own push, even of the same Sidekick.
    let tapId: UUID
}

/// How a left-edge swipe on jess goes home (the same thresholds as iOS's back swipe).
enum JessEdgeSwipe {
    /// Only a drag that starts this close to the left edge.
    static let edgeWidth: Double = 22
    /// Past this share of the width, or flicked past half of it, it goes home.
    static let commitShare: Double = 0.35
    static let flickShare: Double = 0.5
    static let settle = Animation.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.3)

    static func goesHome(translation: Double, predicted: Double, width: Double) -> Bool {
        translation > width * commitShare || predicted > width * flickShare
    }
}

/// jess's screen with its own stack: the Workdesk, then the Sidekicks its cards open.
struct JessScreen: View {
    let flow: VoiceReminderFlow
    let results: JessResults
    var directory: SidekickDirectory = ShellServices.shared.directory
    var store: LocalRecordStore = ShellServices.shared.store
    var storeChannel: SidekickStoreChannel = ShellServices.shared.storeChannel

    @State private var path: [JessOpenedSidekick] = []
    /// How far the edge swipe has moved jess to the right.
    @State private var edgeOffset: Double = 0

    var body: some View {
        GeometryReader { geometry in
            NavigationStack(path: $path) {
                VoiceCaptureView(flow: flow, results: results, onOpen: open)
                    // No repair on jess (founder, 2026-10-23): X2 above the orb, and the try logged
                    .repairUnavailableSwipe(sidekickId: JessSidekick.id, toastBottom: RepairUnavailableSpec.jessToastBottom)
                    .toolbar(.hidden, for: .navigationBar)
                    .overlay(alignment: .leading) {
                        edgeStrip(width: geometry.size.width)
                    }
                    .navigationDestination(for: JessOpenedSidekick.self, destination: sidekickScreen)
            }
            .offset(x: edgeOffset)
            .shadow(color: Color.black.opacity(edgeOffset > 0 ? 0.14 : 0), radius: 14, x: -6)
        }
        // Midas's home shows behind jess while it is swiped away
        .presentationBackground(.clear)
    }

    private func sidekickScreen(_ opened: JessOpenedSidekick) -> some View {
        SidekickScreen(sidekick: opened.entry, notice: opened.isGone ? JessLinkCopy.alreadyDeleted : nil)
    }

    /// A Workdesk card's Sidekick, at its change. A Sidekick no longer listed opens nothing.
    private func open(_ card: JessResultCard) {
        guard let link = card.link, let entry = directory.entry(withId: link.sidekickId) else {
            return
        }
        guard flow.prepareToOpenSidekick() else {
            return
        }
        let recordStore = store
        let sidekickId = link.sidekickId
        func currentValue(_ key: String) -> JSONValue? {
            recordStore.get(sidekickId: sidekickId, key: key)
        }
        let target = link.target(currentValue: currentValue)
        storeChannel.setFocus(target.focus, sidekickId: sidekickId)
        path.append(JessOpenedSidekick(entry: entry, isGone: target.isGone, tapId: UUID()))
    }

    /// The left edge of the Workdesk: swiped right, jess slides off to Midas's home.
    private func edgeStrip(width: Double) -> some View {
        Color.clear
            .frame(width: JessEdgeSwipe.edgeWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .global).onChanged(followEdge).onEnded(finishEdgeSwipe(width: width)))
    }

    private func followEdge(_ value: DragGesture.Value) {
        edgeOffset = max(value.translation.width, 0)
    }

    private func finishEdgeSwipe(width: Double) -> (DragGesture.Value) -> Void {
        let voiceFlow = flow
        func finish(_ value: DragGesture.Value) {
            let goesHome = JessEdgeSwipe.goesHome(translation: value.translation.width, predicted: value.predictedEndTranslation.width, width: width)
            guard goesHome else {
                withAnimation(JessEdgeSwipe.settle) {
                    edgeOffset = 0
                }
                return
            }
            withAnimation(JessEdgeSwipe.settle) {
                edgeOffset = width
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.3))
                // Off screen already: the cover leaves without its slide down
                var noAnimation = Transaction()
                noAnimation.disablesAnimations = true
                withTransaction(noAnimation) {
                    voiceFlow.cancel()
                }
            }
        }
        return finish
    }
}

/// "Already Deleted": an ink pill over the bottom of the page, for 2.5 s.
struct JessLinkNotice: View {
    let words: String

    static let shownFor: Duration = .seconds(2.5)

    @State private var isShown = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(words)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .padding(.vertical, 11)
            .padding(.horizontal, 18)
            .background(Capsule().fill(colorScheme == .dark ? Color.white : Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)))
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : 12)
            .padding(.bottom, 46)
            .allowsHitTesting(false)
            .task {
                withAnimation(.easeOut(duration: 0.22)) {
                    isShown = true
                }
                try? await Task.sleep(for: Self.shownFor)
                withAnimation(.easeOut(duration: 0.22)) {
                    isShown = false
                }
            }
    }
}
