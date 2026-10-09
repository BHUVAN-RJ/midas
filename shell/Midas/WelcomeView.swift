import SwiftUI

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
                Text("Continue with a passkey")
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
            Button("I already have a passkey", action: signIn)
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
