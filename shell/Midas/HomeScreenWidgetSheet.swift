import Foundation
import Observation
import SwiftUI

// "Add to Home Screen" (founder, 2026-10-25/26: one sheet for every widget, demo B, Midas style;
// docs/mockups/widget-howto-demo-2026-10-25.html). iOS has no API that places a widget for the
// person, so a Sidekick asks the shell to show the steps as a short animation:
//
//   Sidekick writes  request:<id>  { kind: "home-screen.widget", widget: "sidekick", status: "pending" }
//   shell shows      the sheet, for the Sidekick that wrote the request (its own small widget)
//   shell updates    request:<id>  { status: "done" }, or "failed" for a widget it does not know
//
// A page asks `{ op: "shell" }` on its store first; an older build answers "unknown op shell" and
// the page hides its row (docs/WIDGETS.md, "Add to Home Screen").

extension ShellRequests {
    static let homeScreenWidgetKind = "home-screen.widget"
    /// Every request kind this build carries out, as `{ op: "shell" }` lists them.
    static let supportedKinds = [importAppleRemindersKind, homeScreenWidgetKind]
}

/// Which gallery entry the sheet walks to: Sidekick (the asking Sidekick's widget) or Sidekicks
/// (the folder). Only Sidekick has an entry point now (founder, 2026-10-26).
enum HomeScreenWidgetVariant: String, CaseIterable, Sendable {
    case sidekick
    case folder
}

/// One sheet a Sidekick asked for.
struct HomeScreenWidgetRequest: Identifiable, Equatable, Sendable {
    let sidekickId: String
    let requestKey: String
    let variant: HomeScreenWidgetVariant

    var id: String {
        sidekickId + "|" + requestKey
    }
}

/// Sends each `request:` record to the part of the shell that carries out its kind. A kind no part
/// claims goes to the Apple Reminders import, which marks it failed ("unknown request").
@MainActor
struct ShellRequestDispatch {
    let homeScreen: HomeScreenWidgetCenter
    let remindersImport: AppleRemindersImportCenter

    func handleRequestWritten(sidekickId: String, key: String, value: JSONValue) {
        if value["kind"]?.stringValue == ShellRequests.homeScreenWidgetKind {
            homeScreen.handleRequestWritten(sidekickId: sidekickId, key: key, value: value)
            return
        }
        remindersImport.handleRequestWritten(sidekickId: sidekickId, key: key, value: value)
    }
}

/// Shows the sheet for the Sidekick that asked and marks its request done.
@MainActor
@Observable
final class HomeScreenWidgetCenter {
    /// The sheet on screen; nil when none.
    var shownRequest: HomeScreenWidgetRequest?

    @ObservationIgnored private let store: LocalRecordStore
    @ObservationIgnored private let now: @MainActor () -> Date

    init(store: LocalRecordStore, now: @escaping @MainActor () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    func handleRequestWritten(sidekickId: String, key: String, value: JSONValue) {
        guard value["status"]?.stringValue == "pending", value["kind"]?.stringValue == ShellRequests.homeScreenWidgetKind else {
            return
        }
        // No `widget` field means the Sidekick's own widget, the only entry point for now.
        let widgetName = value["widget"]?.stringValue ?? HomeScreenWidgetVariant.sidekick.rawValue
        guard let variant = HomeScreenWidgetVariant(rawValue: widgetName) else {
            finish(sidekickId: sidekickId, requestKey: key, status: "failed", extraFields: ["error": .string("unknown widget")])
            return
        }
        shownRequest = HomeScreenWidgetRequest(sidekickId: sidekickId, requestKey: key, variant: variant)
        finish(sidekickId: sidekickId, requestKey: key, status: "done", extraFields: [:])
    }

    /// Done, the close button, or the sheet swiped away.
    func dismiss() {
        shownRequest = nil
    }

    /// Writes the outcome into the request record (a patch: what the Sidekick put in it stays).
    private func finish(sidekickId: String, requestKey: String, status: String, extraFields: [String: JSONValue]) {
        var patch: [String: JSONValue] = [
            "status": .string(status),
            "finishedAt": .string(ISO8601DateFormatter.deviceZone.string(from: now())),
        ]
        for (fieldName, fieldValue) in extraFields {
            patch[fieldName] = fieldValue
        }
        try? RecordWriter(store: store).update(sidekickId: sidekickId, key: requestKey, patch: .object(patch))
    }
}

// MARK: What the sheet shows

/// The words on the sheet (docs/WRITING.md: each caption is the action).
enum HomeScreenWidgetCopy {
    static let title = "Add to Home Screen"
    static let done = "Done"
    static let close = "Close"
    static let touchAndHold = "Touch and hold the Home Screen"
    static let editThenAdd = "Tap Edit, then Add Widget"
    static let tapMidas = "Tap Midas"
    static let tapAddWidget = "Tap Add Widget"
    static let placed = "On your Home Screen"
    static let edit = "Edit"
    static let addWidget = "Add Widget"
    static let customize = "Customize"
    static let editPages = "Edit Pages"
    static let searchWidgets = "Search Widgets"

    static func swipe(to name: String) -> String {
        "Swipe to \(name)"
    }
}

/// The asking Sidekick's small widget, as the gallery and the placed widget draw it.
enum HomeScreenWidgetLook: Equatable {
    /// Its real widget, from the App Group file.
    case filled(SidekickWidgetScreen)
    /// No filled widget: a card in its tile colour with its name.
    case plain(name: String, tileHex: String)
    /// The Sidekicks folder: tiles in these colours.
    case folder(tileHexes: [String])
}

/// One step of the demo: from when its caption shows.
struct HomeScreenDemoStep: Equatable {
    let fromMs: Double
    let caption: String
}

/// When each part of the demo happens, in milliseconds from the start, exactly as the mockup's
/// `buildTimeline`. The folder variant has no swipe: its page is the first after tapping Midas.
struct HomeScreenDemoTimeline: Equatable {
    let jiggleStart: Double
    let menuOpen: Double
    let menuTap: Double
    let galleryUp: Double
    let midasTap: Double
    let pickUp: Double
    let swipeStart: Double
    let swipeEnd: Double
    let spotlight: Double
    let addTap: Double
    let placed: Double
    let jiggleEnd: Double
    let length: Double
    let pagesToPass: Int
    let steps: [HomeScreenDemoStep]

    /// Each swipe takes this long, one per gallery page passed.
    static let swipePerPageMs: Double = 800

    init(variant: HomeScreenWidgetVariant) {
        let pagesToPass = HomeScreenDemoGallery.pageIndex(of: variant)
        self.pagesToPass = pagesToPass
        jiggleStart = 1300
        menuOpen = 2600
        menuTap = 3300
        galleryUp = 3700
        midasTap = 5000
        pickUp = 5500
        swipeStart = 6300
        swipeEnd = swipeStart + Double(pagesToPass) * Self.swipePerPageMs
        spotlight = pagesToPass > 0 ? swipeEnd : 6000
        addTap = spotlight + 1700
        placed = addTap + 700
        jiggleEnd = placed + 1500
        length = jiggleEnd + 1200
        var steps = [
            HomeScreenDemoStep(fromMs: 0, caption: HomeScreenWidgetCopy.touchAndHold),
            HomeScreenDemoStep(fromMs: 2200, caption: HomeScreenWidgetCopy.editThenAdd),
            HomeScreenDemoStep(fromMs: 4300, caption: HomeScreenWidgetCopy.tapMidas),
        ]
        if pagesToPass > 0 {
            steps.append(HomeScreenDemoStep(fromMs: 6000, caption: HomeScreenWidgetCopy.swipe(to: HomeScreenDemoGallery.kind(of: variant).name)))
        }
        steps.append(HomeScreenDemoStep(fromMs: spotlight + 500, caption: HomeScreenWidgetCopy.tapAddWidget))
        self.steps = steps
    }

    /// The step on screen at `timeMs`.
    func stepIndex(at timeMs: Double) -> Int {
        var current = 0
        for (index, step) in steps.enumerated() where timeMs >= step.fromMs {
            current = index
        }
        return current
    }

    /// The caption at `timeMs`: the step's, then "On your Home Screen" once the widget lands.
    /// No "pick the Sidekick" step after it: a new Sidekick widget already shows the last
    /// Sidekick opened, the one that asked (commit 745ec18).
    func caption(at timeMs: Double) -> String {
        if timeMs > placed + 300 {
            return HomeScreenWidgetCopy.placed
        }
        return steps[stepIndex(at: timeMs)].caption
    }
}

/// How the sheet shows the steps: the animation, or with Reduce Motion a still numbered list.
enum HomeScreenDemoPresentation: Equatable {
    case animated(HomeScreenDemoTimeline)
    case stillList([String])

    static func choose(variant: HomeScreenWidgetVariant, reduceMotion: Bool) -> HomeScreenDemoPresentation {
        let timeline = HomeScreenDemoTimeline(variant: variant)
        guard reduceMotion else {
            return .animated(timeline)
        }
        var captions: [String] = []
        for step in timeline.steps {
            captions.append(step.caption)
        }
        return .stillList(captions)
    }
}

/// The widget gallery's pages after tapping Midas, in the app's order (MidasWidgetsBundle):
/// Sidekicks, small only (founder, 2026-10-26), first (founder, 2026-10-27), then Sidekick in
/// three sizes, so the Sidekick variant swipes past one page.
enum HomeScreenDemoGallery {
    struct Size: Equatable {
        let family: SidekickWidgetSize
        let width: CGFloat
        let height: CGFloat
    }

    struct Kind: Equatable {
        let variant: HomeScreenWidgetVariant
        let name: String
        let description: String
        let sizes: [Size]
    }

    static let small = Size(family: .small, width: 132, height: 132)
    static let medium = Size(family: .medium, width: 286, height: 134)
    static let large = Size(family: .large, width: 210, height: 220)

    static let kinds = [
        Kind(variant: .folder, name: FolderWidgetCopy.displayName, description: FolderWidgetCopy.description, sizes: [small]),
        Kind(variant: .sidekick, name: SidekickWidgetCopy.displayName, description: SidekickWidgetCopy.description, sizes: [small, medium, large]),
    ]

    static func kind(of variant: HomeScreenWidgetVariant) -> Kind {
        for kind in kinds where kind.variant == variant {
            return kind
        }
        return kinds[0]
    }

    /// The gallery page (counting every size) where the variant's small size is.
    static func pageIndex(of variant: HomeScreenWidgetVariant) -> Int {
        var pagesBefore = 0
        for kind in kinds {
            if kind.variant == variant {
                return pagesBefore
            }
            pagesBefore += kind.sizes.count
        }
        return 0
    }
}

/// Colours for the small Home Screen: the person's own Sidekick tile colours, or the eight tile
/// colours (docs/DESIGN.md 2.3) when they have fewer than three.
enum HomeScreenDemoColors {
    static let tilePalette = ["#30D5C8", "#FFBF00", "#9CAF88", "#FF6347", "#C9F24D", "#2E2E2E", "#FFE600", "#C41E3A"]
    static let iconCount = 12
    static let dockCount = 4
    /// The written Midas icon's place on the grid.
    static let midasIconIndex = 6

    /// The colours to draw from: the person's tile colours, each once, in their order.
    static func palette(personalHexes: [String]) -> [String] {
        var distinct: [String] = []
        for hex in personalHexes where SidekickColor.rgbComponents(fromHex: hex) != nil && !distinct.contains(hex.uppercased()) {
            distinct.append(hex.uppercased())
        }
        return distinct.count >= 3 ? distinct : tilePalette
    }

    /// Grid icons, the Midas icon's slot included (its colour is not drawn). The mockup steps by
    /// three through the eight so neighbours differ; a palette that three divides steps by one.
    static func iconHexes(palette: [String]) -> [String] {
        let step = palette.count % 3 == 0 ? 1 : 3
        var hexes: [String] = []
        var colorIndex = 0
        for iconIndex in 0..<iconCount {
            if iconIndex == midasIconIndex {
                hexes.append("")
                continue
            }
            hexes.append(palette[colorIndex % palette.count])
            colorIndex += step
        }
        return hexes
    }

    static func dockHexes(palette: [String]) -> [String] {
        var hexes: [String] = []
        for dockIndex in 0..<dockCount {
            hexes.append(palette[(dockIndex * 2 + 1) % palette.count])
        }
        return hexes
    }
}

/// Where the icons sit on the small Home Screen and the square the placed widget covers: rows as
/// far apart as columns, so 2 x 2 icons make a square and the widget takes exactly that square
/// (the mockup's step 4 fix, 2026-10-26).
struct HomeScreenDemoGrid: Equatable {
    static let iconSide: CGFloat = 52
    static let iconCorner: CGFloat = 14
    static let columns = 4
    static let rows = 3
    static let sidePadding: CGFloat = 22
    static let top: CGFloat = 44
    static let columnGap: CGFloat = 20
    /// Icons 0, 1, 4 and 5: the top-left 2 x 2.
    static let coveredIcons = [0, 1, 4, 5]

    let width: CGFloat

    /// Each column's width (the icon sits in its middle).
    var columnWidth: CGFloat {
        (width - Self.sidePadding * 2 - Self.columnGap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
    }

    /// Edge to edge between two icons side by side; the rows use the same.
    var iconGap: CGFloat {
        columnWidth + Self.columnGap - Self.iconSide
    }

    func iconFrame(_ index: Int) -> CGRect {
        let column = index % Self.columns
        let row = index / Self.columns
        let x = Self.sidePadding + CGFloat(column) * (columnWidth + Self.columnGap) + (columnWidth - Self.iconSide) / 2
        let y = Self.top + CGFloat(row) * (Self.iconSide + iconGap)
        return CGRect(x: x, y: y, width: Self.iconSide, height: Self.iconSide)
    }

    /// The square the placed small widget covers: from icon 0's top left to icon 5's bottom right.
    var placedFrame: CGRect {
        let first = iconFrame(Self.coveredIcons[0])
        let last = iconFrame(Self.coveredIcons[3])
        return CGRect(x: first.minX, y: first.minY, width: last.maxX - first.minX, height: last.maxY - first.minY)
    }
}

/// The mockup's easing: 0 before `start`, 1 after `end`, smoothstep between (nothing overshoots).
enum HomeScreenDemoEasing {
    static func progress(_ timeMs: Double, from start: Double, to end: Double) -> Double {
        if timeMs <= start {
            return 0
        }
        if timeMs >= end {
            return 1
        }
        let linear = (timeMs - start) / (end - start)
        return linear * linear * (3 - 2 * linear)
    }
}

/// Picks what the sheet draws for the Sidekick that asked.
enum HomeScreenWidgetLooks {
    /// A gallery entry's widget at a size. Sidekick: the asking Sidekick's own widget, from the
    /// App Group file, or a plain card in its tile colour when it has no filled widget.
    /// Sidekicks: the folder's tiles.
    static func look(of variant: HomeScreenWidgetVariant, sidekickId: String, size: SidekickWidgetSize, file: SharedSidekickWidgets?,
                     entry: SidekickEntry?, personalHexes: [String], at date: Date) -> HomeScreenWidgetLook {
        if variant == .folder {
            let palette = HomeScreenDemoColors.palette(personalHexes: personalHexes)
            let repeated = palette + palette
            return .folder(tileHexes: Array(repeated.prefix(FolderWidgetFamily.small.tileLimit)))
        }
        let screen = SidekickWidgetLayout.screen(file: file, sidekickId: sidekickId, widgetChoiceId: nil, size: size, at: date)
        if case .piece = screen {
            return .filled(screen)
        }
        let name = entry?.name ?? file?.widgets(ofSidekick: sidekickId).first?.sidekickName ?? SidekickWidgetCopy.displayName
        let tileHex = entry?.backgroundHex ?? HomeScreenDemoColors.tilePalette[0]
        return .plain(name: name, tileHex: tileHex)
    }
}
