# NSH Split composition

Split uses one retained native ResizeHandle for pointer capture. Two keyed pane
hosts project the existing ChildRenderer signals; they add geometry and clipping,
not a second source tree. A semantic divider supplies the public focus/keymap and
accessibility action bindings absent from ResizeHandle props. It uses native
focus observations and scoped bindings rather than a separate focus controller.

## Motion inventory

| State change | Mechanism | Reduced motion |
| --- | --- | --- |
| Accepted pointer resize | Immediate source-driven track geometry; native handle owns capture | Same direct geometry |
| Refused pointer resize | Accepted source remains authoritative; no stored preview | Same accepted geometry |
| Programmatic ratio/pixel change | Immediate source-driven geometry | Same immediate geometry |
| Parent resize | Recompute available track; preserve pixel source | Same layout |
| Pane reorder | Native keyed each retains editor elements | Same retained layout |
| Explicit resize animation | Rejected atomically until interruptible native track animation is qualified | Same explicit rejection |

Default gap/handle geometry, min/max proposal constraints and pixel/fraction units
follow the canonical shared Split geometry. Controlled zero closure follows the
shared API and Web path; the older Swift fraction normalization treats zero as
its absent-value fallback and is not copied into the NSH implementation.

The five passing Headless tests cover native drag/refusal, pane bounds, source/parent
resizing, reorder identity/focus/draft, RTL handle placement/delta, zero-width
input suppression, scoped keyboard behavior, atomic animation rejection and the
shared infeasible-constraint math. The main session ran them as part of the full
126-test adapter/OCaml suite. Light/dark visual checks, actual desktop motion and
screen-reader output remain qualification work; see the component-batch evidence
under docs/agent-guide/review-probes/2026-11-11/.
