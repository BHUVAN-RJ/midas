import SwiftUI

/// Words on the import sheet: a title and the buttons, nothing else (docs/WRITING.md; founder
/// approved the wording mockup 2026-10-10).
enum AppleRemindersImportCopy {
    static let title = "Import Apple Reminders"
    static let continueButton = "Continue"
    static let notNowButton = "Not Now"
    static let workingLabel = "Importing…"
}

/// Shown by Midas, never by the Sidekick, when a Sidekick asks to import Apple Reminders. iOS's
/// own permission alert follows "Continue".
struct AppleRemindersImportSheet: View {
    let center: AppleRemindersImportCenter
    let askingSidekick: SidekickEntry?

    var body: some View {
        VStack(spacing: 14) {
            if let askingSidekick {
                SidekickIconView(content: SidekickIconContent.content(for: askingSidekick), size: 64)
                    .padding(.top, 8)
            }
            Text(AppleRemindersImportCopy.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Spacer(minLength: 8)
            if center.isImporting {
                ProgressView(AppleRemindersImportCopy.workingLabel)
                    .padding(.vertical, 12)
            } else {
                Button(action: continueImport) {
                    Text(AppleRemindersImportCopy.continueButton)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button(AppleRemindersImportCopy.notNowButton, action: center.cancelShownRequest)
                    .padding(.top, 2)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(center.isImporting)
    }

    private func continueImport() {
        Task { @MainActor in
            await center.runShownRequest()
        }
    }
}
