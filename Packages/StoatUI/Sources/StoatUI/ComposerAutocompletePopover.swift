import Foundation
import StoatDesignSystem
import StoatModels
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// Geometry for the composer's inline autocomplete popover.
///
/// The popover is presented as an `.overlay` on the composer text field, which means SwiftUI
/// proposes it the *field's* height (34pt collapsed). A bare VStack accepts that proposal and
/// slices its children, which is why rows rendered cut in half. These values let the popover
/// state its own size explicitly and let the call site position it without ever measuring the
/// child -- measuring back up from the child is also the shape Phase 64 forbids.
public enum ComposerAutocompleteSizing {
    public static let rowHeight: CGFloat = StoatSize.minimumRowHeight
    public static let maximumHeight: CGFloat = 240
    public static let width: CGFloat = 260
    public static let gap: CGFloat = 4
    /// Matches the `.padding(StoatSpacing.xxSmall)` around the row stack, top and bottom.
    private static let verticalPadding: CGFloat = StoatSpacing.xxSmall * 2

    public static func height(candidateCount: Int) -> CGFloat {
        guard candidateCount > 0 else { return 0 }
        let content = CGFloat(candidateCount) * rowHeight + verticalPadding
        return min(maximumHeight, content)
    }

    /// Negative offset that lifts the popover clear of the field it overlays.
    public static func offsetAboveField(fieldHeight: CGFloat, popoverHeight: CGFloat) -> CGFloat {
        -(popoverHeight + gap)
    }
}

struct InlineAutocompletePopover: View {
    let candidates: [ComposerAutocompleteCandidate]
    let highlightedID: String?
    let onSelect: (ComposerAutocompleteCandidate) -> Void
    let onRequestEmojiImage: (ComposerAutocompleteCandidate) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(candidates) { candidate in
                        Button {
                            onSelect(candidate)
                        } label: {
                            HStack(spacing: StoatSpacing.small) {
                                accessory(candidate)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(candidate.name)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    if let subtitle = candidate.subtitle {
                                        Text(subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, StoatSpacing.small)
                            .frame(height: ComposerAutocompleteSizing.rowHeight)
                            .background(
                                candidate.id == highlightedID ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(candidate.id)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(candidate.subtitle.map { "\(candidate.name), \($0)" } ?? candidate.name)
                        .accessibilityAddTraits(candidate.id == highlightedID ? [.isSelected] : [])
                        .onAppear {
                            if candidate.kind == .emoji, candidate.avatarData == nil {
                                onRequestEmojiImage(candidate)
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // Only about seven of the ten candidates fit, so keyboard navigation would otherwise
            // walk the highlight off-screen.
            .onChange(of: highlightedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(
            width: ComposerAutocompleteSizing.width,
            height: ComposerAutocompleteSizing.height(candidateCount: candidates.count)
        )
        // Claim the stated size rather than the 34pt the overlay proposes.
        .fixedSize()
        .padding(StoatSpacing.xxSmall)
        // Routes Reduce Transparency, Increase Contrast, and the Liquid Glass slider through the
        // design system instead of hardcoding .regularMaterial.
        .stoatGlass(.popover, radius: StoatRadius.control)
        .shadow(color: StoatElevation.softShadowColor, radius: StoatElevation.softRadius, y: 2)
        .zIndex(1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("autocomplete suggestions, \(candidates.count) results")
    }

    @ViewBuilder private func accessory(_ candidate: ComposerAutocompleteCandidate) -> some View {
        switch candidate.kind {
        case .user:
            AvatarView(title: candidate.name, size: 22, imageData: candidate.avatarData)
                .accessibilityHidden(true)
        case .channel:
            Image(systemName: "number")
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .role:
            Image(systemName: "person.crop.circle.badge.checkmark")
                .frame(width: 22, height: 22)
                .foregroundStyle(roleColor(candidate.roleColor))
                .accessibilityHidden(true)
        case .emoji:
            if let data = candidate.avatarData {
                DecodedDataImage(data: data, pixelSize: 44)
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            } else {
                Text(candidate.literalText ?? ":\(candidate.name):")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
        }
    }

    private func roleColor(_ components: MessageInlineMentionColorComponents?) -> Color {
        guard let components else { return .secondary }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }
}
