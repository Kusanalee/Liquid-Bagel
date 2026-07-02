# QA Lane 1 - Freeze Gate

Run this lane first. If it fails, pause all other parity dogfood and fix the snapshot, preparation, or bounded-cache seam before continuing (Phase 54 rule).

## Prerequisites

- A server with a large thread (the supplied Phase 52 sample scenario) and a member-heavy server (ideally 2,000+ members).
- Instruments or `sample` ready to capture the app during the scenario.
- Member panel open during the capture.

## Evidence Rules

Record categorical outcomes only. No credentials, MFA material, payload bodies, private URLs, local paths, full IDs, or user content in notes or diagnostics copies.

## Checklist

| # | Step | Expected | Result | Evidence note |
| --- | --- | --- | --- | --- |
| 1 | Open the large thread with the member panel open and capture a sample while scrolling, typing, and opening menus | No sustained app-owned main-thread operation above 50 ms | | |
| 2 | Inspect the sample stacks | No hydration or identity-merge stack dominates the sample | | |
| 3 | Trigger member hydration (switch to the large server) and watch Phase 52 diagnostics counters | Exactly one batched member snapshot installation and one identity batch per hydration response | | |
| 4 | Let the session run several minutes with media-heavy channels | Memory stabilizes within the 32/128/64 MB raw-image/decoded-image/attachment-preview budgets | | |
| 5 | During preparation (channel/server switches), interact continuously | Typing, scrolling, menus stay responsive; member presentation stays coherent (last interactive view retained) | | |
| 6 | While a loaded timeline is visible, let avatars, attachment previews, custom emoji, and identity hydration finish | Existing message groups never disappear; first-time preparation shows an explicit progress state instead of a blank timeline | | |
| 7 | Copy Developer Verification diagnostics after the run | Main-thread budget-violation counter is zero or explained; timeline cancellation/stale counts are bounded; no redaction leaks | | |

## Matrix Rows Unlocked

| ParityMatrix row | Promotion condition |
| --- | --- |
| UI/platform / performance with large channels | Steps 1, 2, 4-6 pass on the large-thread repeat |
| UI/platform / performance with large servers | Steps 1, 2, 3, 5 pass with the member panel open |

Both rows stay `partial` if any step fails; record the failing step and file the fix in the owning Phase 52 seam before re-running.
