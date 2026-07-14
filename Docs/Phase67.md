# Phase 67 - Stable Message Actions And Scroll Performance Verification

Phase 67 follows the successful Phase 66 scrolling-freeze retest. The old runaway signatures are absent and CPU settles within the two-second gate, but live QA found a rare message-action flicker while pointer tracking changed rapidly. This phase treats short active-scroll CPU spikes as expected work and targets bounded main-thread work, stable interaction, and a smooth action transition instead of an artificial zero-spike requirement.

## Message Action Stability

- Message rows retain the Phase 65 fixed trailing reservation, so hover, focus, selection, and the transition cannot change content width, wrapping, height, or timeline position.
- The action bar still mounts only for hovered, focused, or selected rows. Inactive rows still contain no hidden `Menu` or `AppKitPopUpAdaptor`.
- Pointer-driven action appearance and removal use an 80 ms opacity-only ease-out transition. Focused and selected-row visibility remains persistent and is not delayed.
- Duplicate `onHover` values are ignored to avoid redundant SwiftUI invalidations during tracking-area refreshes.
- Hit testing and accessibility exposure follow the active mount state, so disappearing controls stop accepting interaction immediately. No delayed hover-exit task or menu-retention grace period is introduced.

## Automated Proof

- StoatUI tests verify the trailing reservation is identical for hidden, hovered, focused, selected, and fading presentation states.
- Mount-policy coverage continues to prove inactive rows and rows without actions mount no action bar, while hovered, focused, and selected rows do.
- Phase 67 interaction-policy coverage proves inactive or actionless rows are not interactive, active rows are interactive, and the hover transition remains fixed at 80 ms.
- Existing Phase 63-66 timeline, composer, visibility-lease, row-equality, geometry-reservation, custom-media, and action-mount tests remain regression coverage.

## Live QA Required

1. Slowly cross message boundaries, scrub rapidly across several rows, and rapid-scroll with the pointer parked over the timeline. Actions must fade cleanly without flashing, row movement, or rewrapping.
2. Verify primary hover actions, ellipsis actions, full-row right-click menus, keyboard focus, and selected-row actions throughout the transition.
3. Capture a Release Time Profiler sample during rapid scrolling with the pointer over and outside the timeline. No `AppKitPopUpAdaptor` dominance, full-history `measureEstimates` loop, or sustained app-owned main-thread operation above 50 ms may appear.
4. Confirm interaction remains smooth and CPU settles below 10% within two seconds. The instantaneous CPU peak during active scrolling is recorded but is not itself a failure.
5. Reconfirm jump-to-newest, load-older position preservation, and unread-separator scrolling.

Large-channel performance remains `partial` until this live pass completes. Once green, resume the remaining Phase 65 resize and emoji-picker QA.
