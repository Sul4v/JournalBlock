import SwiftUI

/// The first thing anyone sees. Two doors, deliberately unequal.
///
/// New users get the personalisation quiz, which is what makes the paywall land
/// later. Returning users — a new phone, a reinstall — need to skip all of it;
/// making someone who already pays answer fourteen questions to reach a sign-in
/// button is the kind of thing that turns a lapsed user into a churned one.
struct WelcomeView: View {
    var onGetStarted: () -> Void
    var onSignIn: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            SkyBackground(phase: .sunrise)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: Theme.Space.lg)

                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text(AppConfig.appName)
                        .font(Theme.Typography.serif(56))
                        .foregroundStyle(Theme.Palette.ink)

                    Text("Your phone stays closed until the page is written.")
                        .font(Theme.Typography.serif(24))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

                Spacer()

                VStack(spacing: Theme.Space.sm) {
                    EmberButton(title: "Get started", systemImage: "arrow.right") {
                        onGetStarted()
                    }

                    Button {
                        Haptics.tap(.light)
                        onSignIn()
                    } label: {
                        Text("I already have an account")
                            .font(Theme.Typography.sans(15, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
            }
            .pageGutter()
            .padding(.bottom, Theme.Space.md)
        }
        .onAppear {
            withAnimation(Theme.Motion.gentle.delay(0.12)) { appeared = true }
        }
    }
}
