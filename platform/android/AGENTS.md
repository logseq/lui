# Android renderer

- Follow the current Material 3 Expressive specifications throughout Android defaults and interactions, using official current Compose Material components where available. Legacy baseline components are not the migration target.
- Use Material typography, color, shape, motion, accessibility semantics and touch targets. Do not copy Apple point sizes, tint rules or control implementations into Android defaults.
- Respect explicitly authored application styling without replacing native control behavior or disabling accessibility.
- Keep menu visibility and transitions in native controls; shared models own actions and product selections.
- Verify behavior, including focus, keyboard, dismissal, disabled/selected states and actual transitions. Importing a Material component does not establish conformance.
- Keep Apple rendering and styling independent. Android changes must not change iOS layout or styles.
- Prefer smaller local fixes; do not add a second renderer, global menu manager or custom imitation of an official Material component.
