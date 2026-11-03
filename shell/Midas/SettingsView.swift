import SwiftUI
import UIKit

// Settings and delete (founder, 2026-10-31; docs/mockups/settings-delete-2026-10-31.html):
// E1 the initial at the top right of the home grid, S2 Settings as a pushed plain list with no
// back arrow, C3 the Midas sheet with the tile to delete a Sidekick, A1 the Delete Account alert,
// X1 its own screen after. Words: SettingsCopy (AccountCenter.swift).

/// A Sidekick's tile at any size: jess's and Make's written words, every other Sidekick's icon.
struct SidekickTileIcon: View {
    let sidekick: SidekickEntry
    let size: CGFloat

    var body: some View {
        if JessSidekick.isJess(sidekick) {
            JessTileIcon(size: size)
        } else if MakeSidekick.isMake(sidekick) {
            MakeTileIcon(size: size)
        } else {
            SidekickIconView(content: SidekickIconContent.content(for: sidekick), size: size)
        }
    }
}

/// E1: the person's initial in a small grey circle (32 pt, 14 pt semibold, ink-2 on paper-2).
struct AccountInitialCircle: View {
    let name: String
    var diameter: CGFloat = 32
    var fontSize: CGFloat = 14
    var textColor: Color?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        Text(AccountInitial.letter(for: name))
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(textColor ?? tokens.ink2.color)
            .frame(width: diameter, height: diameter)
            .background(tokens.paper2.color, in: Circle())
            .overlay(Circle().stroke(tokens.rule.color, lineWidth: 1))
    }
}

/// The home title (founder, 2026-11-02, H2 in docs/mockups/home-title-2026-11-02.html): "Midas" in
/// the hand (Caveat Bold, as on jess's and Make's tiles), on the left, its left edge on the first
/// tile's edge; the initial's right edge on the last tile's edge, its middle level with the middle
/// of the capital M.
enum HomeTopBarSpec {
    static let title = "Midas"
    nonisolated static let titleFontName = "Caveat-Bold"
    nonisolated static let titleSize: CGFloat = 40

    /// The title's and the initial's distance from the screen's edges: the tiles' outer edges.
    static func sideInset(screenWidth: CGFloat) -> CGFloat {
        SidekickHomeLayout.tileEdgeInset(screenWidth: screenWidth)
    }

    /// Half the hand's capital height at the title size: the middle of "M" sits this far above the
    /// baseline.
    nonisolated static var halfCapHeight: CGFloat {
        let font = UIFont(name: titleFontName, size: titleSize)
        let capHeight = font?.capHeight ?? titleSize * 0.61
        return capHeight / 2
    }
}

extension VerticalAlignment {
    /// The middle of the home title's capital letters.
    private enum HomeTitleCapMiddle: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.center]
        }
    }

    static let homeTitleCapMiddle = VerticalAlignment(HomeTitleCapMiddle.self)
}

/// The home grid's top line: "Midas" on the left, and at the right the initial (Settings) or,
/// while the tiles jiggle, "Done".
struct HomeTopBar: View {
    let userName: String
    let isArranging: Bool
    let onOpenSettings: () -> Void
    let onDone: () -> Void

    /// The screen's width, for lining up with the tiles (402 pt until measured).
    @State private var width: CGFloat = 402
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        let inset = HomeTopBarSpec.sideInset(screenWidth: width)
        HStack(alignment: .homeTitleCapMiddle) {
            Text(HomeTopBarSpec.title)
                .font(.custom(HomeTopBarSpec.titleFontName, size: HomeTopBarSpec.titleSize))
                .foregroundStyle(tokens.ink.color)
                .alignmentGuide(.homeTitleCapMiddle, computeValue: HomeTopBar.capMiddleOfTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailingControl
        }
        .padding(.horizontal, inset)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: HomeTopBar.widthOf, action: rememberWidth)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    /// The middle of "M": the baseline less half the capital height.
    nonisolated private static func capMiddleOfTitle(_ dimensions: ViewDimensions) -> CGFloat {
        dimensions[.firstTextBaseline] - HomeTopBarSpec.halfCapHeight
    }

    nonisolated private static func widthOf(_ proxy: GeometryProxy) -> CGFloat {
        proxy.size.width
    }

    private func rememberWidth(_ newWidth: CGFloat) {
        width = newWidth
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isArranging {
            Button(SettingsCopy.done, action: onDone)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
        } else {
            Button(action: onOpenSettings) {
                AccountInitialCircle(name: userName)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }
}

/// S2: big name with the initial, the person's Sidekicks, Sign Out, Delete Account. No back arrow:
/// the left-edge swipe goes home.
struct SettingsView: View {
    let userName: String
    let sidekicks: [SidekickEntry]
    let account: AccountCenter
    /// The AI switch (founder, 2026-11-02): off stops jess and Edit sending; on asks "Allow AI?".
    var aiConsent: AIConsentCenter = ShellServices.shared.aiConsent
    @State private var asksDeleteAccount = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(tokens)
                Text(SettingsCopy.sidekicksSection.uppercased())
                    .font(.system(size: 13))
                    .kerning(0.3)
                    .foregroundStyle(tokens.ink2.color)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 7)
                sidekickList(tokens)
                Spacer()
                    .frame(height: 34)
                aiSwitchRow(tokens)
                Spacer()
                    .frame(height: 34)
                actionRow(SettingsCopy.signOut, color: tokens.ink.color, tokens: tokens, isLast: false, action: signOut)
                deleteAccountRow(tokens)
            }
        }
        .background(tokens.paper.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .background {
            SwipeBackEnabler()
                .frame(width: 0, height: 0)
        }
        .alert(SettingsCopy.deleteAccountTitle, isPresented: $asksDeleteAccount) {
            Button(SettingsCopy.deleteAccount, role: .destructive, action: deleteAccount)
            Button(SettingsCopy.cancel, role: .cancel, action: keepAccount)
        } message: {
            Text(SettingsCopy.deleteAccountLine)
        }
        .alert(account.accountDeletionError ?? "", isPresented: showsDeletionError) {
            Button(SettingsCopy.ok, role: .cancel, action: dismissDeletionError)
        }
        .fullScreenCover(isPresented: showsAccountDeleted) {
            AccountDeletedView(onOK: account.finishAccountDeletion)
        }
    }

    private func header(_ tokens: RepairTokens) -> some View {
        HStack(spacing: 12) {
            AccountInitialCircle(name: userName, diameter: 44, fontSize: 19, textColor: tokens.ink.color)
            Text(userName)
                .font(.system(size: 34, weight: .bold))
                .kerning(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 48)
        .padding(.bottom, 36)
    }

    private func sidekickList(_ tokens: RepairTokens) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(sidekicks.enumerated()), id: \.element.id) { index, sidekick in
                sidekickRow(sidekick, isFirst: index == 0, tokens: tokens)
            }
        }
        .overlay(alignment: .top) { hairline(tokens) }
        .overlay(alignment: .bottom) { hairline(tokens) }
    }

    private func sidekickRow(_ sidekick: SidekickEntry, isFirst: Bool, tokens: RepairTokens) -> some View {
        HStack(spacing: 12) {
            SidekickTileIcon(sidekick: sidekick, size: 30)
            Text(sidekick.name)
                .font(.system(size: 17))
                .foregroundStyle(tokens.ink.color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        // The divider starts under the name, as in an iOS list
        .overlay(alignment: .top) {
            if !isFirst {
                hairline(tokens)
                    .padding(.leading, 58)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func hairline(_ tokens: RepairTokens) -> some View {
        Rectangle()
            .fill(tokens.rule.color)
            .frame(height: 1)
    }

    private func aiSwitchRow(_ tokens: RepairTokens) -> some View {
        Toggle(AIConsentCopy.settingsSwitch, isOn: aiSwitch)
            .font(.system(size: 17))
            .foregroundStyle(tokens.ink.color)
            // Ink in light mode; grey in dark, where ink is white like the knob (ShellSwitchTint)
            .tint(ShellSwitchTint.forScheme(colorScheme).color)
            .padding(.horizontal, 20)
            .frame(height: 52)
            .overlay(alignment: .top) { hairline(tokens) }
            .overlay(alignment: .bottom) { hairline(tokens) }
    }

    private var aiSwitch: Binding<Bool> {
        Binding(get: readAISwitch, set: writeAISwitch)
    }

    private func readAISwitch() -> Bool {
        aiConsent.isAllowed
    }

    // Off at once; on only through "Allow AI?", so the switch stays off until Allow
    private func writeAISwitch(_ isOn: Bool) {
        if isOn {
            aiConsent.run(AIConsentSettings.nothingAfterAllow)
        } else {
            aiConsent.setAllowed(false)
        }
    }

    private func actionRow(_ title: String, color: Color, tokens: RepairTokens, isLast: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(color)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { hairline(tokens) }
        .overlay(alignment: .bottom) {
            if isLast {
                hairline(tokens)
            }
        }
    }

    @ViewBuilder
    private func deleteAccountRow(_ tokens: RepairTokens) -> some View {
        if account.isRequestingDeletion {
            HStack {
                ProgressView()
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .overlay(alignment: .top) { hairline(tokens) }
            .overlay(alignment: .bottom) { hairline(tokens) }
        } else {
            actionRow(SettingsCopy.deleteAccount, color: Color(uiColor: .systemRed), tokens: tokens, isLast: true, action: askDeleteAccount)
        }
    }

    private func signOut() {
        Task { @MainActor in
            await account.signOut()
        }
    }

    private func askDeleteAccount() {
        asksDeleteAccount = true
    }

    private func keepAccount() {}

    private func deleteAccount() {
        Task { @MainActor in
            await account.requestAccountDeletion()
        }
    }

    private var showsDeletionError: Binding<Bool> {
        Binding(get: readShowsDeletionError, set: writeShowsDeletionError)
    }

    private func readShowsDeletionError() -> Bool {
        account.accountDeletionError != nil
    }

    private func writeShowsDeletionError(_ isShown: Bool) {
        if !isShown {
            account.accountDeletionError = nil
        }
    }

    private func dismissDeletionError() {
        account.accountDeletionError = nil
    }

    private var showsAccountDeleted: Binding<Bool> {
        Binding(get: readShowsAccountDeleted, set: writeShowsAccountDeleted)
    }

    private func readShowsAccountDeleted() -> Bool {
        account.showsAccountDeleted
    }

    // Only OK closes X1
    private func writeShowsAccountDeleted(_ isShown: Bool) {}
}

/// The Settings switch's Allow has nothing waiting to run.
enum AIConsentSettings {
    @MainActor
    static func nothingAfterAllow() {}
}

/// X1: "Your account will be deleted within 7 days." and OK, then the signed-out welcome.
struct AccountDeletedView: View {
    let onOK: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        VStack(spacing: 0) {
            Spacer()
            Text(SettingsCopy.accountDeletedLine)
                .font(.system(size: 22, weight: .semibold))
                .kerning(-0.2)
                .multilineTextAlignment(.center)
                .foregroundStyle(tokens.ink.color)
                .padding(.horizontal, 36)
            Spacer()
            Button(action: onOK) {
                Text(SettingsCopy.ok)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.paper.color)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(tokens.ink.color, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(tokens.paper.color.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}

/// C3: the Midas sheet with the tile: "Delete Water?" / "Its data goes too." / red Delete / Cancel.
struct SidekickDeleteSheet: View {
    let sidekick: SidekickEntry
    let account: AccountCenter
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// About how tall C3 is (it sizes itself on the bottom edge sheet; renders use this).
    static let height: CGFloat = 330

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        VStack(spacing: 10) {
            SidekickTileIcon(sidekick: sidekick, size: 60)
            Text(SettingsCopy.deleteSidekickTitle(sidekick.name))
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.3)
                .foregroundStyle(tokens.ink.color)
                .padding(.top, 4)
            Text(account.sidekickDeleteError ?? SettingsCopy.sidekickDataLine)
                .font(.system(size: 15))
                .foregroundStyle(tokens.ink2.color)
            Spacer()
                .frame(height: 12)
            Button(action: delete) {
                deleteLabel
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(uiColor: .systemRed), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(account.isDeletingSidekick)
            Button(action: onClose) {
                Text(SettingsCopy.cancel)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tokens.ink.color)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .onAppear(perform: account.clearSidekickDeleteError)
    }

    @ViewBuilder
    private var deleteLabel: some View {
        if account.isDeletingSidekick {
            ProgressView()
                .tint(.white)
        } else {
            Text(SettingsCopy.delete)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func delete() {
        Task { @MainActor in
            let isDeleted = await account.deleteSidekick(sidekick)
            if isDeleted {
                onClose()
            }
        }
    }
}

/// The minus badge on a tile while the tiles jiggle, like removing an app on iOS: a grey circle
/// with a dark minus at the icon's top left.
struct HomeTileMinusBadge: View {
    let sidekickName: String
    let action: () -> Void

    static let diameter: CGFloat = 22

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color(white: 0.1))
                .frame(width: Self.diameter, height: Self.diameter)
                .background(Color(white: 0.86).opacity(0.94), in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
                // A bigger target than the circle
                .padding(8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SettingsCopy.deleteSidekickLabel(sidekickName))
    }
}

/// The tiles jiggle while they can be deleted (iOS's edit mode); still with Reduce Motion.
struct HomeTileJiggle: ViewModifier {
    let isOn: Bool
    /// Neighbouring tiles swing the other way, so the grid does not move as one.
    let index: Int
    @State private var isTilted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let angle = 1.8
    static let halfPeriod = 0.13

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(currentAngle))
            .onChange(of: isOn, initial: true, restart)
    }

    private var currentAngle: Double {
        guard isOn && !reduceMotion else {
            return 0
        }
        let direction: Double = index.isMultiple(of: 2) ? 1 : -1
        return (isTilted ? Self.angle : -Self.angle) * direction
    }

    private func restart() {
        if isOn {
            let swing = Animation.easeInOut(duration: Self.halfPeriod).repeatForever(autoreverses: true)
            withAnimation(swing) {
                isTilted.toggle()
            }
        } else {
            withAnimation(.easeOut(duration: 0.1)) {
                isTilted = false
            }
        }
    }
}

/// A switch's "on" colour (founder, 2026-11-02, build 22 feedback, pick T2): `ink` in light mode
/// (DESIGN.md 2.1); in dark mode `ink` is white, the same as iOS's knob, so the switch vanished.
/// Dark uses #6B6B6B (light mode's ink-2), where the white knob shows.
enum ShellSwitchTint {
    static let light = JessOrbColor(hex: 0x111111)
    static let dark = JessOrbColor(hex: 0x6B6B6B)

    static func forScheme(_ scheme: ColorScheme) -> JessOrbColor {
        scheme == .dark ? dark : light
    }
}
