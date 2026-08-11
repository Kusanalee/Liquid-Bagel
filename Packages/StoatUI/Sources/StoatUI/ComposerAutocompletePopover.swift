import Foundation
import StoatDesignSystem
import StoatModels
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

struct InlineAutocompletePopover: View {
    let candidates: [ComposerAutocompleteCandidate]
    let highlightedID: String?
    let onSelect: (ComposerAutocompleteCandidate) -> Void
    let onRequestEmojiImage: (ComposerAutocompleteCandidate) -> Void

    var body: some View {
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
                    .padding(.vertical, StoatSpacing.xSmall)
                    .background(
                        candidate.id == highlightedID ? Color.accentColor.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
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
        .padding(StoatSpacing.xxSmall)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: StoatRadius.control, style: .continuous))
        .frame(width: 260)
        .shadow(radius: 8)
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
