import SwiftUI

/// Single-admin sign-in. There is exactly one account — mine.
struct AuthView: View {
    @EnvironmentObject var store: DataStore
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "soccerball")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.amber)
                Text("SoccerLog").font(.largeTitle.bold()).foregroundStyle(Theme.ink)
                Text("Admin sign-in").font(.subheadline).foregroundStyle(Theme.inkSoft)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Divider()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                .padding()
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))

                if let err = store.authError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    busy = true
                    Task { await store.signIn(email: email, password: password); busy = false }
                } label: {
                    if busy { ProgressView().tint(.white) } else { Text("Sign in") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || email.isEmpty || password.isEmpty)
                Spacer()
            }
            .padding(24)
        }
    }
}
