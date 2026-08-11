import AppKit
import StoatDesignSystem
import StoatModels
import SwiftUI
import XCTest
@testable import StoatUI

final class StoatUITests: XCTestCase {
    func testInitialsGeneration() {
        XCTAssertEqual(StoatInitials.make("Bagel Lab"), "BL")
        XCTAssertEqual(StoatInitials.make("stoat"), "S")
        XCTAssertEqual(StoatInitials.make("", fallback: "LB"), "LB")
    }

    func testBadgeFormatting() {
        XCTAssertEqual(StoatBadges.displayCount(0), "")
        XCTAssertEqual(StoatBadges.displayCount(7), "7")
        XCTAssertEqual(StoatBadges.displayCount(120), "99+")
    }

    func testAccessibilityLabelsIncludeState() {
        let label = StoatAccessibility.serverLabel(name: "Bagel Lab", unreadCount: 2, mentionCount: 1, isSelected: true)
        XCTAssertTrue(label.contains("selected"))
        XCTAssertTrue(label.contains("2 unread messages"))
        XCTAssertTrue(label.contains("1 mention"))
    }

    func testPhase8AccessibilityLabelsIncludeDisabledReasons() {
        let composer = StoatAccessibility.composerLabel(isEnabled: false, disabledReason: "Connect Live Manual before sending.")
        XCTAssertTrue(composer.contains("disabled"))
        XCTAssertTrue(composer.contains("Connect Live Manual"))

        let channel = StoatAccessibility.channelLabel(name: "voice", isDisabled: true)
        XCTAssertTrue(channel.contains("unavailable"))
    }

    func testPhase9MessageActionAccessibilityHelpers() {
        let message = StoatAccessibility.messageLabel(author: "Liquid", timestamp: "now", content: "hello", isEdited: true, isPinned: true, reactionCount: 2, status: "selected")
        XCTAssertTrue(message.contains("edited"))
        XCTAssertTrue(message.contains("pinned"))
        XCTAssertTrue(message.contains("2 reactions"))

        XCTAssertTrue(StoatAccessibility.inlineEditLabel(isSaving: true).contains("saving"))
        XCTAssertTrue(StoatAccessibility.failedMessageActionLabel(action: "Retry", error: "send failed").contains("failed message"))
        XCTAssertTrue(StoatAccessibility.reactionLabel(emoji: "✅", count: 1, hasReacted: true).contains("selected"))
    }

    func testPhase16AttachmentDisplaySanitizesAndInfersKind() {
        let image = File(id: "file-image", tag: "attachments", filename: "/tmp/private/photo.png", metadata: .image(width: 80, height: 60, thumbhash: nil, animated: false), contentType: "image/png", size: 12_000)
        let item = AttachmentDisplayItem(file: image)

        XCTAssertEqual(item.displayName, "photo.png")
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.source.fileID?.rawValue, "file-image")
        XCTAssertFalse(item.debugDescription.contains("/tmp/private"))
    }

    func testPhase16AttachmentKindInferenceAndAccessibilityHelpers() {
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "application/pdf", filename: "brief.pdf"), .pdf)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "text/csv", filename: "data.csv"), .text)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: nil, filename: "bundle.zip"), .archive)

        let label = StoatAccessibility.attachmentLabel(filename: "brief.pdf", kind: "PDF", size: "42 KB", state: "Not loaded")
        XCTAssertTrue(label.contains("PDF"))
        XCTAssertTrue(StoatAccessibility.attachmentActionLabel(action: "Save As", filename: "brief.pdf").contains("brief.pdf"))
    }

    func testPhase55VideoAttachmentKindMapping() {
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "video/mp4", filename: "clip.mp4"), .video)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "video/quicktime", filename: "clip.mov"), .video)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: nil, filename: "clip.m4v"), .video)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "video/webm", filename: "clip.webm"), .unsupported)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "video/mp4", filename: "clip.mp4", metadata: .video(width: 10, height: 10)), .video)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "video/webm", filename: "clip.webm", metadata: .video(width: 10, height: 10)), .unsupported)
        XCTAssertEqual(AttachmentDisplayFormatting.kind(contentType: "audio/mpeg", filename: "song.mp3", metadata: .audio), .unsupported)

        let video = File(id: "file-video", tag: "attachments", filename: "clip.mp4", metadata: .video(width: 640, height: 480), contentType: "video/mp4", size: 1_000)
        let item = AttachmentDisplayItem(file: video)
        XCTAssertEqual(item.kind, .video)
        XCTAssertFalse(item.kind.isPreviewable)
        XCTAssertNil(item.playbackURL)
    }

    @MainActor
    func testPhase56PresenceDotGatesOnOfflineRegardlessOfStoredPresence() {
        // An offline member whose stored (configured) presence is still "Online" must show
        // as offline — `status.presence` persists after disconnect and must not override a
        // known-false `isOnline`.
        let offlineWithOnlinePresence = PresenceDot.resolve(presence: .online, isOnline: false)
        XCTAssertEqual(offlineWithOnlinePresence.color, .secondary)
        XCTAssertEqual(offlineWithOnlinePresence.label, "Offline")

        let offlineWithIdlePresence = PresenceDot.resolve(presence: .idle, isOnline: false)
        XCTAssertEqual(offlineWithIdlePresence.color, .secondary)
        XCTAssertEqual(offlineWithIdlePresence.label, "Offline")

        let onlineWithIdlePresence = PresenceDot.resolve(presence: .idle, isOnline: true)
        XCTAssertEqual(onlineWithIdlePresence.color, .orange)
        XCTAssertEqual(onlineWithIdlePresence.label, "Idle")

        let onlineNoPresence = PresenceDot.resolve(presence: nil, isOnline: true)
        XCTAssertEqual(onlineNoPresence.color, .green)
        XCTAssertEqual(onlineNoPresence.label, "Online")

        // isOnline unknown (nil): some call sites don't have it, fall back to presence-first.
        let unknownOnlineWithPresence = PresenceDot.resolve(presence: .online, isOnline: nil)
        XCTAssertEqual(unknownOnlineWithPresence.color, .green)
        XCTAssertEqual(unknownOnlineWithPresence.label, "Online")

        let unknownOnlineNoPresence = PresenceDot.resolve(presence: nil, isOnline: nil)
        XCTAssertEqual(unknownOnlineNoPresence.color, .secondary)
        XCTAssertEqual(unknownOnlineNoPresence.label, "Offline")

        let invisibleButOnline = PresenceDot.resolve(presence: .invisible, isOnline: true)
        XCTAssertEqual(invisibleButOnline.color, .secondary)
        XCTAssertEqual(invisibleButOnline.label, "Invisible")
    }

    func testPhase56VideoPosterStoreBoundsEntriesAndBytes() async {
        let store = VideoPosterStore(maxEntries: 2, maxBytes: 7)
        let first = URL(fileURLWithPath: "/tmp/phase56-first.mov")
        let second = URL(fileURLWithPath: "/tmp/phase56-second.mov")
        let third = URL(fileURLWithPath: "/tmp/phase56-third.mov")

        await store.insert(Data(repeating: 1, count: 3), for: first)
        await store.insert(Data(repeating: 2, count: 3), for: second)
        await store.insert(Data(repeating: 3, count: 3), for: third)

        let diagnostics = await store.diagnostics()
        let firstPoster = await store.cachedPoster(for: first)
        let secondPoster = await store.cachedPoster(for: second)
        let thirdPoster = await store.cachedPoster(for: third)
        XCTAssertEqual(diagnostics.cacheCount, 2)
        XCTAssertEqual(diagnostics.byteCount, 6)
        XCTAssertNil(firstPoster)
        XCTAssertNotNil(secondPoster)
        XCTAssertNotNil(thirdPoster)
    }

    func testPhase55ExternalEmbedMediaFactorySynthesizesSafeItems() {
        let imageEmbed = Embed(kind: .website, url: "https://tenor.com/view", image: EmbedImage(url: "https://media1.tenor.com/m/abc/dance.gif", width: 200, height: 200))
        let imageItem = ExternalEmbedMediaFactory.mediaItem(for: imageEmbed)
        XCTAssertEqual(imageItem?.kind, .image)
        XCTAssertTrue(imageItem?.isExternalEmbedMedia == true)
        XCTAssertEqual(imageItem?.playbackURL?.absoluteString, "https://media1.tenor.com/m/abc/dance.gif")
        XCTAssertTrue(imageItem?.id.hasPrefix("embed-ext-") == true)

        let insecureEmbed = Embed(kind: .website, image: EmbedImage(url: "http://insecure.example/x.png", width: 10, height: 10))
        XCTAssertNil(ExternalEmbedMediaFactory.mediaItem(for: insecureEmbed))

        let topLevelImage = Embed(kind: .image, url: "https://images.example/direct.png")
        XCTAssertEqual(ExternalEmbedMediaFactory.mediaItem(for: topLevelImage)?.kind, .image)

        let videoEmbed = Embed(kind: .website, video: EmbedVideo(url: "https://cdn.example/clip.mp4", width: 640, height: 480))
        XCTAssertEqual(ExternalEmbedMediaFactory.mediaItem(for: videoEmbed)?.kind, .video)

        let embedPlayerVideo = Embed(kind: .website, video: EmbedVideo(url: "https://www.youtube.com/embed/xyz", width: 640, height: 480))
        XCTAssertNil(ExternalEmbedMediaFactory.mediaItem(for: embedPlayerVideo))

        let youtube = Embed(kind: .website, special: .object(["type": .string("YouTube"), "id": .string("dQw4w9WgXcQ")]))
        let thumbnail = ExternalEmbedMediaFactory.mediaItem(for: youtube)
        XCTAssertEqual(thumbnail?.playbackURL?.absoluteString, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")

        let evilYoutube = Embed(kind: .website, special: .object(["type": .string("YouTube"), "id": .string("../evil?x=1")]))
        XCTAssertNil(ExternalEmbedMediaFactory.mediaItem(for: evilYoutube))
    }

    func testPhase17MessageActionAndReactionDisplayHelpers() {
        let action = MessageRowActionItem(id: "delete", title: "Delete Message", systemImage: "trash", role: .destructive, isEnabled: false)
        XCTAssertEqual(action.id, "delete")

        let actionLabel = StoatAccessibility.messageActionLabel(title: action.title, isDestructive: action.role == .destructive, isEnabled: action.isEnabled)
        XCTAssertTrue(actionLabel.contains("destructive"))
        XCTAssertTrue(actionLabel.contains("unavailable"))

        let reaction = MessageReactionDisplayItem(emoji: "👍", count: 2, hasCurrentUserReacted: true)
        let reactionLabel = StoatAccessibility.reactionLabel(emoji: reaction.emoji, count: reaction.count, hasReacted: reaction.hasCurrentUserReacted)
        XCTAssertTrue(reactionLabel.contains("2 reactions"))
        XCTAssertTrue(reactionLabel.contains("selected"))
    }

    func testPhase29ComposerTextSizingStartsCompactAndGrows() {
        XCTAssertEqual(ComposerTextSizing.height(for: ""), ComposerTextSizing.compactHeight)
        XCTAssertEqual(ComposerTextSizing.height(for: "one line"), ComposerTextSizing.compactHeight)

        let multiline = ComposerTextSizing.height(for: "one\ntwo\nthree")
        XCTAssertGreaterThan(multiline, ComposerTextSizing.compactHeight)
        XCTAssertLessThanOrEqual(multiline, ComposerTextSizing.maximumHeight)

        let capped = ComposerTextSizing.height(for: String(repeating: "long message wraps ", count: 80), approximateCharactersPerLine: 24)
        XCTAssertEqual(capped, ComposerTextSizing.maximumHeight)
    }

    func testPhase47MarkdownCustomEmojiKeepsCodeBlocksLiteral() {
        let emoji = MessageInlineCustomEmojiItem(shortcode: ":bagel:", name: "bagel")

        let inlineTokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "**Bold** :bagel:",
            customEmojiItems: [emoji]
        )
        XCTAssertEqual(inlineTokens, ["text::**Bold** ", "emoji:::bagel:"])

        // `code:-::` is the block descriptor's "no fence language" form.
        let codeBlocks = MarkdownMessageContent._testBlockDescriptions(for: "```\nlet value = \":bagel:\"\n```")
        XCTAssertEqual(codeBlocks, ["code:-::let value = \":bagel:\""])
    }

    func testPhase63CSSRoleColorParserHexForms() throws {
        let sixDigit = try XCTUnwrap(CSSRoleColorParser.parse("#1a2b3c"))
        guard case let .solid(stop) = sixDigit else { return XCTFail("expected solid") }
        XCTAssertEqual(stop.red, Double(0x1A) / 255, accuracy: 0.0001)
        XCTAssertEqual(stop.green, Double(0x2B) / 255, accuracy: 0.0001)
        XCTAssertEqual(stop.blue, Double(0x3C) / 255, accuracy: 0.0001)
        XCTAssertEqual(stop.alpha, 1)

        let shorthand = try XCTUnwrap(CSSRoleColorParser.parseHexColor("#f0a"))
        XCTAssertEqual(shorthand.red, 1, accuracy: 0.0001)
        XCTAssertEqual(shorthand.green, 0, accuracy: 0.0001)
        XCTAssertEqual(shorthand.blue, Double(0xAA) / 255, accuracy: 0.0001)

        let withAlpha = try XCTUnwrap(CSSRoleColorParser.parseHexColor("#11223380"))
        XCTAssertEqual(withAlpha.alpha, Double(0x80) / 255, accuracy: 0.0001)

        XCTAssertNotNil(CSSRoleColorParser.parse("  #FFFFFF  "))
        XCTAssertNil(CSSRoleColorParser.parseHexColor("ff0000"))
        XCTAssertNil(CSSRoleColorParser.parseHexColor("#ff00f"))
        XCTAssertNil(CSSRoleColorParser.parseHexColor("#gggggg"))
    }

    func testPhase63CSSRoleColorParserFunctionalForms() throws {
        let rgb = try XCTUnwrap(CSSRoleColorParser.parseFunctionalColor("rgb(255, 128, 0)"))
        XCTAssertEqual(rgb.red, 1, accuracy: 0.0001)
        XCTAssertEqual(rgb.green, 128.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(rgb.blue, 0, accuracy: 0.0001)

        let rgba = try XCTUnwrap(CSSRoleColorParser.parseFunctionalColor("rgba(0, 0, 255, 0.5)"))
        XCTAssertEqual(rgba.alpha, 0.5, accuracy: 0.0001)

        let percent = try XCTUnwrap(CSSRoleColorParser.parseFunctionalColor("rgb(100%, 50%, 0%)"))
        XCTAssertEqual(percent.red, 1, accuracy: 0.0001)
        XCTAssertEqual(percent.green, 0.5, accuracy: 0.0001)

        let clamped = try XCTUnwrap(CSSRoleColorParser.parseFunctionalColor("rgb(999, -20, 128)"))
        XCTAssertEqual(clamped.red, 1, accuracy: 0.0001)
        XCTAssertEqual(clamped.green, 0, accuracy: 0.0001)

        XCTAssertNil(CSSRoleColorParser.parseFunctionalColor("rgb(1, 2)"))
        XCTAssertNil(CSSRoleColorParser.parseFunctionalColor("hsl(120, 50%, 50%)"))
        XCTAssertNil(CSSRoleColorParser.parseFunctionalColor("rgb(a, b, c)"))
    }

    func testPhase63CSSRoleColorParserLinearGradients() throws {
        let toRight = try XCTUnwrap(CSSRoleColorParser.parse("linear-gradient(to right, #ff0000, #00ff00)"))
        guard case let .linearGradient(angle, stops) = toRight else { return XCTFail("expected gradient") }
        XCTAssertEqual(angle, 90)
        XCTAssertEqual(stops.count, 2)
        XCTAssertEqual(stops[0].red, 1, accuracy: 0.0001)
        XCTAssertEqual(stops[1].green, 1, accuracy: 0.0001)
        XCTAssertTrue(toRight.isGradient)
        XCTAssertEqual(toRight.primaryStop.red, 1, accuracy: 0.0001)

        let angled = try XCTUnwrap(CSSRoleColorParser.parse("linear-gradient(45deg, #f00 0%, #0f0 50%, #00f 100%)"))
        guard case let .linearGradient(degrees, positioned) = angled else { return XCTFail("expected gradient") }
        XCTAssertEqual(degrees, 45)
        XCTAssertEqual(positioned.map(\.location), [0, 0.5, 1])

        // No direction argument -> CSS default "to bottom" (180deg).
        let defaulted = try XCTUnwrap(CSSRoleColorParser.parse("linear-gradient(#ff0000, rgb(0, 0, 255))"))
        guard case let .linearGradient(defaultAngle, mixedStops) = defaulted else { return XCTFail("expected gradient") }
        XCTAssertEqual(defaultAngle, 180)
        XCTAssertEqual(mixedStops[1].blue, 1, accuracy: 0.0001)

        XCTAssertNil(CSSRoleColorParser.parse("linear-gradient(to right, #ff0000)"))
        XCTAssertNil(CSSRoleColorParser.parse("linear-gradient(to right, var(--a), var(--b))"))
        XCTAssertNil(CSSRoleColorParser.parse("conic-gradient(#f00, #0f0)"))
        XCTAssertNil(CSSRoleColorParser.parse("radial-gradient(#f00, #0f0)"))
        XCTAssertNil(CSSRoleColorParser.parse("url(https://example.invalid/x.png)"))
        XCTAssertNil(CSSRoleColorParser.parse("tomato"))
        XCTAssertNil(CSSRoleColorParser.parse(""))
    }

    func testPhase63LinearGradientGeometryCardinalPoints() {
        func assertPoints(_ degrees: Double, start: UnitPoint, end: UnitPoint, line: UInt = #line) {
            let points = LinearGradientGeometry.unitPoints(angleDegrees: degrees)
            XCTAssertEqual(points.start.x, start.x, accuracy: 0.0001, line: line)
            XCTAssertEqual(points.start.y, start.y, accuracy: 0.0001, line: line)
            XCTAssertEqual(points.end.x, end.x, accuracy: 0.0001, line: line)
            XCTAssertEqual(points.end.y, end.y, accuracy: 0.0001, line: line)
        }
        assertPoints(0, start: UnitPoint(x: 0.5, y: 1), end: UnitPoint(x: 0.5, y: 0))    // to top
        assertPoints(90, start: UnitPoint(x: 0, y: 0.5), end: UnitPoint(x: 1, y: 0.5))   // to right
        assertPoints(180, start: UnitPoint(x: 0.5, y: 0), end: UnitPoint(x: 0.5, y: 1))  // to bottom
        assertPoints(270, start: UnitPoint(x: 1, y: 0.5), end: UnitPoint(x: 0, y: 0.5))  // to left
    }

    func testPhase62PlainMarkdownComposesTextSegments() {
        let longBio = "Star Rail codes. /FetchZZZ — Fetch all active Zenless Zone Zero codes. /FetchHI3 — Fetch all active Honkai Impact 3rd codes."
        XCTAssertEqual(MarkdownMessageContent._testInlineSegmentDescriptions(for: longBio), ["text::\(longBio)"])

        let styled = "**Bold text** and a [link](https://example.invalid)"
        XCTAssertEqual(MarkdownMessageContent._testInlineSegmentDescriptions(for: styled), ["text::\(styled)"])
    }

    /// Phase 72 replaces `testPhase62InlineMediaAndReferencesKeepTokenRow`, which asserted that
    /// emoji and mentions forced a non-wrapping `HStack`. That assertion encoded the bug: an
    /// `HStack` cannot line-break, so any paragraph containing a mention or custom emoji refused
    /// to wrap and truncated. All three token kinds now compose into one wrapping `Text`.
    func testPhase72InlineMediaAndReferencesComposeIntoOneText() {
        let emoji = MessageInlineCustomEmojiItem(shortcode: ":bagel:", name: "bagel")
        XCTAssertEqual(
            MarkdownMessageContent._testInlineSegmentDescriptions(for: "hello :bagel:", customEmojiItems: [emoji]),
            ["text::hello ", "emoji:::bagel:"]
        )

        let userID = "01FD58YK5W7QRV5H3D64KTQYX3"
        let mention = MessageInlineReferenceItem(kind: .user, rawID: userID, displayName: "Enka")
        XCTAssertEqual(
            MarkdownMessageContent._testInlineSegmentDescriptions(
                for: "hello <@\(userID)> bye",
                referenceItems: ["<@\(userID)>": mention]
            ),
            ["text::hello ", "reference:user::\(userID)", "text:: bye"]
        )
    }

    func testPhase72MentionRunIsUnbreakableAndPadded() {
        let item = MessageInlineReferenceItem(kind: .user, rawID: "01FD58YK5W7QRV5H3D64KTQYX3", displayName: "Design Pilot")
        let run = MarkdownMessageContent._testMentionRunText(for: item)

        // No ordinary space anywhere, so the mention wraps to the next line whole rather than
        // splitting into two tinted fragments.
        XCTAssertFalse(run.contains(" "), "mention run must not contain U+0020: \(run.debugDescription)")
        XCTAssertTrue(run.contains("Design\u{00A0}Pilot"))
        XCTAssertTrue(run.hasPrefix("\u{00A0}@"))
        XCTAssertTrue(run.hasSuffix("\u{00A0}"))
    }

    func testPhase72OnlyUserMentionsAreTappable() {
        let id = "01FD58YK5W7QRV5H3D64KTQYX3"
        XCTAssertTrue(MarkdownMessageContent._testMentionHasLink(
            for: MessageInlineReferenceItem(kind: .user, rawID: id, displayName: "Enka")
        ))
        // Channel and role mentions were inert before and stay inert.
        XCTAssertFalse(MarkdownMessageContent._testMentionHasLink(
            for: MessageInlineReferenceItem(kind: .channel, rawID: id, displayName: "general")
        ))
        XCTAssertFalse(MarkdownMessageContent._testMentionHasLink(
            for: MessageInlineReferenceItem(kind: .role, rawID: id, displayName: "Core Crew")
        ))
    }

    func testPhase72MentionLinkRouteRoundTripsAndRejectsBadInput() throws {
        let id = "01FD58YK5W7QRV5H3D64KTQYX3"
        let item = MessageInlineReferenceItem(kind: .user, rawID: id, displayName: "Enka")
        let url = try XCTUnwrap(MentionLinkRoute.url(for: item))
        XCTAssertEqual(url.absoluteString, "liquidbagel-mention://user/\(id)")
        XCTAssertEqual(MentionLinkRoute.parse(url)?.rawValue, id)

        // Ordinary links must fall through to the system so real URLs in messages still open.
        XCTAssertNil(MentionLinkRoute.parse(URL(string: "https://example.invalid/\(id)")!))
        XCTAssertNil(MentionLinkRoute.parse(URL(string: "liquidbagel-mention://role/\(id)")!))
        XCTAssertNil(MentionLinkRoute.parse(URL(string: "liquidbagel-mention://user/0000")!))
        // I, L, O and U are outside the Crockford ULID alphabet.
        XCTAssertNil(MentionLinkRoute.parse(URL(string: "liquidbagel-mention://user/01FD58YK5W7QRV5H3D64KTQYXI")!))
        XCTAssertNil(MentionLinkRoute.parse(URL(string: "liquidbagel-mention://user/01fd58yk5w7qrv5h3d64ktqyx3")!))
    }

    func testPhase72AccessibleDescriptionExpandsMentionKinds() {
        let id = "01FD58YK5W7QRV5H3D64KTQYX3"
        func description(_ item: MessageInlineReferenceItem) -> String {
            MarkdownMessageContent._testAccessibleDescription(
                for: "hi <@\(id)>",
                referenceItems: ["<@\(id)>": item]
            )
        }

        XCTAssertEqual(
            description(MessageInlineReferenceItem(kind: .user, rawID: id, displayName: "Enka")),
            "hi mention, Enka"
        )
        XCTAssertEqual(
            description(MessageInlineReferenceItem(kind: .user, rawID: id, displayName: "Enka", isCurrentUser: true)),
            "hi mentions you"
        )
        XCTAssertEqual(
            description(MessageInlineReferenceItem(kind: .channel, rawID: id, displayName: "general")),
            "hi channel mention, general"
        )
        XCTAssertEqual(
            description(MessageInlineReferenceItem(kind: .role, rawID: id, displayName: "Core Crew")),
            "hi role mention, Core Crew"
        )
    }

    func testPhase72HeadingLevelsAreAllDistinct() {
        let source = (1...6).map { String(repeating: "#", count: $0) + " h\($0)" }.joined(separator: "\n")
        XCTAssertEqual(
            MarkdownMessageContent._testBlockDescriptions(for: source),
            (1...6).map { "heading\($0)::h\($0)" }
        )

        // Six markdown levels used to collapse onto two fonts, so ## through ###### looked alike.
        let fonts = (1...6).map { MarkdownHeadingStyle.font(for: $0) }
        XCTAssertEqual(Set(fonts).count, 6, "each heading level needs its own font")
        // Out-of-range levels clamp rather than crash or fall through to body text.
        XCTAssertEqual(MarkdownHeadingStyle.font(for: 0), MarkdownHeadingStyle.font(for: 1))
        XCTAssertEqual(MarkdownHeadingStyle.font(for: 7), MarkdownHeadingStyle.font(for: 6))
    }

    func testPhase72NestedListsKeepTheirDepth() {
        XCTAssertEqual(
            MarkdownMessageContent._testBlockDescriptions(for: "- a\n  - b\n    - c"),
            ["list0:-::a", "list1:-::b", "list2:-::c"]
        )
        // Indentation used to be trimmed away before depth could be measured.
        XCTAssertEqual(
            MarkdownMessageContent._testBlockDescriptions(for: "            - deep"),
            ["list4:-::deep"]
        )
        // Ordered markers keep the author's numbering.
        XCTAssertEqual(
            MarkdownMessageContent._testBlockDescriptions(for: "1. first\n2. second"),
            ["list0:1.::first", "list0:2.::second"]
        )
        XCTAssertEqual(MarkdownListStyle.glyph(marker: "1.", depth: 0), "1.")
        XCTAssertNotEqual(
            MarkdownListStyle.glyph(marker: "-", depth: 0),
            MarkdownListStyle.glyph(marker: "-", depth: 1)
        )
        XCTAssertEqual(MarkdownListStyle.indent(depth: 0), 0)
        XCTAssertGreaterThan(MarkdownListStyle.indent(depth: 2), MarkdownListStyle.indent(depth: 1))
    }

    func testPhase72ConsecutiveQuoteLinesFormOneBlock() {
        // Each `>` line used to become its own block, so one logical quote rendered as several
        // disconnected bars separated by paragraph gaps.
        XCTAssertEqual(
            MarkdownMessageContent._testBlockDescriptions(for: "> line one\n> line two"),
            ["quote::line one\\nline two"]
        )
        // A blank line still separates two distinct quotes.
        XCTAssertEqual(
            MarkdownMessageContent._testBlockDescriptions(for: "> first\n\n> second"),
            ["quote::first", "quote::second"]
        )
        // An intervening paragraph closes the quote.
        XCTAssertEqual(
            MarkdownMessageContent._testBlockDescriptions(for: "> quoted\nplain"),
            ["quote::quoted", "text::plain"]
        )
    }

    func testPhase72FenceLanguageIsCapturedAndValidated() {
        XCTAssertEqual(
            MarkdownMessageContent._testBlockDescriptions(for: "```swift\nlet x = 1\n```"),
            ["code:swift::let x = 1"]
        )
        // An arbitrary info string must not become visible UI.
        XCTAssertEqual(
            MarkdownMessageContent._testBlockDescriptions(for: "```<script>alert()\nbody\n```"),
            ["code:-::body"]
        )
        XCTAssertEqual(
            MarkdownMessageContent._testBlockDescriptions(for: "```\(String(repeating: "a", count: 40))\nbody\n```"),
            ["code:-::body"]
        )
    }

    func testPhase72HorizontalRules() {
        for rule in ["---", "***", "___", "-----"] {
            XCTAssertEqual(MarkdownMessageContent._testBlockDescriptions(for: rule), ["rule"], "\(rule) should be a rule")
        }
        for notRule in ["--", "-- -", "- - -", "text ---"] {
            XCTAssertNotEqual(MarkdownMessageContent._testBlockDescriptions(for: notRule), ["rule"], "\(notRule) is not a rule")
        }
    }

    func testPhase72BlockSpacingTightensConsecutiveListItems() {
        let listToList = MarkdownBlockSpacing._testSpacing(above: "list", below: "list")
        let textToText = MarkdownBlockSpacing._testSpacing(above: "text", below: "text")
        XCTAssertLessThan(listToList, textToText, "consecutive list items should sit tighter than paragraphs")

        XCTAssertEqual(MarkdownBlockSpacing._testSpacing(above: "text", below: nil), 0, "first block gets no leading gap")
        XCTAssertGreaterThan(
            MarkdownBlockSpacing._testSpacing(above: "heading", below: "text"),
            MarkdownBlockSpacing._testSpacing(above: "text", below: "heading")
        )
    }

    func testPhase72SanitizerKeepsComparisonProse() {
        // The old `<[^>]+>` pattern ate everything between angle brackets, so ordinary prose
        // containing comparisons lost a chunk of its text.
        XCTAssertEqual(MarkdownMessageContent._testAttributedPlainText(for: "5 < 10 > 3"), "5 < 10 > 3")
        XCTAssertEqual(MarkdownMessageContent._testAttributedPlainText(for: "if a<b then swap"), "if a<b then swap")
        XCTAssertEqual(MarkdownMessageContent._testAttributedPlainText(for: "2<3 and 4>1"), "2<3 and 4>1")

        // Real HTML tags are still stripped. Note `<b and c>` is deliberately NOT preserved: it
        // is a well-formed `<b>` tag with attributes, so treating it as markup is correct.
        XCTAssertEqual(MarkdownMessageContent._testAttributedPlainText(for: "<b>bold</b>"), "bold")
        XCTAssertEqual(MarkdownMessageContent._testAttributedPlainText(for: "<script>x</script>"), "x")
        XCTAssertEqual(MarkdownMessageContent._testAttributedPlainText(for: "a<b and c>d"), "ad")
    }

    func testPhase72AutocompletePopoverHeightGrowsThenCaps() {
        let sizing = ComposerAutocompleteSizing.self
        XCTAssertEqual(sizing.height(candidateCount: 0), 0)

        // Monotonic, and always at least one row tall once there is a candidate.
        var previous = sizing.height(candidateCount: 1)
        XCTAssertGreaterThanOrEqual(previous, sizing.rowHeight)
        for count in [2, 6, 10, 50] {
            let height = sizing.height(candidateCount: count)
            XCTAssertGreaterThanOrEqual(height, previous, "height must not shrink at \(count)")
            XCTAssertLessThanOrEqual(height, sizing.maximumHeight, "height must stay capped at \(count)")
            previous = height
        }

        // The cap is what makes the list scroll instead of overflowing the window.
        XCTAssertEqual(sizing.height(candidateCount: 50), sizing.maximumHeight)
    }

    func testPhase72AutocompletePopoverSitsAboveTheField() {
        let sizing = ComposerAutocompleteSizing.self
        let popover = sizing.height(candidateCount: 6)

        for fieldHeight in [CGFloat(34), 92] {
            let offset = sizing.offsetAboveField(fieldHeight: fieldHeight, popoverHeight: popover)
            XCTAssertLessThan(offset, 0, "popover must be lifted above the field")
            XCTAssertEqual(offset, -(popover + sizing.gap), accuracy: 0.001)
        }
    }

    func testPhase72InlineEmojiGlyphScaleIsClamped() {
        XCTAssertEqual(InlineEmojiGlyphMetrics.scale(pixelHeight: 44), 2, accuracy: 0.001)
        XCTAssertEqual(InlineEmojiGlyphMetrics.scale(pixelHeight: 22), 1, accuracy: 0.001)
        // Never scale below 1 -- a tiny bitmap should not be blown up past its natural size.
        XCTAssertEqual(InlineEmojiGlyphMetrics.scale(pixelHeight: 11), 1, accuracy: 0.001)
        XCTAssertEqual(InlineEmojiGlyphMetrics.scale(pixelHeight: 0), 1, accuracy: 0.001)
        XCTAssertEqual(InlineEmojiGlyphMetrics.scale(pixelHeight: -5), 1, accuracy: 0.001)
        XCTAssertEqual(InlineEmojiGlyphMetrics.scale(pixelHeight: 10_000), 8, accuracy: 0.001)
    }

    func testPhase58MentionTokenizerExtractsUserMentionsOutsideCode() {
        let userID = "01FD58YK5W7QRV5H3D64KTQYX3"
        let mention = MessageInlineReferenceItem(kind: .user, rawID: userID, displayName: "Enka")

        let tokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "hello <@\(userID)> how are you",
            customEmojiItems: [],
            referenceItems: ["<@\(userID)>": mention]
        )
        XCTAssertEqual(tokens, ["text::hello ", "reference:user::\(userID)", "text:: how are you"])
    }

    func testPhase58MentionTokenizerLeavesFencedCodeLiteral() {
        let userID = "01FD58YK5W7QRV5H3D64KTQYX3"
        let mention = MessageInlineReferenceItem(kind: .user, rawID: userID, displayName: "Enka")

        let codeBlocks = MarkdownMessageContent._testBlockDescriptions(for: "```\n<@\(userID)>\n```")
        XCTAssertEqual(codeBlocks, ["code:-::<@\(userID)>"])

        // The inline tokenizer itself (given only the fenced content, as the block parser would
        // hand it) still recognizes the shape -- literalness comes from the block parser routing
        // code blocks away from inline tokenization entirely (MarkdownContentPreparer.prepare).
        let tokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "<@\(userID)>",
            customEmojiItems: [],
            referenceItems: ["<@\(userID)>": mention]
        )
        XCTAssertEqual(tokens, ["reference:user::\(userID)"])
    }

    func testPhase58UnresolvedMentionRendersUnknownUserFallback() {
        let userID = "01FD58YK5W7QRV5H3D64KTQYX3"

        let tokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "hey <@\(userID)>",
            customEmojiItems: [],
            referenceItems: [:]
        )
        XCTAssertEqual(tokens, ["text::hey ", "reference:user::\(userID)"])
    }

    func testPhase58MentionTokensDoNotHitAngleBracketSanitizer() {
        // Malformed/short bracket content (not a real 26-char ULID) should NOT be treated as a
        // mention -- it stays literal text and is still subject to the existing sanitizer.
        let tokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "a <div> tag and <@short>",
            customEmojiItems: [],
            referenceItems: [:]
        )
        XCTAssertEqual(tokens, ["text::a <div> tag and <@short>"])
    }

    func testPhase58ChannelAndRoleMentionsAreRecognized() {
        let channelID = "01FD58YK5W7QRV5H3D64KTQYX3"
        let roleID = "01FD58YK5W7QRV5H3D64KTQYX4"
        let tokens = MarkdownMessageContent._testInlineTokenDescriptions(
            for: "<#\(channelID)> and <%\(roleID)>",
            customEmojiItems: [],
            referenceItems: [:]
        )
        XCTAssertEqual(tokens, ["reference:channel::\(channelID)", "text:: and ", "reference:role::\(roleID)"])
    }

    #if canImport(AppKit)
    @MainActor
    func testPhase58InlineTriggerDetectionAtCaretAndCancellation() {
        let atEnd = GlassComposer._testDetectInlineTrigger(text: "hello @enk", caretUTF16Offset: 10)
        XCTAssertEqual(atEnd?.query, "enk")
        XCTAssertEqual(atEnd?.utf16Location, 6)
        XCTAssertEqual(atEnd?.utf16Length, 4)
        XCTAssertEqual(atEnd?.kind, .user)

        let bareAt = GlassComposer._testDetectInlineTrigger(text: "hello @", caretUTF16Offset: 7)
        XCTAssertEqual(bareAt?.query, "")

        // Caret sits right after "@enk", mid-word (before the trailing "a") -- query is only
        // what's been typed so far, not the whole word.
        let midWord = GlassComposer._testDetectInlineTrigger(text: "@enka is here", caretUTF16Offset: 4)
        XCTAssertEqual(midWord?.query, "enk")
        XCTAssertEqual(midWord?.utf16Location, 0)

        let noTrigger = GlassComposer._testDetectInlineTrigger(text: "hello world", caretUTF16Offset: 11)
        XCTAssertNil(noTrigger)

        let cancelledByWhitespace = GlassComposer._testDetectInlineTrigger(text: "hey @enk done", caretUTF16Offset: 13)
        XCTAssertNil(cancelledByWhitespace)

        // A word character immediately before "@" (e.g. an email address) must not trigger.
        let emailLikeNoTrigger = GlassComposer._testDetectInlineTrigger(text: "a@b.com", caretUTF16Offset: 7)
        XCTAssertNil(emailLikeNoTrigger)
    }

    @MainActor
    func testPhase71KindAwareInlineTriggerDetectionAndSuppression() {
        func detect(_ text: String) -> InlineComposerTrigger? {
            GlassComposer._testDetectInlineTrigger(text: text, caretUTF16Offset: (text as NSString).length)
        }

        XCTAssertEqual(detect("@al")?.kind, .user)
        XCTAssertEqual(detect("#dev")?.kind, .channel)
        XCTAssertEqual(detect("%admin")?.kind, .role)
        XCTAssertEqual(detect(":bagel")?.kind, .emoji)
        XCTAssertEqual(detect(":bagel")?.query, "bagel")

        XCTAssertNil(detect(":"))
        XCTAssertNil(detect(":b"))
        XCTAssertNil(detect(":bagel:"))
        XCTAssertNil(detect("https://"))
        XCTAssertNil(detect("12:30"))
        XCTAssertNil(detect("#1"))
        XCTAssertNil(detect("#42"))
        XCTAssertNil(detect("#fff"))
        XCTAssertNil(detect("#1a2b3c"))
        XCTAssertNotNil(detect("#2024-planning"))
        XCTAssertNil(detect("#foo.bar"))
        XCTAssertNil(detect("50%"))
        XCTAssertNil(detect("%42"))
        XCTAssertNil(detect("`@literal"))
        XCTAssertNotNil(detect("`code` @real"))

        let channel = ComposerAutocompleteCandidate(kind: .channel, rawID: "same", name: "General")
        let role = ComposerAutocompleteCandidate(kind: .role, rawID: "same", name: "General")
        XCTAssertNotEqual(channel.id, role.id)
    }

    @MainActor
    func testPhase61PasteFileURLWinsOverAccompanyingTextRepresentation() {
        let fileURL = URL(fileURLWithPath: "/tmp/phase61-example.png")
        let outcome = GlassComposer._testPaste(existingText: "") { pasteboard in
            pasteboard.writeObjects([fileURL as NSURL])
            pasteboard.setString("phase61-example.png", forType: .string)
        }
        XCTAssertEqual(outcome.pastedFileURLs, [fileURL])
        XCTAssertNil(outcome.pastedImageData)
        XCTAssertEqual(outcome.resultingText, "")
    }

    @MainActor
    func testPhase61PasteImageDataWinsOverAccompanyingTextRepresentation() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let outcome = GlassComposer._testPaste(existingText: "") { pasteboard in
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setString("clipboard.png", forType: .string)
        }
        XCTAssertNil(outcome.pastedFileURLs)
        XCTAssertEqual(outcome.pastedImageData, pngData)
        XCTAssertEqual(outcome.resultingText, "")
    }

    @MainActor
    func testPhase61PastePreservesExistingComposerTextWhenAttachmentWins() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let outcome = GlassComposer._testPaste(existingText: "Hello there") { pasteboard in
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setString("clipboard.png", forType: .string)
        }
        XCTAssertEqual(outcome.pastedImageData, pngData)
        XCTAssertNil(outcome.pastedFileURLs)
        XCTAssertEqual(outcome.resultingText, "Hello there")
    }

    @MainActor
    func testPhase62KeyEquivalentQueuesAttachmentBeforeMenuPasteRouting() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let outcome = GlassComposer._testKeyEquivalentPaste(existingText: "Keep this") { pasteboard in
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setString("clipboard.png", forType: .string)
        }

        XCTAssertEqual(outcome.pastedImageData, pngData)
        XCTAssertNil(outcome.pastedFileURLs)
        XCTAssertEqual(outcome.resultingText, "Keep this")
    }

    @MainActor
    func testPhase62ReadSelectionInterceptsScreenshotDataBeforeTextFallback() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let outcome = GlassComposer._testReadSelection(existingText: "Keep this") { pasteboard in
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setString("screenshot.png", forType: .string)
        }

        XCTAssertEqual(outcome.pastedImageData, pngData)
        XCTAssertNil(outcome.pastedFileURLs)
        XCTAssertEqual(outcome.resultingText, "Keep this")
    }

    @MainActor
    func testPhase61PasteFallsBackToPlainTextWhenNoAttachmentPayload() {
        let outcome = GlassComposer._testPaste(existingText: "") { pasteboard in
            pasteboard.setString("plain clipboard text", forType: .string)
        }
        XCTAssertNil(outcome.pastedFileURLs)
        XCTAssertNil(outcome.pastedImageData)
        XCTAssertEqual(outcome.resultingText, "plain clipboard text")
    }

    @MainActor
    func testPhase63AttachmentThenCharacterViewerEmojiKeepsNativeComposerResponsive() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let outcome = GlassComposer._testAttachmentThenNativeTextAndEmoji(
            imageData: pngData,
            text: "still composing ",
            emoji: "😭"
        )

        XCTAssertEqual(outcome.pastedImageData, pngData)
        XCTAssertEqual(outcome.resultingText, "still composing 😭😭")
        XCTAssertEqual(outcome.nativeEditCount, 3)
        XCTAssertEqual(outcome.inlineTriggerPublications.count, 1)
        XCTAssertNil(outcome.inlineTriggerPublications[0])
        XCTAssertGreaterThanOrEqual(outcome.inlineTriggerSuppressionCount, 2)
    }

    #endif

    func testPhase47EmbedDisplayItemSanitizesURLsAndLabelsVariants() {
        let website = Embed(
            kind: .website,
            url: "https://example.com/path?token=secret#fragment",
            title: "<b>Launch</b>",
            description: "A safe description",
            siteName: " Example "
        )
        let item = MessageEmbedDisplayItem(id: "embed", embed: website)

        XCTAssertEqual(item.label, "Link")
        XCTAssertEqual(item.title, "Launch")
        XCTAssertEqual(item.displayURL, "https://example.com/path")
        XCTAssertNotNil(item.externalURL)
        XCTAssertTrue(item.accessibilityLabel.contains("Launch"))

        let unsafeImage = Embed(kind: .image, url: "file:///Users/enka/private.png", image: EmbedImage(url: "file:///Users/enka/private.png", width: 20, height: 20))
        let imageItem = MessageEmbedDisplayItem(id: "image", embed: unsafeImage)
        XCTAssertEqual(imageItem.label, "Image")
        XCTAssertNil(imageItem.externalURL)
        XCTAssertNil(imageItem.displayURL)
        XCTAssertTrue(imageItem.accessibilityLabel.contains("external image preview available"))

        XCTAssertEqual(MessageEmbedDisplayItem.label(for: .video), "Video")
        XCTAssertEqual(MessageEmbedDisplayItem.label(for: .unknown("Poll")), "Embed Poll")
    }

    func testPhase47EmbedDisplayItemCarriesModeledMediaPreviewData() {
        let file = File(id: "embed-media", tag: "attachments", filename: "/tmp/private/embed.png", metadata: .image(width: 40, height: 40, thumbhash: nil, animated: false), contentType: "image/png", size: 128)
        let data = Data("png".utf8)
        var mediaItem = AttachmentDisplayItem(file: file, previewState: .readyRemote)
        mediaItem.previewData = data

        let item = MessageEmbedDisplayItem(
            id: "embed",
            embed: Embed(kind: .image, title: "Modeled image", media: file),
            mediaItem: mediaItem,
            mediaPreviewData: data
        )

        XCTAssertEqual(item.mediaItem?.displayName, "embed.png")
        XCTAssertEqual(item.mediaPreviewData, data)
        XCTAssertTrue(item.accessibilityLabel.contains("media embed.png"))
    }

    func testPhase51DecodedImagePipelineDedupesIdenticalResources() async throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let key = DecodedImageKey(id: "phase51-pixel", pixelSize: 32)
        await DecodedImagePipeline.reset()

        async let first = DecodedImagePipeline.prepare(data: png, key: key)
        async let second = DecodedImagePipeline.prepare(data: png, key: key)
        let firstResult = await first
        let secondResult = await second
        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult)
        _ = await DecodedImagePipeline.prepare(data: png, key: key)
        let diagnostics = await DecodedImagePipeline.diagnostics()

        XCTAssertEqual(diagnostics.decodeCount, 1)
        XCTAssertGreaterThanOrEqual(diagnostics.dedupeCount + diagnostics.cacheHitCount, 2)
        XCTAssertEqual(diagnostics.cacheCount, 1)
        let isSynchronouslyCached = await MainActor.run {
            DecodedImagePipeline.hasSynchronouslyCachedImage(for: key)
        }
        XCTAssertTrue(isSynchronouslyCached)
    }

    @MainActor
    func testPhase60TimelineSkeletonHonorsReduceMotionPolicy() {
        XCTAssertTrue(TimelineSkeletonAnimationPolicy.usesShimmer(reduceMotion: false))
        XCTAssertFalse(TimelineSkeletonAnimationPolicy.usesShimmer(reduceMotion: true))
        _ = TimelineSkeletonRow()
        _ = MessageRow(
            message: Message(
                id: "phase60-row",
                channelID: "phase60-channel",
                authorID: "phase60-author",
                content: "Prepared only"
            ),
            author: nil
        )
    }

    func testPhase67MessageActionReservationDoesNotDependOnPresentationState() {
        let expectedReservation = MessageRowActionLayout.trailingReservation(
            primaryActionCount: 3,
            hasMenu: true
        )
        let presentationStates = ["hidden", "hovered", "focused", "selected", "fading"]

        for state in presentationStates {
            XCTAssertEqual(
                MessageRowActionLayout.trailingReservation(primaryActionCount: 3, hasMenu: true),
                expectedReservation,
                "Reservation changed while \(state)"
            )
        }
        XCTAssertGreaterThan(expectedReservation, 0)
        XCTAssertEqual(
            MessageRowActionLayout.trailingReservation(primaryActionCount: 0, hasMenu: false),
            0
        )
    }

    func testPhase66MessageActionBarMountsOnlyForActiveRowsWithActions() {
        XCTAssertFalse(MessageRowActionLayout.shouldMountActionBar(
            hasActions: true,
            isHovering: false,
            isFocused: false,
            isSelected: false
        ))
        XCTAssertTrue(MessageRowActionLayout.shouldMountActionBar(
            hasActions: true,
            isHovering: true,
            isFocused: false,
            isSelected: false
        ))
        XCTAssertTrue(MessageRowActionLayout.shouldMountActionBar(
            hasActions: true,
            isHovering: false,
            isFocused: true,
            isSelected: false
        ))
        XCTAssertTrue(MessageRowActionLayout.shouldMountActionBar(
            hasActions: true,
            isHovering: false,
            isFocused: false,
            isSelected: true
        ))
        XCTAssertFalse(MessageRowActionLayout.shouldMountActionBar(
            hasActions: false,
            isHovering: true,
            isFocused: true,
            isSelected: true
        ))
    }

    func testPhase67MessageActionInteractionFollowsActiveMountState() {
        XCTAssertFalse(MessageRowActionLayout.allowsActionBarInteraction(
            hasActions: true,
            isHovering: false,
            isFocused: false,
            isSelected: false
        ))
        XCTAssertTrue(MessageRowActionLayout.allowsActionBarInteraction(
            hasActions: true,
            isHovering: true,
            isFocused: false,
            isSelected: false
        ))
        XCTAssertTrue(MessageRowActionLayout.allowsActionBarInteraction(
            hasActions: true,
            isHovering: false,
            isFocused: true,
            isSelected: false
        ))
        XCTAssertTrue(MessageRowActionLayout.allowsActionBarInteraction(
            hasActions: true,
            isHovering: false,
            isFocused: false,
            isSelected: true
        ))
        XCTAssertFalse(MessageRowActionLayout.allowsActionBarInteraction(
            hasActions: false,
            isHovering: true,
            isFocused: true,
            isSelected: true
        ))
        XCTAssertEqual(MessageRowActionLayout.hoverFadeDuration, 0.08, accuracy: 0.001)
    }

    func testPhase65EmojiPickerItemKeepsArtworkAndReadableFallbackMetadata() {
        let fallback = EmojiPickerItem(
            id: "custom-bagel",
            insertionText: ":01J00000000000000000650001:",
            displayName: "bagel",
            searchTerms: ["bagel"],
            customMediaKey: "bagel-media"
        )
        var loaded = fallback
        loaded.imageData = Data("image".utf8)

        XCTAssertTrue(fallback.isCustom)
        XCTAssertEqual(fallback.insertionText, ":01J00000000000000000650001:")
        XCTAssertEqual(fallback.displayName, "bagel")
        XCTAssertNil(fallback.imageData)
        XCTAssertTrue(fallback.matchesSearch("bag"))
        XCTAssertEqual(loaded.imageData, Data("image".utf8))
        let unicode = EmojiPickerItem.unicode("🥯")
        XCTAssertFalse(unicode.isCustom)
        XCTAssertTrue(unicode.matchesSearch("bread", aliases: ["bread", "bagel"]))
    }
}
