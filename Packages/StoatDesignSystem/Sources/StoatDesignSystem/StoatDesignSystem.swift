import SwiftUI

public enum StoatSpacing {
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let xLarge: CGFloat = 24
    public static let xxLarge: CGFloat = 32
}

public enum StoatRadius {
    public static let control: CGFloat = 8
    public static let panel: CGFloat = 16
    public static let avatar: CGFloat = 10
}

public enum StoatAnimation {
    public static let quick = Animation.snappy(duration: 0.18)
    public static let standard = Animation.smooth(duration: 0.28)
}

public struct GlassPanel<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(StoatSpacing.large)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: StoatRadius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: StoatRadius.panel, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
    }
}

public struct GlassButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, StoatSpacing.medium)
            .padding(.vertical, StoatSpacing.small)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(StoatAnimation.quick, value: configuration.isPressed)
    }
}
