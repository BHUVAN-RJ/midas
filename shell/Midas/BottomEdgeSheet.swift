import SwiftUI

// A short sheet that comes up from the bottom edge (founder, 2026-11-02, build 22 feedback: Make's
// "Built by Hand" sheet "doesn't look like it's coming from the bottom but rather like a square
// just hanging"). On iOS 26 a system sheet at a partial height floats above the bottom with all
// four corners rounded. This one sits on the bottom edge: top corners rounded, the page dimmed
// behind it, swipe down or tap the dimmed page to close. Used by Make's first-open sheet, the
// Third-Party Services ask and C3 "Delete <Sidekick>?".

enum BottomEdgeSheetSpec {
    static let cornerRadius: CGFloat = 30
    static let dimOpacity: Double = 0.4
    /// Dragged down this far, or flung this far, the sheet closes.
    static let closeDistance: CGFloat = 100
    static let flingDistance: CGFloat = 220
    static let grabberWidth: CGFloat = 36
    static let grabberHeight: CGFloat = 5
    static let comeUp = Animation.spring(response: 0.38, dampingFraction: 0.9)
    static let goDown = Animation.easeIn(duration: 0.22)

    /// Light: paper. Dark: paper-2, so the sheet shows on the dimmed black page (DESIGN.md 2.4).
    static func background(_ scheme: ColorScheme) -> JessOrbColor {
        scheme == .dark ? RepairTokens.dark.paper2 : RepairTokens.light.paper
    }

    /// Whether a drag down that ended here closes the sheet.
    static func closes(translation: CGFloat, predicted: CGFloat) -> Bool {
        translation >= closeDistance || predicted >= flingDistance
    }
}

/// The dimmed page and the sheet on the bottom edge. It slides up when shown and down before it
/// goes; `onGone` runs once it is off screen.
private struct BottomEdgePanel<Content: View>: View {
    @Binding var isPresented: Bool
    let onGone: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isUp = false
    @State private var dragDown: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .opacity(isUp ? BottomEdgeSheetSpec.dimOpacity : 0)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            if isUp {
                panel
                    .offset(y: dragDown)
                    .transition(.move(edge: .bottom))
            }
        }
        .onAppear(perform: comeUp)
        .onChange(of: isPresented, goDownWhenClosed)
    }

    private var panel: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        let shape = UnevenRoundedRectangle(topLeadingRadius: BottomEdgeSheetSpec.cornerRadius, topTrailingRadius: BottomEdgeSheetSpec.cornerRadius, style: .continuous)
        return VStack(spacing: 0) {
            Capsule()
                .fill(tokens.ink3.color)
                .frame(width: BottomEdgeSheetSpec.grabberWidth, height: BottomEdgeSheetSpec.grabberHeight)
                .padding(.top, 8)
            content()
                .padding(.bottom, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        // Down to the screen's bottom edge, under the home indicator
        .background {
            shape
                .fill(BottomEdgeSheetSpec.background(colorScheme).color)
                .ignoresSafeArea(edges: .bottom)
        }
        .gesture(DragGesture(minimumDistance: 8).onChanged(follow).onEnded(finishDrag))
    }

    private func comeUp() {
        withAnimation(BottomEdgeSheetSpec.comeUp) {
            isUp = true
        }
    }

    private func close() {
        isPresented = false
    }

    private func goDownWhenClosed(_ wasPresented: Bool, _ nowPresented: Bool) {
        guard !nowPresented else {
            return
        }
        withAnimation(BottomEdgeSheetSpec.goDown, completionCriteria: .logicallyComplete, goDown, completion: onGone)
    }

    private func goDown() {
        isUp = false
    }

    private func follow(_ value: DragGesture.Value) {
        dragDown = max(value.translation.height, 0)
    }

    private func finishDrag(_ value: DragGesture.Value) {
        if BottomEdgeSheetSpec.closes(translation: value.translation.height, predicted: value.predictedEndTranslation.height) {
            close()
            return
        }
        withAnimation(BottomEdgeSheetSpec.comeUp) {
            dragDown = 0
        }
    }
}

/// Presents the panel over everything (a full-screen cover with a clear background, shown without
/// the system slide so only the sheet moves).
private struct BottomEdgeSheetModifier<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    @ViewBuilder let panel: () -> Panel

    @State private var isCoverUp = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isCoverUp, onDismiss: coverGone) {
                BottomEdgePanel(isPresented: $isPresented, onGone: takeCoverDown, content: panel)
                    .presentationBackground(.clear)
            }
            .onChange(of: isPresented, initial: true, putCoverUpWhenShown)
    }

    private func putCoverUpWhenShown(_ wasPresented: Bool, _ nowPresented: Bool) {
        guard nowPresented, !isCoverUp else {
            return
        }
        setCoverWithoutSlide(true)
    }

    private func takeCoverDown() {
        setCoverWithoutSlide(false)
    }

    private func setCoverWithoutSlide(_ isUp: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        func change() {
            isCoverUp = isUp
        }
        withTransaction(transaction, change)
    }

    private func coverGone() {
        // Closed from outside while the cover was going (e.g. signing out): keep the binding true to it
        if isPresented {
            isPresented = false
        }
        onDismiss?()
    }
}

/// The item version keeps the last item, so the sheet's content stays while it slides down.
private struct BottomEdgeItemSheetModifier<Item: Identifiable, Panel: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder let panel: (Item) -> Panel

    @State private var shownItem: Item?

    func body(content: Content) -> some View {
        content
            .bottomEdgeSheet(isPresented: isPresentedBinding, content: panelForShownItem)
            .onChange(of: item?.id, initial: true, keepShownItem)
    }

    private var isPresentedBinding: Binding<Bool> {
        Binding(get: readIsPresented, set: writeIsPresented)
    }

    private func readIsPresented() -> Bool {
        item != nil
    }

    private func writeIsPresented(_ isPresented: Bool) {
        if !isPresented {
            item = nil
        }
    }

    private func keepShownItem(_ oldId: Item.ID?, _ newId: Item.ID?) {
        if let item {
            shownItem = item
        }
    }

    @ViewBuilder
    private func panelForShownItem() -> some View {
        if let shownItem {
            panel(shownItem)
        }
    }
}

extension View {
    /// A short sheet on the bottom edge (BottomEdgeSheet.swift).
    func bottomEdgeSheet<Panel: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Panel) -> some View {
        modifier(BottomEdgeSheetModifier(isPresented: isPresented, onDismiss: onDismiss, panel: content))
    }

    func bottomEdgeSheet<Item: Identifiable, Panel: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Panel) -> some View {
        modifier(BottomEdgeItemSheetModifier(item: item, panel: content))
    }
}
