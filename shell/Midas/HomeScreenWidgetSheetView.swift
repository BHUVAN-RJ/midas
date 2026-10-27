import SwiftUI

// The "Add to Home Screen" sheet, ported from docs/mockups/widget-howto-demo-2026-10-25.html
// (demo B in Midas style, founder 2026-10-25/26): ink on paper, colour only from the Sidekicks,
// one ink pill and one ink ring as the spotlight, eased slides and fades. No springs, gradients,
// blur reveals or confetti. Every frame is drawn from the time alone, as the mockup's renderDemo.

/// Everything the sheet draws that comes from the person's phone, worked out once when it opens.
struct HomeScreenDemoContent {
    let variant: HomeScreenWidgetVariant
    /// One look per gallery page, in gallery order (each kind, each size).
    let galleryLooks: [HomeScreenWidgetLook]
    /// The small widget that lands on the Home Screen.
    let placedLook: HomeScreenWidgetLook
    let iconHexes: [String]
    let dockHexes: [String]

    static func make(request: HomeScreenWidgetRequest, file: SharedSidekickWidgets?, entries: [SidekickEntry], now: Date) -> HomeScreenDemoContent {
        var personalHexes: [String] = []
        var askingEntry: SidekickEntry?
        for entry in entries {
            personalHexes.append(entry.backgroundHex)
            if entry.id == request.sidekickId {
                askingEntry = entry
            }
        }
        var galleryLooks: [HomeScreenWidgetLook] = []
        for kind in HomeScreenDemoGallery.kinds {
            for size in kind.sizes {
                let look = HomeScreenWidgetLooks.look(of: kind.variant, sidekickId: request.sidekickId, size: size.family, file: file,
                                                      entry: askingEntry, personalHexes: personalHexes, at: now)
                galleryLooks.append(look)
            }
        }
        let placedLook = HomeScreenWidgetLooks.look(of: request.variant, sidekickId: request.sidekickId, size: .small, file: file,
                                                    entry: askingEntry, personalHexes: personalHexes, at: now)
        let palette = HomeScreenDemoColors.palette(personalHexes: personalHexes)
        return HomeScreenDemoContent(variant: request.variant, galleryLooks: galleryLooks, placedLook: placedLook,
                                     iconHexes: HomeScreenDemoColors.iconHexes(palette: palette),
                                     dockHexes: HomeScreenDemoColors.dockHexes(palette: palette))
    }
}

/// The shell palette (docs/DESIGN.md 2.1, dark 2.4) and the mockup's sheet tokens.
struct HomeScreenDemoInk {
    let colorScheme: ColorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var paper: Color { isDark ? Self.hex(0x111111) : Self.hex(0xFFFFFF) }
    var ink: Color { isDark ? Self.hex(0xFFFFFF) : Self.hex(0x111111) }
    var ink2: Color { isDark ? Self.hex(0xA3A3A3) : Self.hex(0x6B6B6B) }
    var ink3: Color { isDark ? Self.hex(0x5C5C5C) : Self.hex(0xBDBDBD) }
    var rule: Color { isDark ? Color.white.opacity(0.14) : Self.hex(0x111111).opacity(0.12) }
    var fill: Color { isDark ? Color.white.opacity(0.08) : Self.hex(0x111111).opacity(0.06) }
    var wall: Color { isDark ? Self.hex(0x1C1C1C) : Self.hex(0xE9E6DF) }
    var shadow: Color { isDark ? Color.black.opacity(0.5) : Self.hex(0x111111).opacity(0.14) }
    var dock: Color { isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.45) }
    var dockEdge: Color { isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.6) }
    var fingerBody: Color { isDark ? Self.hex(0x111111).opacity(0.45) : Color.white.opacity(0.55) }
    var fingerEdge: Color { isDark ? Color.white : Self.hex(0x111111) }

    static func hex(_ packed: UInt32) -> Color {
        Color(red: Double((packed >> 16) & 0xFF) / 255, green: Double((packed >> 8) & 0xFF) / 255, blue: Double(packed & 0xFF) / 255)
    }
}

struct HomeScreenWidgetSheetView: View {
    let content: HomeScreenDemoContent
    /// Holds the demo still at this moment (the simulator screenshots); nil plays it in a loop.
    var frozenTimeMs: Double?
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()

    private var ink: HomeScreenDemoInk {
        HomeScreenDemoInk(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetBar
            switch HomeScreenDemoPresentation.choose(variant: content.variant, reduceMotion: reduceMotion) {
            case .animated(let timeline):
                TimelineView(.animation(paused: frozenTimeMs != nil)) { context in
                    let timeMs = demoTime(at: context.date, length: timeline.length)
                    HomeScreenDemoFrame(content: content, timeline: timeline, timeMs: timeMs, ink: ink)
                }
            case .stillList(let captions):
                HomeScreenDemoStillList(captions: captions, ink: ink)
            }
            Spacer(minLength: 16)
            Button(action: onDone) {
                Text(HomeScreenWidgetCopy.done)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ink.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(ink.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .foregroundStyle(ink.ink)
        .presentationBackground(ink.paper)
        .presentationDetents([.large])
    }

    private var sheetBar: some View {
        ZStack {
            Text(HomeScreenWidgetCopy.title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.17)
                .padding(.horizontal, 60)
            HStack {
                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(ink.fill))
                        .overlay(Circle().strokeBorder(ink.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(HomeScreenWidgetCopy.close)
                Spacer()
            }
        }
        .frame(height: 44)
    }

    private func demoTime(at date: Date, length: Double) -> Double {
        if let frozenTimeMs {
            return frozenTimeMs
        }
        let elapsedMs = date.timeIntervalSince(startDate) * 1000
        return elapsedMs.truncatingRemainder(dividingBy: length)
    }
}

/// With Reduce Motion: the steps, numbered, still.
struct HomeScreenDemoStillList: View {
    let captions: [String]
    let ink: HomeScreenDemoInk

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(captions.enumerated()), id: \.offset) { index, caption in
                HStack(spacing: 14) {
                    Text("\(index + 1)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink.paper)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(ink.ink))
                    Text(caption)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
        .padding(.horizontal, 4)
    }
}

/// One frame: the small Home Screen, the caption and the step dots.
struct HomeScreenDemoFrame: View {
    let content: HomeScreenDemoContent
    let timeline: HomeScreenDemoTimeline
    let timeMs: Double
    let ink: HomeScreenDemoInk

    static let stageHeight: CGFloat = 430

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                HomeScreenDemoStage(content: content, timeline: timeline, timeMs: timeMs, ink: ink, width: proxy.size.width)
            }
            .frame(height: Self.stageHeight)
            .padding(.top, 14)
            Text(timeline.caption(at: timeMs))
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.19)
                .multilineTextAlignment(.center)
                .frame(minHeight: 24)
                .padding(.top, 16)
            HStack(spacing: 7) {
                let currentStep = timeline.stepIndex(at: timeMs)
                ForEach(0..<timeline.steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? ink.ink : ink.ink3)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.top, 10)
        }
    }
}

/// The small Home Screen and everything that slides over it.
struct HomeScreenDemoStage: View {
    let content: HomeScreenDemoContent
    let timeline: HomeScreenDemoTimeline
    let timeMs: Double
    let ink: HomeScreenDemoInk
    let width: CGFloat

    static let cornerRadius: CGFloat = 30
    static let panelInset: CGFloat = 5
    static let panelTop: CGFloat = 30
    static let cardWidth: CGFloat = 312

    private var height: CGFloat {
        HomeScreenDemoFrame.stageHeight
    }

    private var grid: HomeScreenDemoGrid {
        HomeScreenDemoGrid(width: width)
    }

    private var isJiggling: Bool {
        timeMs > timeline.jiggleStart && timeMs < timeline.jiggleEnd
    }

    private var placedIn: Double {
        HomeScreenDemoEasing.progress(timeMs, from: timeline.placed, to: timeline.placed + 500)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ink.wall
            gridIcons
            placedWidget
            dock
            editPills
            menu
            galleryPanel
            pickPanel
            finger
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).strokeBorder(ink.rule, lineWidth: 1))
        .allowsHitTesting(false)
    }

    // MARK: Home Screen

    private var gridIcons: some View {
        ForEach(0..<HomeScreenDemoColors.iconCount, id: \.self) { iconIndex in
            let frame = grid.iconFrame(iconIndex)
            let angle = isJiggling ? sin(timeMs / 70 + Double(iconIndex)) * 2 : 0
            let isCovered = HomeScreenDemoGrid.coveredIcons.contains(iconIndex)
            HomeScreenDemoIcon(hex: content.iconHexes[iconIndex], isMidas: iconIndex == HomeScreenDemoColors.midasIconIndex)
                .rotationEffect(.degrees(angle))
                .opacity(isCovered ? 1 - placedIn : 1)
                .offset(x: frame.minX, y: frame.minY)
        }
    }

    // The placed widget keeps its rounded corners, covers exactly the 2 x 2 icon square and
    // jiggles with the icons, a little less since it is bigger.
    private var placedWidget: some View {
        let frame = grid.placedFrame
        let angle = isJiggling ? sin(timeMs / 70 + 0.5) * 1 : 0
        return HomeScreenDemoWidget(look: content.placedLook, family: .small, width: frame.width, height: frame.height, ink: ink)
            .rotationEffect(.degrees(angle))
            .opacity(placedIn)
            .offset(x: frame.minX, y: frame.minY)
    }

    private var dock: some View {
        HStack {
            ForEach(0..<content.dockHexes.count, id: \.self) { dockIndex in
                Spacer(minLength: 0)
                HomeScreenDemoIcon(hex: content.dockHexes[dockIndex], isMidas: false)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: width - 20, height: 76)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(ink.dock))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(ink.dockEdge, lineWidth: 1))
        .offset(x: 10, y: height - 10 - 76)
    }

    private var editPills: some View {
        let shown = HomeScreenDemoEasing.progress(timeMs, from: timeline.jiggleStart, to: timeline.jiggleStart + 300)
            * (1 - HomeScreenDemoEasing.progress(timeMs, from: timeline.jiggleEnd, to: timeline.jiggleEnd + 200))
        return HStack {
            HomeScreenDemoPill(text: HomeScreenWidgetCopy.edit, ink: ink)
            Spacer()
            HomeScreenDemoPill(text: HomeScreenWidgetCopy.done, ink: ink)
        }
        .frame(width: width - 24)
        .offset(x: 12, y: 10)
        .opacity(shown)
    }

    private var menu: some View {
        let shown = HomeScreenDemoEasing.progress(timeMs, from: timeline.menuOpen, to: timeline.menuOpen + 200)
            * (1 - HomeScreenDemoEasing.progress(timeMs, from: timeline.galleryUp - 100, to: timeline.galleryUp + 50))
        let isAddTapped = timeMs > timeline.menuTap && timeMs < timeline.galleryUp
        return VStack(spacing: 0) {
            HomeScreenDemoMenuRow(text: HomeScreenWidgetCopy.addWidget, symbol: "plus", isOn: isAddTapped, ink: ink)
            HomeScreenDemoMenuRow(text: HomeScreenWidgetCopy.customize, symbol: "circle.lefthalf.filled", isOn: false, ink: ink)
            HomeScreenDemoMenuRow(text: HomeScreenWidgetCopy.editPages, symbol: "square.grid.2x2", isOn: false, ink: ink)
        }
        .padding(6)
        .frame(width: 180)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ink.paper))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(ink.rule, lineWidth: 1))
        .shadow(color: ink.shadow, radius: 15, y: 12)
        .scaleEffect(0.94 + 0.06 * shown, anchor: .topLeading)
        .opacity(shown)
        .offset(x: 12, y: 42)
    }

    // MARK: Gallery and the Midas pages

    private var panelSize: CGSize {
        CGSize(width: width - Self.panelInset * 2, height: height - Self.panelTop - Self.panelInset)
    }

    /// A panel slid `shown` of the way up from below the stage (the mockup's 105%).
    private func panelOffsetY(shown: Double) -> CGFloat {
        Self.panelTop + (1 - shown) * 1.05 * panelSize.height
    }

    private var galleryPanel: some View {
        let shown = HomeScreenDemoEasing.progress(timeMs, from: timeline.galleryUp, to: timeline.galleryUp + 500)
            * (1 - HomeScreenDemoEasing.progress(timeMs, from: timeline.pickUp + 100, to: timeline.pickUp + 400))
        // Point at Midas: the other rows fade, Midas turns ink.
        let focus = HomeScreenDemoEasing.progress(timeMs, from: timeline.midasTap - 600, to: timeline.midasTap - 300)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                Text(HomeScreenWidgetCopy.searchWidgets)
                    .font(.system(size: 13))
            }
            .foregroundStyle(ink.ink2)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
            .background(Capsule().fill(ink.fill))
            VStack(spacing: 3) {
                ForEach(HomeScreenDemoGalleryRow.rows, id: \.name) { row in
                    HomeScreenDemoGalleryRowView(row: row, isFocused: row.isMidas && focus > 0.5, ink: ink)
                        .opacity(row.isMidas ? 1 : 1 - 0.65 * focus)
                }
            }
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .modifier(HomeScreenDemoPanel(size: panelSize, ink: ink))
        .offset(x: Self.panelInset, y: panelOffsetY(shown: shown))
    }

    private var pickPanel: some View {
        let shown = HomeScreenDemoEasing.progress(timeMs, from: timeline.pickUp, to: timeline.pickUp + 400)
            * (1 - HomeScreenDemoEasing.progress(timeMs, from: timeline.placed - 300, to: timeline.placed))
        let position = carouselPosition()
        // Spotlight: once on the target, its name and preview are marked in ink and the rest fades.
        let spot = HomeScreenDemoEasing.progress(timeMs, from: timeline.spotlight, to: timeline.spotlight + 400)
        let isAddPressed = timeMs > timeline.addTap && timeMs < timeline.addTap + 400
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(galleryPages.enumerated()), id: \.offset) { pageIndex, page in
                    let isTarget = page.variant == content.variant
                    HomeScreenDemoCard(page: page, look: content.galleryLooks[pageIndex], isSpotlit: isTarget && spot > 0, ink: ink)
                        .opacity(isTarget ? 1 : 1 - 0.7 * spot)
                }
            }
            .offset(x: -position * Self.cardWidth)
            .frame(width: Self.cardWidth, height: 288, alignment: .topLeading)
            .clipped()
            pageDots(currentPage: Int(position.rounded()))
                .padding(.top, 6)
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text(HomeScreenWidgetCopy.addWidget)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(ink.paper)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(Capsule().fill(ink.ink))
            .opacity(isAddPressed ? 0.6 : 1)
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .modifier(HomeScreenDemoPanel(size: panelSize, ink: ink))
        .offset(x: Self.panelInset, y: panelOffsetY(shown: shown))
    }

    private var galleryPages: [HomeScreenDemoPage] {
        var pages: [HomeScreenDemoPage] = []
        for kind in HomeScreenDemoGallery.kinds {
            for size in kind.sizes {
                pages.append(HomeScreenDemoPage(variant: kind.variant, name: kind.name, description: kind.description, size: size))
            }
        }
        return pages
    }

    private func pageDots(currentPage: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(galleryPages.enumerated()), id: \.offset) { pageIndex, page in
                let isCurrent = pageIndex == currentPage
                let isTargetGroup = page.variant == content.variant
                Circle()
                    .fill(isCurrent ? ink.ink : ink.ink3)
                    .frame(width: 6, height: 6)
                    .opacity(isCurrent || isTargetGroup ? 1 : 0.5)
            }
        }
    }

    /// Which page the carousel shows: one eased swipe per page between swipeStart and swipeEnd.
    private func carouselPosition() -> Double {
        let pagesToPass = timeline.pagesToPass
        if pagesToPass == 0 || timeMs <= timeline.swipeStart {
            return 0
        }
        if timeMs >= timeline.swipeEnd {
            return Double(pagesToPass)
        }
        let perPage = (timeline.swipeEnd - timeline.swipeStart) / Double(pagesToPass)
        let wholePages = floor((timeMs - timeline.swipeStart) / perPage)
        let pageStart = timeline.swipeStart + wholePages * perPage
        return wholePages + HomeScreenDemoEasing.progress(timeMs, from: pageStart, to: pageStart + perPage * 0.8)
    }

    // MARK: Finger

    private var finger: some View {
        let touch = fingerTouch()
        return Circle()
            .fill(ink.fingerBody)
            .overlay(Circle().strokeBorder(ink.fingerEdge, lineWidth: 1.5))
            .shadow(color: ink.shadow, radius: 4, y: 2)
            .frame(width: 34, height: 34)
            .scaleEffect(touch.isPressed ? 0.82 : 1)
            .opacity(touch.isVisible ? 1 : 0)
            .offset(x: touch.point.x - 17, y: touch.point.y - 17)
    }

    /// Where the finger is, as the mockup's renderFinger (points in the stage).
    private func fingerTouch() -> (point: CGPoint, isVisible: Bool, isPressed: Bool) {
        if timeMs < 1800 {
            return (CGPoint(x: 230, y: 280), timeMs > 300, timeMs > 500)
        }
        if timeMs < 2900 {
            return (CGPoint(x: 34, y: 24), timeMs > 2000, timeMs > 2450 && timeMs < 2650)
        }
        if timeMs < timeline.galleryUp + 100 {
            return (CGPoint(x: 84, y: 62), true, timeMs > timeline.menuTap)
        }
        if timeMs < timeline.pickUp + 200 {
            return (CGPoint(x: 120, y: 236), timeMs > timeline.midasTap - 700, timeMs > timeline.midasTap)
        }
        if timeline.pagesToPass > 0 && timeMs < timeline.swipeEnd {
            // Drag right to left, once per page
            let perPage = (timeline.swipeEnd - timeline.swipeStart) / Double(timeline.pagesToPass)
            let inPage = (timeMs - timeline.swipeStart).truncatingRemainder(dividingBy: perPage) / perPage
            let dragX = timeMs < timeline.swipeStart ? 270 : 270 - 190 * min(1, inPage / 0.8)
            return (CGPoint(x: dragX, y: 170), timeMs > timeline.swipeStart - 400, timeMs > timeline.swipeStart && inPage < 0.8)
        }
        if timeMs < timeline.placed - 200 {
            return (CGPoint(x: 181, y: 356), timeMs > timeline.addTap - 700, timeMs > timeline.addTap)
        }
        return (.zero, false, false)
    }
}

/// A sheet over the small Home Screen: the gallery, then Midas's pages.
struct HomeScreenDemoPanel: ViewModifier {
    let size: CGSize
    let ink: HomeScreenDemoInk

    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ink.paper))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(ink.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: ink.shadow, radius: 13, y: -6)
    }
}

/// An app icon on the small Home Screen: a tile colour, or the written Midas icon.
struct HomeScreenDemoIcon: View {
    let hex: String
    let isMidas: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeScreenDemoGrid.iconCorner, style: .continuous)
        Group {
            if isMidas {
                Image(HomeScreenDemoIcon.midasImageName)
                    .resizable()
                    .interpolation(.high)
            } else {
                SidekickColor.color(fromHex: hex)
            }
        }
        .frame(width: HomeScreenDemoGrid.iconSide, height: HomeScreenDemoGrid.iconSide)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: HomeScreenDemoInk.hex(0x111111).opacity(0.12), radius: 1, y: 1)
    }

    /// The app icon, light and dark, small (shell/Midas/Assets.xcassets/MidasTile.imageset).
    static let midasImageName = "MidasTile"
}

struct HomeScreenDemoPill: View {
    let text: String
    let ink: HomeScreenDemoInk

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ink.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .background(Capsule().fill(ink.paper))
            .overlay(Capsule().strokeBorder(ink.rule, lineWidth: 1))
            .shadow(color: ink.shadow, radius: 4, y: 2)
    }
}

struct HomeScreenDemoMenuRow: View {
    let text: String
    let symbol: String
    let isOn: Bool
    let ink: HomeScreenDemoInk

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 14))
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(isOn ? ink.paper : ink.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isOn ? ink.ink : Color.clear))
    }
}

/// A row of the widget gallery's list.
struct HomeScreenDemoGalleryRow {
    let name: String
    let hex: String?

    var isMidas: Bool {
        hex == nil
    }

    static let rows = [
        HomeScreenDemoGalleryRow(name: "Batteries", hex: "#9CAF88"),
        HomeScreenDemoGalleryRow(name: "Calendar", hex: "#FF6347"),
        HomeScreenDemoGalleryRow(name: "Clock", hex: "#2E2E2E"),
        HomeScreenDemoGalleryRow(name: "Midas", hex: nil),
        HomeScreenDemoGalleryRow(name: "Weather", hex: "#30D5C8"),
    ]
}

struct HomeScreenDemoGalleryRowView: View {
    let row: HomeScreenDemoGalleryRow
    let isFocused: Bool
    let ink: HomeScreenDemoInk

    var body: some View {
        HStack(spacing: 11) {
            glyph
            Text(row.name)
                .font(.system(size: 14, weight: isFocused ? .semibold : .regular))
            Spacer(minLength: 0)
        }
        .foregroundStyle(isFocused ? ink.paper : ink.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isFocused ? ink.ink : Color.clear))
    }

    @ViewBuilder
    private var glyph: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if let hex = row.hex {
            shape.fill(SidekickColor.color(fromHex: hex))
                .frame(width: 30, height: 30)
        } else {
            Image(HomeScreenDemoIcon.midasImageName)
                .resizable()
                .frame(width: 30, height: 30)
                .clipShape(shape)
                .overlay(shape.strokeBorder(ink.rule, lineWidth: 1))
        }
    }
}

/// One page of Midas's widgets in the gallery: one kind at one size.
struct HomeScreenDemoPage {
    let variant: HomeScreenWidgetVariant
    let name: String
    let description: String
    let size: HomeScreenDemoGallery.Size
}

struct HomeScreenDemoCard: View {
    let page: HomeScreenDemoPage
    let look: HomeScreenWidgetLook
    let isSpotlit: Bool
    let ink: HomeScreenDemoInk

    var body: some View {
        VStack(spacing: 0) {
            Text(page.name)
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.17)
                .foregroundStyle(isSpotlit ? ink.paper : ink.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(Capsule().fill(isSpotlit ? ink.ink : Color.clear))
            Text(page.description)
                .font(.system(size: 12))
                .foregroundStyle(ink.ink2)
                .padding(.top, 3)
            HomeScreenDemoWidget(look: look, family: page.size.family, width: page.size.width, height: page.size.height, ink: ink)
                // The ink ring: 3 points of paper, then 2 of ink
                .overlay {
                    if isSpotlit {
                        RoundedRectangle(cornerRadius: HomeScreenDemoWidget.cornerRadius + 4, style: .continuous)
                            .strokeBorder(ink.ink, lineWidth: 2)
                            .padding(-5)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 2)
        .frame(width: HomeScreenDemoStage.cardWidth, height: 288, alignment: .top)
    }
}

/// A widget in the demo, with its rounded corners: the Sidekick's real widget drawn small, a plain
/// card in its tile colour, or the Sidekicks folder.
struct HomeScreenDemoWidget: View {
    let look: HomeScreenWidgetLook
    let family: SidekickWidgetSize
    let width: CGFloat
    let height: CGFloat
    let ink: HomeScreenDemoInk

    static let cornerRadius: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Group {
            switch look {
            case .filled(let screen):
                filled(screen)
            case .plain(let name, let tileHex):
                plain(name: name, tileHex: tileHex)
            case .folder(let tileHexes):
                folder(tileHexes)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .shadow(color: HomeScreenDemoInk.hex(0x111111).opacity(0.10), radius: 4, y: 2)
    }

    // The widget at its real size, scaled down whole so it looks exactly as on the Home Screen.
    private func filled(_ screen: SidekickWidgetScreen) -> some View {
        let fullWidth = SidekickWidgetSnapshot.width(of: family)
        let fullHeight = SidekickWidgetSnapshot.height(of: family)
        let scale = min(width / fullWidth, height / fullHeight)
        return SidekickWidgetSnapshot(screen: screen, size: family)
            .scaleEffect(scale, anchor: .center)
            .frame(width: width, height: height)
    }

    private func plain(name: String, tileHex: String) -> some View {
        ZStack(alignment: .topLeading) {
            SidekickColor.color(fromHex: tileHex)
            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HomeScreenDemoWidget.markColor(onTileHex: tileHex))
                .padding(12)
        }
    }

    private func folder(_ tileHexes: [String]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(tileHexes.enumerated()), id: \.offset) { _, hex in
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(SidekickColor.color(fromHex: hex))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ink.paper)
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).strokeBorder(ink.rule, lineWidth: 1))
    }

    /// Ink or paper on a tile colour, whichever contrasts (docs/DESIGN.md 2.3).
    static func markColor(onTileHex tileHex: String) -> Color {
        guard let components = SidekickColor.rgbComponents(fromHex: tileHex) else {
            return HomeScreenDemoInk.hex(0x111111)
        }
        // Relative luminance on linear light; 0.35 splits the eight as the table does (Tomato
        // light, Cherry and Charcoal take paper)
        let luminance = 0.2126 * pow(components.red, 2.2) + 0.7152 * pow(components.green, 2.2) + 0.0722 * pow(components.blue, 2.2)
        return luminance > 0.35 ? HomeScreenDemoInk.hex(0x111111) : HomeScreenDemoInk.hex(0xFFFFFF)
    }
}
