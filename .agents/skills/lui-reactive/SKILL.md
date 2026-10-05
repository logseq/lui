---
name: lui-reactive
description: "LUI reactive API rules for view/example code (OCaml + lui_ppx). Use whenever writing or editing code that builds Lui_elements views: reactive sugar, dyn ban, if_/keyed usage, signal conventions."
---

# LUI Reactive API Rules

`lui_ppx` is enabled for view code. `reactive` is the single reactive
form; `dyn` is a ppx expansion target and is never called directly.

## Hard rules

1. **Never call `Lui_elements.dyn` directly.** It exists only as the ppx
   expansion target for children-position `reactive`. Writing `dyn` in
   view code is a bug.
2. **Never write `Signal.map` / `~p_signal:` / `Signal.value` plumbing
   by hand for reactive props or test/source signals** — `reactive`
   covers all of it.

## The reactive vocabulary

```ocaml
(* prop position: ~p:(reactive f s) — expands to ~p_signal:(Signal.map f s) *)
button ~icon:(reactive (fun v -> if v then `eye_off else `eye) visible) []

(* children position: model -> subtree (this IS dyn, via ppx) *)
column [ reactive (fun m -> pane_of m.tab) model_s ]

(* custom comparator — ~equal leads, matching `dyn ~equal f s` order.
   Omit ~equal when (=) suffices (the default). *)
reactive ~equal:(fun a b -> a.id = b.id) (fun m -> view_of m) model_s

(* signal of elements / multi-signal tuple *)
reactive elements_s
reactive (fun (a, b) -> combined a b) s1 s2
```

## Structural primitives (only when signal-driven)

```ocaml
if_ ~test:(reactive (fun v -> v <> "") value) (button ...)   (* mount/unmount *)
keyed ~source:items_s ~key:(fun it -> it.id) ~cmp:Int.compare
  ~mount:(fun item_s -> row item_s)                          (* list identity *)
```

- `if_ ~test` / `keyed ~source` take signals directly; no `_signal`
  suffix (they have no static twin).
- **Static structure uses plain OCaml**: `if` for static branches,
  `List.map`/`for` for static lists. Never wrap static branching in
  `if_`/`reactive`.

## Decision rules

- Value changes (text, icon, disabled, class, attrs) → `reactive` prop.
- Whole subtree switches shape on a signal → `reactive` in children.
- Mount/unmount on a bool signal → `if_ ~test`.
- List membership/order changes on a signal → `keyed ~source`.
- Anything else → plain OCaml.
- `dyn`-inside-`dyn`/`if_` nesting is almost always wrong: the inner
  layer usually changes only props — demote it to `reactive` props.

## Signals and ownership

- `Lui_elements.dyn/if_/keyed` own their sources internally
  (`Signal.own_signal` on derived signals) — ppx-expanded calls inherit
  leak protection automatically. Do not add a second ownership layer.
- Derived-signal transforms stop re-running once the owning node
  unmounts; shared state signals (`Signal.value`/`state_signal`) carry
  no upstream links and survive unmount by design.

## Comments

All code comments and PR descriptions must be in English.
