import SwiftUI

struct ThemeModeToggle: View {
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.dark.rawValue

    private var appearance: AppAppearance {
        get { AppAppearance(rawValue: storedAppearance) ?? .dark }
        nonmutating set { storedAppearance = newValue.rawValue }
    }

    private var isLightMode: Bool {
        appearance == .light
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                appearance = isLightMode ? .dark : .light
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(AppTheme.controlFill)

                HStack {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isLightMode ? AppTheme.textMuted : AppTheme.accent)

                    Spacer(minLength: 0)

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isLightMode ? AppTheme.accent : AppTheme.textMuted)
                }
                .padding(.horizontal, 10)

                Circle()
                    .fill(AppTheme.switchThumb)
                    .frame(width: 26, height: 26)
                    .shadow(color: AppTheme.switchThumbShadow, radius: 10, y: 3)
                    .overlay {
                        Image(systemName: isLightMode ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isLightMode ? AppTheme.accent : AppTheme.textPrimary)
                            .rotationEffect(.degrees(isLightMode ? 0 : -18))
                            .scaleEffect(isLightMode ? 1 : 0.94)
                    }
                    .offset(x: isLightMode ? 19 : -19)
            }
            .frame(width: 76, height: 34)
            .overlay(
                Capsule()
                    .stroke(AppTheme.controlStroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isLightMode)
        .accessibilityLabel("Toggle appearance")
        .accessibilityValue(isLightMode ? "Light mode" : "Dark mode")
        .help(isLightMode ? "Switch to dark mode" : "Switch to light mode")
    }
}
