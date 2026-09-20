import SwiftUI
import UIKit
import Combine

// Centralized theme for the app inspired by the new brush logo
public enum BrushTheme {
    // Brand colors (tuned to warm orange -> pink gradient, with a dark muted blue for text)
    public static let orange = Color(red: 1.00, green: 0.62, blue: 0.24)
    public static let pink   = Color(red: 0.98, green: 0.28, blue: 0.52)
    public static let yellow = Color(red: 1.00, green: 0.86, blue: 0.25)
    public static let textBlue = Color(red: 0.12, green: 0.18, blue: 0.30) // dark, muted blue

    // Background gradient matching the logo
    public static let backgroundGradient = LinearGradient(
        colors: [orange, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Soft multi-color background for large surfaces
    public static let softBackground = RadialGradient(
        gradient: Gradient(colors: [orange.opacity(0.25), pink.opacity(0.25), yellow.opacity(0.25)]),
        center: .center,
        startRadius: 20,
        endRadius: 500
    )

    // A pill button style with animated gradient shine
    public struct BrushButtonStyle: ButtonStyle {
        public init() {}
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    ZStack {
                        BrushTheme.backgroundGradient
                    }
                    .opacity(configuration.isPressed ? 0.85 : 1.0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: BrushTheme.pink.opacity(0.35), radius: configuration.isPressed ? 6 : 12, y: configuration.isPressed ? 2 : 8)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
        }
    }
}

// Font helpers: use Montserrat/Lato if added to the project; fall back to rounded system
public enum BrushFont {
    public static func title(_ size: CGFloat) -> Font {
        if UIFont(name: "Montserrat-Bold", size: size) != nil {
            return .custom("Montserrat-Bold", size: size)
        } else if UIFont(name: "Lato-Bold", size: size) != nil {
            return .custom("Lato-Bold", size: size)
        } else {
            return .system(size: size, weight: .bold, design: .rounded)
        }
    }

    public static func body(_ size: CGFloat) -> Font {
        if UIFont(name: "Montserrat-Regular", size: size) != nil {
            return .custom("Montserrat-Regular", size: size)
        } else if UIFont(name: "Lato-Regular", size: size) != nil {
            return .custom("Lato-Regular", size: size)
        } else {
            return .system(size: size, weight: .regular, design: .rounded)
        }
    }
}

// MARK: - Brand Icon (uses exact asset if available)
public struct BrandIcon: View {
    let size: CGFloat
    let preferAsset: Bool
    public init(size: CGFloat = 72, preferAsset: Bool = false) {
        self.size = size
        self.preferAsset = preferAsset
    }

    public var body: some View {
        Group {
            if preferAsset, let uiImage = UIImage(named: "BrushLogo") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "paintbrush.pointed.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(BrushTheme.backgroundGradient)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Artistic Home Background
public struct HomeBackground: View {
    public struct Palette {
        let top: Color
        let bottom: Color
        let glow: Color
        let blob1: Color
        let blob2: Color
        let blob3: Color
    }

    // Original soft brand palette
    public static let brandSoft = Palette(
        top: BrushTheme.orange.opacity(0.18),
        bottom: BrushTheme.pink.opacity(0.18),
        glow: BrushTheme.yellow.opacity(0.35),
        blob1: BrushTheme.pink.opacity(0.35),
        blob2: BrushTheme.orange.opacity(0.35),
        blob3: BrushTheme.yellow.opacity(0.25)
    )

    // Vivid palette: richer saturation and a subtle lavender accent for depth
    public static let brandVivid = Palette(
        top: Color(red: 1.00, green: 0.45, blue: 0.00).opacity(0.35),   // deeper orange
        bottom: Color(red: 0.94, green: 0.16, blue: 0.52).opacity(0.35), // vivid pink
        glow: Color(red: 1.00, green: 0.78, blue: 0.20).opacity(0.45),   // warm glow
        blob1: Color(red: 0.86, green: 0.18, blue: 0.56).opacity(0.50),  // magenta blob
        blob2: Color(red: 1.00, green: 0.55, blue: 0.20).opacity(0.45),  // coral blob
        blob3: Color(red: 0.62, green: 0.48, blue: 0.96).opacity(0.35)   // lavender accent
    )

    let palette: Palette
    public init(palette: Palette = HomeBackground.brandSoft) { self.palette = palette }

    public var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [palette.top, palette.bottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Warm center glow
            RadialGradient(
                gradient: Gradient(colors: [palette.glow, .clear]),
                center: .center,
                startRadius: 0,
                endRadius: 460
            )

            // Blurred color blobs for a lively, artistic feel
            Circle()
                .fill(palette.blob1)
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: 140, y: -260)

            Circle()
                .fill(palette.blob2)
                .frame(width: 320, height: 320)
                .blur(radius: 100)
                .offset(x: -160, y: 180)

            Circle()
                .fill(palette.blob3)
                .frame(width: 280, height: 280)
                .blur(radius: 110)
                .offset(x: 120, y: 320)
        }
        // Soft vignette to keep focus in the middle
        .overlay(
            RadialGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.06)]),
                center: .center,
                startRadius: 600,
                endRadius: 900
            )
        )
    }
}

// MARK: - Glass material helper
public extension BrushTheme {
    struct GlassModifier: ViewModifier {
        let cornerRadius: CGFloat
        public init(cornerRadius: CGFloat = 16) { self.cornerRadius = cornerRadius }
        public func body(content: Content) -> some View {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        }
    }
}

public extension View {
    func brushGlass(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(BrushTheme.GlassModifier(cornerRadius: cornerRadius))
    }
}
