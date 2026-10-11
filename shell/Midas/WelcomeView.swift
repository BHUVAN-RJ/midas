import SwiftUI

/// Button wording on the welcome screen (founder, 2026-10-10: option B).
enum WelcomeCopy {
    static let newUserButton = "Get started"
    static let returningUserButton = "I've used Midas before"
}

/// First screen for anyone without a session: a name, then a passkey. Returning users (new
/// phone, reinstall) sign in with the passkey they already have, which brings their data back.
struct WelcomeView: View {
    let auth: AuthModel
    @State private var name = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Midas")
                .font(.largeTitle.bold())
            Text("What should we call you?")
                .foregroundStyle(.secondary)
            TextField("Your name", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
                .onSubmit(createAccount)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            Button(action: createAccount) {
                Text(WelcomeCopy.newUserButton)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(auth.isWorking || name.trimmingCharacters(in: .whitespaces).isEmpty)

            if let errorMessage = auth.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button(WelcomeCopy.returningUserButton, action: signIn)
                .disabled(auth.isWorking)
        }
        .padding(24)
    }

    private func createAccount() {
        let enteredName = name
        Task {
            await auth.createAccount(name: enteredName)
        }
    }

    private func signIn() {
        Task {
            await auth.signInWithPasskey()
        }
    }
}
