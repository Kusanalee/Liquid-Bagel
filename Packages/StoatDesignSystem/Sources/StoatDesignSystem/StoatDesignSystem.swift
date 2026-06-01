import SwiftUI

public enum StoatSpacing {
    public static let xxSmall: CGFloat = 2
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let xLarge: CGFloat = 24
    public static let xxLarge: CGFloat = 32
}

public enum StoatRadius {
    public static let small: CGFloat = 6
    public static let control: CGFloat = 8
    public static let row: CGFloat = 8
    public static let panel: CGFloat = 14
    public static let largePanel: CGFloat = 18
    public static let avatar: CGFloat = 12
    public static let capsule: CGFloat = 999
}

public enum StoatSize {
    public static let serverRailWidth: CGFloat = 72
    public static let channelSidebarWidth: CGFloat = 260
    public static let memberPanelWidth: CGFloat = 240
    public static let serverIcon: CGFloat = 46
    public static let avatar: CGFloat = 38
    public static let compactAvatar: CGFloat = 28
    public static let minimumRowHeight: CGFloat = 34
}

public enum StoatTypography {
    public static let sidebarHeader = Font.title3.weight(.semibold)
    public static let section = Font.caption.weight(.semibold)
    public static let row = Font.callout
    public static let rowSelected = Font.callout.weight(.semibold)
    public static let messageAuthor = Font.subheadline.weight(.semibold)
    public static let messageBody = Font.body
    public static let metadata = Font.caption
}

public enum StoatGlassMaterial: Sendable {
    case rail
    case sidebar
    case panel
    case composer
    case toolbar
    case popover

    public var material: Material {
        switch self {
        case .rail: .regularMaterial
        case .sidebar: .thinMaterial
        case .panel: .thinMaterial
        case .composer: .regularMaterial
        case .toolbar: .bar
        case .popover: .regularMaterial
        }
    }
}

public enum StoatElevation {
    public static let panelShadowColor = Color.black.opacity(0.16)
    public static let softShadowColor = Color.black.opacity(0.08)
    public static let panelRadius: CGFloat = 18
    public static let softRadius: CGFloat = 8
}

public enum StoatAnimation {
    public static let quick = Animation.snappy(duration: 0.16)
    public static let standard = Animation.smooth(duration: 0.24)

    public static func allowed(_ reduceMotion: Bool, _ animation: Animation = standard) -> Animation? {
        reduceMotion ? nil : animation
    }
}

public struct SearchHighlightStyle: Hashable, Sendable {
    public var isHighlighted: Bool
    public var isCurrent: Bool
    public var highContrast: Bool
    public var reduceTransparency: Bool
    public var compactDensity: Bool

    public init(isHighlighted: Bool = false, isCurrent: Bool = false, highContrast: Bool = false, reduceTransparency: Bool = false, compactDensity: Bool = false) {
        self.isHighlighted = isHighlighted
        self.isCurrent = isCurrent
        self.highContrast = highContrast
        self.reduceTransparency = reduceTransparency
        self.compactDensity = compactDensity
    }

    public var fillOpacity: Double {
        guard isHighlighted else { return 0 }
        if reduceTransparency { return isCurrent ? 0.22 : 0.15 }
        if highContrast { return isCurrent ? 0.24 : 0.16 }
        return isCurrent ? 0.16 : 0.09
    }

    public var borderOpacity: Double {
        guard isHighlighted else { return 0 }
        if highContrast { return isCurrent ? 0.78 : 0.52 }
        return isCurrent ? 0.58 : 0.28
    }

    public var borderWidth: CGFloat {
        guard isHighlighted else { return 0 }
        return highContrast || isCurrent ? 1.5 : 1
    }

    public var verticalPaddingAdjustment: CGFloat {
        compactDensity ? 0 : 1
    }
}

public enum StoatBadges {
    public static func displayCount(_ count: Int) -> String {
        if count <= 0 { return "" }
        if count > 99 { return "99+" }
        return String(count)
    }

    public static func mentionAccessibilityLabel(count: Int) -> String {
        count == 1 ? "1 mention" : "\(count) mentions"
    }

    public static func unreadAccessibilityLabel(count: Int) -> String {
        count == 1 ? "1 unread message" : "\(count) unread messages"
    }
}

public enum StoatInitials {
    public static func make(_ text: String, fallback: String = "?") -> String {
        let words = text
            .split { !$0.isLetter && !$0.isNumber }
            .filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap(\.first)
        if letters.isEmpty {
            return String(fallback.prefix(2)).uppercased()
        }
        return String(letters).uppercased()
    }
}

public enum StoatAccessibility {
    public static func selectedLabel(_ label: String, isSelected: Bool) -> String {
        isSelected ? "\(label), selected" : label
    }

    public static func serverLabel(name: String, unreadCount: Int = 0, mentionCount: Int = 0, isSelected: Bool = false) -> String {
        var parts = [selectedLabel(name, isSelected: isSelected)]
        if unreadCount > 0 { parts.append(StoatBadges.unreadAccessibilityLabel(count: unreadCount)) }
        if mentionCount > 0 { parts.append(StoatBadges.mentionAccessibilityLabel(count: mentionCount)) }
        return parts.joined(separator: ", ")
    }

    public static func channelLabel(name: String, unreadCount: Int = 0, mentionCount: Int = 0, isSelected: Bool = false, isDisabled: Bool = false) -> String {
        var parts = [selectedLabel(name, isSelected: isSelected)]
        if unreadCount > 0 { parts.append(StoatBadges.unreadAccessibilityLabel(count: unreadCount)) }
        if mentionCount > 0 { parts.append(StoatBadges.mentionAccessibilityLabel(count: mentionCount)) }
        if isDisabled { parts.append("unavailable") }
        return parts.joined(separator: ", ")
    }

    public static func messageLabel(author: String, timestamp: String, content: String, isEdited: Bool = false, isPinned: Bool = false, reactionCount: Int = 0, status: String? = nil, isSelected: Bool = false, isFocused: Bool = false, searchResultStatus: String? = nil, replyPreview: String? = nil) -> String {
        var parts = [author, timestamp, content.isEmpty ? "message" : content]
        if let replyPreview, !replyPreview.isEmpty { parts.append("reply to \(replyPreview)") }
        if isEdited { parts.append("edited") }
        if isPinned { parts.append("pinned") }
        if reactionCount > 0 { parts.append(reactionCount == 1 ? "1 reaction" : "\(reactionCount) reactions") }
        if let status, !status.isEmpty { parts.append(status) }
        if isSelected { parts.append("selected") }
        if isFocused { parts.append("focused") }
        if let searchResultStatus, !searchResultStatus.isEmpty { parts.append(searchResultStatus) }
        return parts.joined(separator: ", ")
    }

    public static func inlineEditLabel(isSaving: Bool, errorMessage: String? = nil) -> String {
        ["Inline message editor", isSaving ? "saving" : nil, errorMessage].compactMap { $0 }.joined(separator: ", ")
    }

    public static func failedMessageActionLabel(action: String, error: String? = nil) -> String {
        [action, "failed message", error].compactMap { $0 }.joined(separator: ", ")
    }

    public static func reactionLabel(emoji: String, count: Int, hasReacted: Bool) -> String {
        var parts = ["Reaction \(emoji)", count == 1 ? "1 reaction" : "\(count) reactions"]
        if hasReacted { parts.append("selected") }
        return parts.joined(separator: ", ")
    }

    public static func messageActionLabel(title: String, isDestructive: Bool = false, isEnabled: Bool = true) -> String {
        [title, isDestructive ? "destructive" : nil, isEnabled ? nil : "unavailable"].compactMap { $0 }.joined(separator: ", ")
    }

    public static func composerLabel(isEnabled: Bool, disabledReason: String?, replyAuthor: String? = nil) -> String {
        let base = isEnabled ? "Message composer" : "Message composer disabled"
        return [base, replyAuthor.map { "replying to \($0)" }, isEnabled ? nil : disabledReason].compactMap { $0 }.joined(separator: ", ")
    }

    public static func replyContextLabel(author: String, preview: String, mentionsAuthor: Bool) -> String {
        ["Replying to \(author)", preview, mentionsAuthor ? "will mention author" : "will not mention author"].joined(separator: ", ")
    }

    public static func replyPreviewLabel(_ preview: String) -> String {
        "Reply preview, \(preview)"
    }

    public static func attachmentLabel(filename: String, kind: String, size: String, state: String) -> String {
        [filename, kind, size, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    public static func attachmentActionLabel(action: String, filename: String) -> String {
        "\(action), \(filename)"
    }

    public static func jumpNewestLabel(hasNewMessages: Bool) -> String {
        hasNewMessages ? "Jump to newest messages" : "Jump to newest message"
    }

    public static func localReadStateLabel() -> String {
        "Marked read locally"
    }

    public static func runtimeLabel(mode: String, connection: String, health: String? = nil) -> String {
        ["Runtime \(mode)", "connection state \(connection)", health].compactMap { $0 }.joined(separator: ", ")
    }
}

public enum StoatDensityStyle: Sendable {
    public static func timelineSpacing(for preference: String) -> CGFloat {
        preference == "compact" ? StoatSpacing.small : StoatSpacing.medium
    }

    public static func messageVerticalPadding(for preference: String) -> CGFloat {
        preference == "compact" ? StoatSpacing.xxSmall : StoatSpacing.small
    }
}

public struct StoatMaterialStyle: Hashable, Sendable {
    public var usesMaterial: Bool
    public var backgroundOpacity: Double
    public var strokeOpacity: Double

    public init(usesMaterial: Bool, backgroundOpacity: Double, strokeOpacity: Double) {
        self.usesMaterial = usesMaterial
        self.backgroundOpacity = backgroundOpacity
        self.strokeOpacity = strokeOpacity
    }

    public static func resolved(reduceTransparency: Bool, increaseContrast: Bool, reduceGlassIntensity: Bool) -> StoatMaterialStyle {
        if reduceTransparency {
            return StoatMaterialStyle(usesMaterial: false, backgroundOpacity: 1, strokeOpacity: increaseContrast ? 0.42 : 0.24)
        }
        return StoatMaterialStyle(
            usesMaterial: !reduceGlassIntensity,
            backgroundOpacity: reduceGlassIntensity ? 0.12 : 0.04,
            strokeOpacity: increaseContrast ? 0.38 : 0.18
        )
    }
}

public struct GlassBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let material: StoatGlassMaterial
    private let radius: CGFloat
    private let strokeOpacity: Double

    public init(material: StoatGlassMaterial = .panel, radius: CGFloat = StoatRadius.panel, strokeOpacity: Double = 0.18) {
        self.material = material
        self.radius = radius
        self.strokeOpacity = strokeOpacity
    }

    public func body(content: Content) -> some View {
        let style = StoatMaterialStyle.resolved(
            reduceTransparency: reduceTransparency,
            increaseContrast: colorSchemeContrast == .increased,
            reduceGlassIntensity: false
        )
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(style.backgroundOpacity))
                    .modifier(MaterialFallback(material: material, radius: radius, reduceTransparency: reduceTransparency))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(max(strokeOpacity, style.strokeOpacity)), lineWidth: colorSchemeContrast == .increased ? 1.5 : 1)
            }
    }
}

private struct MaterialFallback: ViewModifier {
    let material: StoatGlassMaterial
    let radius: CGFloat
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
        } else {
            content.background(material.material, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

public extension View {
    func stoatGlass(_ material: StoatGlassMaterial = .panel, radius: CGFloat = StoatRadius.panel, strokeOpacity: Double = 0.18) -> some View {
        modifier(GlassBackground(material: material, radius: radius, strokeOpacity: strokeOpacity))
    }
}

public struct GlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let selected: Bool

    public init(selected: Bool = false) {
        self.selected = selected
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(selected ? .semibold : .medium))
            .padding(.horizontal, StoatSpacing.medium)
            .padding(.vertical, StoatSpacing.small)
            .background(selected ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08))
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(StoatAnimation.allowed(reduceMotion, .snappy(duration: 0.12)), value: configuration.isPressed)
    }
}
