import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentPage = 0
    
    let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "checkmark.seal.fill",
            title: "Prove Existence",
            description: "Timestamp any text, photo, or file to create an immutable proof that it existed at a specific point in time.",
            color: .orange
        ),
        OnboardingPage(
            icon: "bitcoinsign.circle.fill",
            title: "Anchored in Bitcoin",
            description: "Your timestamps are anchored in the Bitcoin blockchain - the most secure and decentralized ledger in the world.",
            color: .orange
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "Privacy First",
            description: "Only the hash of your content is sent to the network. Your actual data never leaves your device.",
            color: .green
        ),
        OnboardingPage(
            icon: "icloud.slash.fill",
            title: "No Account Needed",
            description: "No sign-up, no servers, no tracking. Witness works directly with the OpenTimestamps network.",
            color: .blue
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Pages
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 32)
            
            // Button
            Button {
                if currentPage < pages.count - 1 {
                    withAnimation {
                        currentPage += 1
                    }
                } else {
                    hasSeenOnboarding = true
                    dismiss()
                }
            } label: {
                Text(currentPage < pages.count - 1 ? "Continue" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            
            // Skip button
            if currentPage < pages.count - 1 {
                Button("Skip") {
                    hasSeenOnboarding = true
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
            } else {
                Spacer()
                    .frame(height: 44)
            }
        }
        .interactiveDismissDisabled()
    }
    
    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundStyle(page.color)
            
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            Spacer()
        }
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

#Preview {
    OnboardingView()
}
