import SwiftUI

/// Shown when the Declared Age Range check determines the user is under the
/// minimum age. It's a terminal screen — there's no way past it.
struct UnderageBlockedView: View {
    var body: some View {
        ZStack {
            HomeBackground()
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(BrushTheme.textBlue)
                    .accessibilityHidden(true)

                Text("You're not old enough to use bRUSH")
                    .font(BrushFont.title(26))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BrushTheme.textBlue)

                Text("bRUSH is for artists aged 13 and up. Thanks for stopping by — come back when you're a little older!")
                    .font(BrushFont.body(17))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BrushTheme.textBlue.opacity(0.8))
                    .padding(.horizontal, 32)
            }
            .padding()
        }
    }
}

#Preview {
    UnderageBlockedView()
}
