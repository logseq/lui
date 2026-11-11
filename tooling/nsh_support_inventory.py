#!/usr/bin/env python3
"""Generate a conservative NSH route/gap inventory from the canonical contract."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "docs/agent-guide/review-probes/2026-11-11/nsh-support-inventory.md"
SOURCE_NAMES = ["render.rs", "controls.rs", "style.rs", "virtual_rows.rs", "app.rs", "ui/mod.rs", "ui/controls.rs", "events.rs"]
ROUTES = {
    "root": "core view", "row": "core view + flex direction", "column": "core view",
    "box": "core view", "panel": "core view", "card": "core view", "spacer": "core view + grow/shrink",
    "text": "core text", "heading": "core text", "paragraph": "core text", "label": "core text", "kbd": "core text",
    "text-field": "themed base Input", "secure-field": "themed base Input + masked",
    "input": "themed base Input", "search-field": "themed base Input", "textarea": "themed base Input + multiline",
    "checkbox": "themed base Checkbox", "scroll": "core Scroll", "image": "core Image",
    "virtual-list": "core VirtualList + bounded LUI demand adapter",
    "button": "CommandButton -> base Button/Tab", "toggle-button": "base Toggle",
    "toggle": "base Checkbox", "switch": "base Switch", "radio": "base Radio",
    "radio-group": "semantic view + base RadioGroup", "slider": "base Slider",
    "number-stepper": "base NumberInput", "progress": "base Progress", "divider": "core view separator",
    "tabs": "themed Tabs", "button-group": "base ToolbarGroup", "toggle-group": "base ToggleGroup",
    "toolbar": "base Toolbar", "input-group": "semantic styled view", "input-group-actions": "core row view",
    "menu-item": "base MenuItem", "dialog": "base Dialog + authored panel", "sheet": "base Sheet",
    "list": "core Scroll + List role", "grid": "core view + native grid",
    "select": "base Menu + controlled trigger", "combobox": "base Menu + controlled Input",
    "menu-trigger": "base Menu/Submenu", "dropdown-menu": "core view inside picker-owned menu",
    "popover": "core anchored Overlay", "tooltip": "core anchored Overlay + hint policy",
}

HOST_EVENT_KINDS = {
    "root", "row", "column", "box", "panel", "card", "spacer", "dropdown-menu",
    "text", "heading", "paragraph", "label", "kbd", "text-field", "secure-field",
    "input", "search-field", "textarea", "scroll", "virtual-list", "image",
    "radio-group", "input-group", "input-group-actions", "divider", "list", "grid",
    "dialog", "popover", "tooltip", "select", "combobox", "menu-trigger",
}

# These are reviewed omissions, not conclusions inferred from a string search.
# Filtering by canonical properties avoids asserting a property on the wrong kind.
GAPS = {
    "G1": (None, {"style-class", "alignment"}, "Authored style-class and alignment have no adapter reader; native/style defaults remain."),
    "G2": ({"menu-item"}, {"icon", "icon-placement", "selection-placement", "size", "variant", "tooltip-keys"}, "Menu-item renders text/children with a fixed themed wrapper; these authored appearance choices are not forwarded."),
    "G11": ({"button", "toggle-button"}, {"tooltip-keys"}, "Command shortcut hints are not forwarded; built-in icons, placement, size and variants have native bindings outside tabs."),
    "G3": ({"text-field", "secure-field", "input", "search-field", "textarea", "combobox"}, {"input-type", "submit-on-enter", "submit-on-blur", "navigate-enabled"}, "Input hint/navigation/submit policies are not forwarded; native Input defaults remain."),
    "G4": ({"checkbox", "toggle"}, {"indeterminate", "label-opacity", "indicator-border-color", "checked-indicator-border-color", "toggle-detail-enabled"}, "Checkbox routes pass checked/disabled/label only; mixed state and authored indicator/detail behavior are absent."),
    "G5": ({"image"}, {"url", "source-x", "source-y", "source-width", "source-height", "image-fit", "alt", "loading", "referrer-policy"}, "Image route reads source only; alternative URL, cropping, fit and image metadata are not forwarded."),
    "G6": ({"heading"}, {"heading-level"}, "Heading uses the same core text route, without heading role/level or level-based presentation."),
    "G7": ({"scroll"}, {"orientation"}, "Scroll route does not set horizontal mode; the native default remains."),
    "G8": ({"list", "virtual-list"}, {"style", "list-style"}, "Container appearance and CSS list markers are not implemented by the Scroll/VirtualList routes."),
    "G9": (None, {"navigate-enabled", "pointer-capture"}, "Canonical navigation-key and pointer-capture behavior remain unimplemented."),
    "G12": (set(ROUTES) - HOST_EVENT_KINDS, {"pointer-enabled", "long-press-enabled", "double-press-enabled"}, "Typed native behavior components do not expose generic root pointer/gesture projection; unit semantic events remain supported separately."),
}

TESTS = {
    "switch": ["switch_follows_accepted_press_and_keyboard_values_without_duplicate_events", "refused_switch_requests_keep_native_identity_and_accepted_value", "disabled_switch_takes_no_user_event"],
    "toggle-button": ["toggle_button_exposes_pressed_semantics_and_uses_selected_as_value"],
    "radio": ["radio_reports_change_before_toggle_and_cannot_uncheck_itself", "unsupported_activation_contracts_fail_before_mounting"],
    "radio-group": ["radio_group_preserves_its_name_and_native_arrows_skip_disabled_choices"],
    "slider": ["slider_uses_unit_interval_and_reports_one_value_per_keyboard_step"],
    "number-stepper": ["number_stepper_does_not_impose_an_unrequested_100_limit"],
    "progress": ["progress_unit_fraction_fills_half_its_native_track"],
    "dialog": ["dialog_escape_requests_application_owned_dismissal_once", "authored_dialog_and_sheet_width_targets_the_visible_panel"],
    "sheet": ["authored_dialog_and_sheet_width_targets_the_visible_panel"],
    "toolbar": ["toolbar_axis_mutation_is_rejected_without_losing_horizontal_keyboard_state"],
    "tabs": ["tabs_convert_lui_buttons_and_use_native_arrow_navigation"],
    "button": ["authored_command_icon_size_and_variant_update_without_remounting", "icon_only_command_has_square_geometry_and_named_keyboard_activation", "real_ocaml_edits_and_keyed_moves_keep_the_editor", "tabs_convert_lui_buttons_and_use_native_arrow_navigation"],
    "text-field": ["real_ocaml_edits_and_keyed_moves_keep_the_editor"],
    "row": ["canonical_space_between_places_children_at_opposite_edges"],
    "box": ["native_host_press_preserves_modifiers_pointer_payload_and_appear_without_text_stealing", "live_flags_guard_input_checkbox_and_host_callbacks_without_remounting", "a_container_observes_one_focus_entry_and_exit_from_its_real_input"],
    "column": ["column_detail_only_capability_does_not_emit_an_unsupported_ordinary_press"],
    "virtual-list": ["real_ocaml_sparse_rows_keep_focus_and_bound_both_trees_through_reorder", "native_cell_feedback_releases_distant_focus_without_scrolling_again", "eager_nearest_uses_native_root_geometry_and_reports_each_token_once"],
    "menu-item": ["native_menu_keyboard_skips_disabled_items_and_dispatches_the_existing_press"],
    "dropdown-menu": ["native_menu_keyboard_skips_disabled_items_and_dispatches_the_existing_press", "structural_sibling_insertion_revalidates_existing_menu_ownership_atomically"],
    "menu-trigger": ["native_submenu_owns_right_arrow_focus_and_nested_selection"],
    "select": ["model_owned_select_can_refuse_open_then_dismiss_without_replacing_its_trigger", "pointer_only_controlled_picker_delivers_detail_once_without_semantic_activation", "keyboard_context_menu_uses_root_coordinates_without_a_fake_secondary_button"],
    "combobox": ["combobox_keeps_its_controlled_query_and_input_identity_through_popup_opening"],
    "popover": ["externally_anchored_popover_preserves_editor_identity_and_escape_restores_focus"],
    "tooltip": ["anchored_tooltip_uses_native_keyboard_hint_visibility_and_escape"],
}

EMITTED = {
    "button": {"press", "press-modifiers"}, "menu-item": {"press", "press-modifiers"},
    "toggle-button": {"toggle-changed"}, "toggle": {"toggle-changed"}, "checkbox": {"toggle-changed"}, "switch": {"toggle-changed"},
    "radio": {"change", "toggle-changed"}, "slider": {"value-changed"}, "number-stepper": {"value-changed"},
    "select": {"press", "press-modifiers"}, "combobox": {"press", "press-modifiers", "text-changed", "submit"},
    "dialog": {"dismiss"}, "sheet": {"dismiss"}, "popover": {"dismiss"},
    "virtual-list": {"visible-range", "scroll-completed", "virtual-window"},
}
for _kind in ROUTES:
    EMITTED.setdefault(_kind, set()).add("appear")
for _kind in HOST_EVENT_KINDS:
    EMITTED.setdefault(_kind, set()).update({"press", "press-modifiers", "press-detail", "pointer-down", "pointer-up", "pointer-move", "pointer-cancel", "pointer-enter", "pointer-leave", "context-menu-press", "long-press", "double-press", "focus-within-changed"})
for _kind in ("text-field", "secure-field", "input", "search-field", "textarea"):
    EMITTED.setdefault(_kind, set()).update({"text-changed", "submit"})


def admitted(source):
    start = source.index("fn supported(kind: &str) -> bool")
    stop = source.index("\n}", start)
    return set(re.findall(r'"([a-z][a-z-]*)"', source[start:stop]))


def inventory():
    contract = json.loads((ROOT / "platform/nsh/contract.json").read_text())
    sources = {name: (ROOT / "platform/nsh/src" / name).read_text() for name in SOURCE_NAMES}
    supported = admitted(sources["render.rs"]) | admitted(sources["controls.rs"])
    if supported != set(ROUTES):
        raise ValueError(f"Route catalog needs review: {sorted(supported ^ set(ROUTES))}")
    if not supported <= set(contract["kinds"]):
        raise ValueError("A native route is absent from the canonical contract")
    test_sources = {**{"src/" + path: source for path, source in sources.items()}, **{str(path.relative_to(ROOT / "platform/nsh")): path.read_text()
                                  for path in (ROOT / "platform/nsh/tests").glob("*.rs")}}
    test_sources.update({str(path.relative_to(ROOT / "platform/nsh")): path.read_text()
                         for path in (ROOT / "platform/nsh/src").rglob("*tests.rs")})
    test_locations = {}
    for path, source in test_sources.items():
        for match in re.finditer(r"#\[test\]\s*fn\s+(\w+)", source):
            test_locations[match[1]] = {"file": path, "line": source.count("\n", 0, match.start()) + 1}
    for tests in TESTS.values():
        for test in tests:
            if test not in test_locations:
                raise ValueError(f"Listed test no longer exists: {test}")
    production = "\n".join(source.split("#[cfg(test)]", 1)[0] for source in sources.values())
    literal_names = set(re.findall(r'"([a-z][a-z0-9-]*)"', production))
    # Paint::read constructs these property names from a prefix and suffix.
    for prefix in ("", "hover-", "pressed-", "focus-", "focus-within-", "selected-", "selected-hover-", "disabled-"):
        literal_names.update(prefix + suffix for suffix in ("background", "foreground", "opacity", "shadow", "border"))
    kinds = []
    for kind, canonical in contract["kinds"].items():
        routed = kind in supported
        gaps = {key: sorted(properties & set(canonical["properties"]))
                for key, (kinds, properties, _) in GAPS.items()
                if routed and (kinds is None or kind in kinds) and properties & set(canonical["properties"])}
        press_gap = routed and "press-enabled" in canonical["properties"] and kind not in HOST_EVENT_KINDS | {"button", "menu-item", "radio"}
        if press_gap:
            gaps["G10"] = ["press-enabled"]
        implemented = set(canonical["events"]) & EMITTED.get(kind, set())
        kinds.append({
            "kind": kind, "admitted_route": ROUTES.get(kind), "canonical_properties": canonical["properties"],
            "canonical_events": canonical["events"], "verified_property_gaps": gaps,
            "event_path_candidates": sorted(implemented),
            "events_without_renderer_transport": sorted(set(canonical["events"]) - implemented) if routed else [],
            "property_review_candidates_without_literal_reference": sorted(set(canonical["properties"]) - literal_names) if routed else [],
            "tests_present_in_source": {name: test_locations[name] for name in TESTS.get(kind, [])},
        })
    return {"scope": "Source inventory, not native OS qualification or proof of complete property support",
            "source_sha256": {name: hashlib.sha256(source.encode()).hexdigest() for name, source in sources.items()},
            "canonical_kind_count": len(kinds), "admitted_route_count": len(supported), "kinds": kinds}


def markdown(data):
    rows = ["# NSH source support inventory", "", "Generated by `python3 tooling/nsh_support_inventory.py`; check with `--check`.",
            "Use `--json` for every canonical property/event, known property gap, conservative", "unreferenced-property candidate, test location and source hash.", "",
            f"The canonical contract contains **{data['canonical_kind_count']} kinds**; **{data['admitted_route_count']} have an admitted native route**.",
            "The remainder are explicitly rejected by `render::validate` before publication.",
            "An admitted route is **partial support**, not a claim that all its canonical", "properties, events, children or defaults are implemented. Source-listed tests", "are not rerun by this generator and do not establish Windows/Linux/macOS parity.", "",
            "## All canonical kinds", "", "P/E are canonical property/event counts. Gap IDs are expanded below.",
            "The JSON output also enumerates canonical events without a renderer transport.", "",
            "| Kind | Current native route or rejection | P/E | Verified property gaps | Focused test sources |", "| --- | --- | --- | --- | --- |"]
    for node in data["kinds"]:
        route = node["admitted_route"] or "Explicitly unsupported"
        gaps = ", ".join(node["verified_property_gaps"]) or "—"
        tests = str(len(node["tests_present_in_source"])) if node["tests_present_in_source"] else "None mapped"
        rows.append(f"| `{node['kind']}` | {route} | {len(node['canonical_properties'])}/{len(node['canonical_events'])} | {gaps} | {tests} |")
    rows += ["", "## Verified gaps and priorities", "",
             "Canonical validation accepts the listed properties. The current adapter does", "not implement the authored behavior on the indicated routes. These must be", "implemented or explicitly rejected with migration notes; silently accepting", "them is not a support guarantee.", ""]
    for key, (_, properties, description) in GAPS.items():
        rows += [f"- **{key}**: {description} Candidate properties: " + ", ".join(f"`{prop}`" for prop in sorted(properties)) + "."]
    rows += ["- **G10** is retired for current generic host routes: authored activation is now installed with live guards. Radio's true press-enabled value remains explicitly rejected.", "",
             "Priority 1: remaining typed-control pointer/modifier delivery, navigation", "and capture; input submit policy; checkbox mixed state; image source/fit;", "menu-item icons. Priority 2: remaining appearance, class translation or explicit", "rejection, semantic heading defaults, list appearance and metadata.", "",
             "## Event, child and default limitations", "",
             "- Native host routes deliver available modifier/pointer payloads; typed behavior", "  components still expose unit events and do not gain a synthetic observer wrapper.", "  The JSON event-path list is not a claim of full per-field parity. Appearance", "  uses the actual existing ref after native materialization, including disabled", "  controls; it is not an OS-visible-frame notification.",
             "- Input change/submit and Checkbox toggle callbacks now honor live callback", "  flags and enabled state. Row/Column/Box use one native-ref focus transition", "  owner rather than duplicate direct Input focus handlers.",
             "- Host listeners are installed from authored initial capabilities. Enabling an", "  initially unauthored press/pointer/gesture capability after mount is explicitly", "  rejected atomically pending a public identity-preserving rebind path. Focus-within", "  flags on the three canonical containers can change live. Unused Text nodes get", "  no press listener, so they do not steal activation from enclosing commands.",
             "- Core text routes render the node's text value and discard their canonical", "  children. Container admission therefore does not prove rich/composed text.",
             "- Ignored menu-item size/variant and heading/input-submit/orientation properties leave NSH", "  wrapper defaults in control even when an application authors another value.", "  This inventory does not infer canonical absent-property defaults from NSH's", "  defaults. Those need explicit cross-backend behavior tests and migration notes.",
             "- Button/toggle command icons use shared Web SVG assets, native retained size/variant", "  bindings and decorative glyph accessibility. Tab appearance, application icon", "  registration and shortcut hints still need qualification or implementation.", "- Native pointer states used by styles are separate from LUI pointer events.", "  Paint::read dynamically handles prefixed background/foreground/border/opacity/", "  shadow properties; the generator excludes these string-search false positives.", "",
             "## Explicit restrictions already enforced", "",
             "Unsupported kinds; box display=contents; any authored white-space; true inert;", "nonzero container-relative-frame-inset; radio press-enabled=true; grid count", "above u16; virtual count above u32; unanchored tooltips; menu-role external", "popovers; nonzero popup alignment offset; invalid/mutated popup anchor source;", "menu-trigger icon and invalid menu shape; same-incarnation toolbar axis changes.", "Enabling an initially unauthored host event listener capability after mount also", "requires an explicit remount. See render::validate,", "validate_popup_shape, controls::validate, virtual_rows::validate and style::compile.", "",
             "## Evidence and freshness", "",
             "Admission/routes: `platform/nsh/src/render.rs` and `controls.rs`. Presentation:", "`style.rs` and `ui/`. Event delivery: `render.rs`, `app.rs`, and the native C ABI.", "The JSON test references identify actual test declarations, including real OCaml", "Todos/virtual rows and focused NSH control tests. A source reference is not a", "claim that a test covers every property on that kind.", "",
             "Unreferenced-property candidates in JSON are review prompts, not automatically", "verified omissions. Conversely, a literal reference elsewhere does not prove", "that a specific kind forwards that property. The reviewed gap catalog above", "uses the concrete route bodies, not literal presence alone.", "", "| Source | SHA-256 |", "| --- | --- |"]
    rows += [f"| `{name}` | `{digest}` |" for name, digest in data["source_sha256"].items()]
    rows += ["", "Concrete route evidence at this generated source checkpoint:", "",
             "| Gap | Source evidence |", "| --- | --- |",
             "| G1 | style.rs `compile`, render.rs `node`: authored style is compiled, but neither class nor alignment is read |",
             "| G2 | controls.rs `element` menu-item branch |",
             "| G11 | controls.rs `command_content`; ui/controls.rs `CommandButtonProps` |",
             "| G12 | events.rs `NativeEvents::attach`; ComponentElement lacks public Interactive root handlers |",
             "| G3 | render.rs basic Input branch; controls.rs `picker` combobox Input branch |",
             "| G4 | render.rs CheckboxProps and controls.rs toggle CheckboxProps omit mixed/indicator props |",
             "| G5 | render.rs Image branch reads only `source` |",
             "| G6 | render.rs combined text/heading/paragraph/label/kbd branch |",
             "| G7 | render.rs Scroll branch creates default Scroll without horizontal configuration |",
             "| G8 | controls.rs list branch and virtual_rows.rs VirtualList builder |",
             "| G9/G10 | render.rs Event enum and all native route listeners; app.rs `semantic` |"]
    return "\n".join(rows) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    data = inventory()
    if args.json:
        print(json.dumps(data, indent=2))
    else:
        content = markdown(data)
        if args.check:
            if not REPORT.exists() or REPORT.read_text() != content:
                parser.exit(1, "NSH support inventory is stale; regenerate with tooling/nsh_support_inventory.py\n")
        else:
            REPORT.parent.mkdir(parents=True, exist_ok=True)
            REPORT.write_text(content)


if __name__ == "__main__":
    main()
