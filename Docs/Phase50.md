# Phase 50 - Native macOS Appearance Polish

Phase 50 narrows the UI/platform parity work to native settings organization, command routing, and Liquid Glass appearance control. It does not add Stoat API routes, hidden networking, persistent message caches, or live-sensitive parity claims.

## Implemented Behavior

- App Settings now includes a dedicated Appearance tab for message density, Liquid Glass transparency, inline image preview policy, developer controls, and member-panel visibility.
- The app command router, macOS Settings menu, and quick switcher now expose an Appearance Settings route.
- Liquid Glass transparency is a persisted numeric preference instead of only a binary reduced-glass toggle.
- The old `reduceGlassIntensity` preference still decodes for older stored payloads and migrates to low Liquid Glass transparency.
- Shared glass panels, sidebars, and toolbars read one environment-driven transparency value, while macOS Reduce Transparency still forces solid surfaces.

## Safety Boundaries

- No tokens, credentials, session data, profile content, message bodies, raw server responses, or local paths are stored in the new preference.
- System Reduce Transparency remains stronger than the Liquid Glass slider.
- Existing high-contrast and reduce-motion behavior remains intact.
- Native-platform parity rows stay `partial` until manual macOS settings, VoiceOver, high-contrast, and reduce-transparency QA is completed.

## Verification

```sh
swift test --package-path Packages/StoatDesignSystem
swift test --package-path Packages/StoatPersistence
swift test --package-path Packages/StoatFeatures --filter 'testCommandRouter|testQuickSwitcher|testAppearancePreferences'
git diff --check
Scripts/check.sh
```

## Manual QA Checklist

1. Open Settings with Command-comma and confirm the current settings window appears.
2. Open Appearance Settings from the app menu and quick switcher.
3. Adjust Liquid Glass transparency and confirm panels, sidebars, and toolbars update together.
4. Save Appearance, quit, relaunch, and confirm the saved transparency returns.
5. Enable macOS Reduce Transparency and confirm solid surfaces override the slider.
6. Enable Increase Contrast and confirm strokes/readability remain strong.
7. Run a short VoiceOver pass through the settings tabs, quick switcher, sidebars, timeline, and composer.
