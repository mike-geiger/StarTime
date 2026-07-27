import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthService

    @State private var isSigningUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)

                Text("Star Time")
                    .font(.largeTitle.bold())

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $password)
                        .textContentType(isSigningUp ? .newPassword : .password)
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(isSigningUp ? "Create Account" : "Sign In") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || password.isEmpty || isSubmitting)

                Button(isSigningUp ? "Already have an account? Sign In" : "New here? Create an account") {
                    isSigningUp.toggle()
                    errorMessage = nil
                }
                .font(.footnote)
            }
            .padding()
        }
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                if isSigningUp {
                    try await auth.signUp(email: email, password: password)
                } else {
                    try await auth.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthService())
}
