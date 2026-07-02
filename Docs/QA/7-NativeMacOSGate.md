# QA Lane 7 - Native macOS Gate

Covers VoiceOver, keyboard access, high contrast, Reduce Transparency, menus, windows, and Settings organization.

## Prerequisites

- macOS accessibility settings available: VoiceOver, Increase Contrast, Reduce Transparency, Full Keyboard Access.
- Official client (or native macOS apps like Messages) as the behavior reference for menu/window conventions.

## Evidence Rules

Categorical outcomes only.

## Checklist

| # | Step | Expected | Result | Evidence note |
| --- | --- | --- | --- | --- |
| 1 | Command-comma opens Settings; visit Account, Sessions, Connection, Appearance, Notifications, Developer tabs | Current settings window with all six tabs; visual preferences live under Appearance | | |
| 2 | Open Appearance Settings from the app menu and from the quick switcher | Both routes land on the Appearance tab | | |
| 3 | Adjust the Liquid Glass transparency slider | Panels, sidebars, and toolbars update together; value persists across relaunch | | |
| 4 | Enable macOS Reduce Transparency | Solid surfaces override the slider | | |
| 5 | Enable Increase Contrast | Strokes/readability stay strong across shell, timeline, member panel, settings | | |
| 6 | Run a VoiceOver pass: settings tabs, quick switcher, server rail, channel sidebar, timeline rows, composer, member panel, badges | Elements have sensible labels; unread/mention badges announce counts; no unlabeled controls | | |
| 7 | Full Keyboard Access: tab through the main shell and settings; use Cmd-K quick switcher, Cmd-N New DM picker, and other wired shortcuts | Focus order sane; shortcuts fire; no keyboard traps | | |
| 8 | Audit the menu bar (App, File, Edit, View, Window, Help) against native conventions | Commands route correctly; no dead items; Window management behaves natively | | |
| 9 | Exercise multiple windows/spaces if supported, full screen, and window restoration | Native behavior without layout breakage | | |
| 10 | Check role-color readability in both light/dark and Increase Contrast modes | Sanitized colors keep contrast; fallbacks diagnosed, not broken | | |

## Matrix Rows Unlocked

| ParityMatrix row | Promotion condition |
| --- | --- |
| UI/platform / keyboard shortcuts | Step 7 passes plus the Phase 50 menu-route check in step 2 |
| UI/platform / accessibility | Step 6 VoiceOver pass completes with fixes filed for any unlabeled controls |
| UI/platform / high contrast | Steps 5, 10 pass |
| UI/platform / reduce transparency | Steps 3-4 pass |
| UI/platform / native macOS window/menu behavior | Steps 8-9 pass |
| UI/platform / settings organization | Steps 1-2 pass |
| Server/community / roles (readability portion) | Step 10 passes |
