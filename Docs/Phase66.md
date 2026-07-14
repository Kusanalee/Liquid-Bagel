# Phase 66 - Scrolling Freeze Regression Repair

Phase 66 responds to the Phase 65 live blocker: the app froze while scrolling the capped timeline. The supplied 1.616-second sample spent 632 of 718 platform-view update samples in SwiftUI's macOS `AppKitPopUpAdaptor`. This differs from the Phase 64 channel-load failure: full-history `measureEstimates` work was secondary rather than dominant.

## Root Cause

- Phase 65 moved message actions into a top-trailing overlay and kept that overlay mounted at zero opacity for every row so hover could not change row geometry.
- Each overlay contained a SwiftUI `Menu`, which materialized an AppKit pop-up and resolved every action label and symbol even while hidden.
- Scrolling realized new lazy rows and repeatedly performed this hidden menu work on the main thread.

## Repair

- The fixed trailing reservation remains unconditional whenever actions exist, so message width, wrapping, height, and timeline position do not depend on hover, focus, or selection.
- The action bar now mounts only for an active hovered, focused, or selected row. Inactive rows contain no hidden `Menu` or pop-up adaptor.
- Primary actions, the ellipsis menu, full-row context menus, keyboard focus, selection, and action availability rules are unchanged.
- The safe-area-inset chat layout, default timeline layout priority, render identity, row preparation, and media visibility leases are unchanged.

## Automated Proof

- StoatUI tests keep the Phase 65 geometry-reservation assertion.
- A Phase 66 mount-policy test proves inactive rows and rows without actions do not mount the action bar, while hovered, focused, and selected rows do.
- Existing Phase 63-65 timeline, composer, visibility-lease, action-layout, and custom-media tests remain regression coverage.

## Live QA Required

1. Load the capped 250-message channel and rapid-scroll for ten seconds with the pointer over the timeline, then repeat with the pointer outside it.
2. Confirm no freeze, beachball, row jump, movement, or rewrapping; CPU must settle below 10% within two seconds.
3. Capture a short redacted sample during the run. Mass `AppKitPopUpAdaptor` updates and a full-history `measureEstimates` loop must both be absent.
4. Verify primary hover buttons, the ellipsis menu, full-row right-click menus, and focused/selected-row actions.
5. Reconfirm jump-to-newest, load-older position preservation, and unread scrolling.

Large-channel performance remains `partial` until this live gate passes. Emoji-picker and broader Phase 65 QA remain paused behind the scrolling blocker.
