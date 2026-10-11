import SwiftUI

/// Words on the import sheet (founder, 2026-10-10, approved in the import-flow mockup).
enum AppleRemindersImportCopy {
    static let title = "Bring in your Apple Reminders"
    static let explanation = "Midas reads your lists and reminders on this iPhone and adds them here. Nothing in Apple Reminders is changed."
    static let reconcileNote = "Already brought them in from your Mac? Anything that changed on your iPhone is updated."
    static let continueButton = "Continue"
    static let notNowButton = "Not now"
    static let workingLabel = "Reading your reminders"
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
            Text(AppleRemindersImportCopy.explanation)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(AppleRemindersImportCopy.reconcileNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
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
