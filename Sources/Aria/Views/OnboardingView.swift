import SwiftUI

/// Full-screen onboarding shown on first launch.
/// Splash → Sign In → Done.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var step: OnboardingStep = .splash
    @State private var showAccountSetup = false

    enum OnboardingStep { case splash, signIn, done }

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18), Color(nsColor: .windowBackgroundColor)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            switch step {
            case .splash:    splashScreen
            case .signIn:    signInScreen
            case .done:      doneScreen
            }
        }
        .frame(minWidth: 540, minHeight: 480)
        .sheet(isPresented: $showAccountSetup) {
            AccountSetupView()
                .environmentObject(appState)
                .onDisappear {
                    if !appState.accounts.isEmpty {
                        withAnimation(.easeInOut(duration: 0.5)) { step = .done }
                    }
                }
        }
    }

    // MARK: - Splash

    private var splashScreen: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Oralis")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)

                Text("Your voice-first email assistant")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                FeatureRow(icon: "mic.fill",          text: "Talk to manage your inbox")
                FeatureRow(icon: "brain.head.profile", text: "AI understands natural language")
                FeatureRow(icon: "lock.shield.fill",  text: "Everything stays on your device")
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.4)) { step = .signIn }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get started — set up your email account")
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Sign In

    private var signInScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "envelope.badge.shield.half.filled.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("Connect Your Email")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)

                Text("Sign in securely to get started.\nOralis never stores your password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                OnboardingProviderButton(
                    label: "Continue with Google",
                    subtitle: "Gmail, Google Workspace",
                    tint: Color(red: 0.85, green: 0.26, blue: 0.21)
                ) { showAccountSetup = true }

                OnboardingProviderButton(
                    label: "Continue with Microsoft",
                    subtitle: "Outlook, Hotmail, Live",
                    tint: Color(red: 0.0, green: 0.47, blue: 0.84)
                ) { showAccountSetup = true }

                OnboardingProviderButton(
                    label: "Other account",
                    subtitle: "Yahoo, iCloud, or custom IMAP",
                    tint: .secondary
                ) { showAccountSetup = true }
            }
            .padding(.horizontal, 32)

            Spacer()

            Button("Skip for now") {
                completeOnboarding()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.bottom, 32)
            .accessibilityLabel("Skip account setup and go to the main screen")
        }
    }

    // MARK: - Done

    private var doneScreen: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.green)
                .symbolEffect(.bounce)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("You're all set!")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)

                if let acc = appState.accounts.first {
                    Text("Connected as \(acc.emailAddress)")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Say \"Read my latest email\" to get started, or tap the mic at the bottom of the screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)

            Spacer()

            Button {
                completeOnboarding()
            } label: {
                Text("Start Talking to Oralis")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Finish setup and open the main screen")
            .padding(.bottom, 40)
        }
    }

    // MARK: - Helpers

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "oralis.onboardingComplete")
        appState.showOnboarding = false
    }
}

// MARK: - Feature row

struct FeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Onboarding provider button

struct OnboardingProviderButton: View {
    let label: String
    let subtitle: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.secondary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(tint.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label). \(subtitle)")
    }
}
