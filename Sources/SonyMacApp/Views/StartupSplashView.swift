import SwiftUI

struct StartupSplashView: View {
    @State private var wordmarkScale: CGFloat = 0.78
    @State private var wordmarkOpacity = 0.0
    @State private var wordmarkBlur: CGFloat = 14
    @State private var glowOpacity = 0.0

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    AppTheme.splashGlow.opacity(glowOpacity),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 340
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("SONY")
                    .font(.system(size: 38, weight: .semibold))
                    .tracking(8)
                    .foregroundStyle(AppTheme.splashWordmark)
                    .scaleEffect(wordmarkScale)
                    .opacity(wordmarkOpacity)
                    .blur(radius: wordmarkBlur)
                    .shadow(color: AppTheme.splashGlow.opacity(glowOpacity), radius: 18, y: 0)

                Rectangle()
                    .fill(AppTheme.splashDivider.opacity(glowOpacity))
                    .frame(width: 120, height: 1)
                    .opacity(wordmarkOpacity * 0.5)
            }
            .padding(32)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.72)) {
                wordmarkScale = 1.06
                wordmarkOpacity = 1
                wordmarkBlur = 0
                glowOpacity = 1
            }

            withAnimation(.easeInOut(duration: 0.34).delay(0.72)) {
                wordmarkScale = 1.0
            }
        }
    }
}
