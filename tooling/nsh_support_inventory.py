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
PLATFORM_EXCEPTIONS = {
    "swipe-actions": "Mobile action-reveal container; explicitly excluded from NSH desktop scope by the user on 2026-11-12.",
    "swipe-action": "Mobile action metadata; keep maintained mobile APIs, use desktop commands or ContextMenu on NSH.",
}
SOURCE_NAMES = ["native_capture.rs", "white_space.rs", "application_icons.rs", "application_theme.rs", "runtime.rs", "runtime/driver.rs", "extensions/mod.rs", "extensions/schema.rs", "extensions/host.rs", "ui/checkbox.rs", "render.rs", "controls.rs", "style.rs", "virtual_rows.rs", "app.rs", "ui/mod.rs", "ui/controls.rs", "events.rs", "ui/icons.rs", "controls/basic.rs", "controls/collections.rs", "controls/surfaces.rs", "controls/navigation.rs", "images.rs", "headings.rs", "inputs.rs", "file_picker.rs", "media.rs", "controls/toasts.rs", "controls/tree.rs", "controls/surfaces/native_split.rs", "controls/fit.rs", "context_menu.rs", "ui/context_menu.rs", "images/file_image.rs", "images/file_image/macos.rs", "images/file_image/linux.rs", "images/file_image/windows.rs", "ui/menu_item.rs"]
ROUTES = {
    "root": "core view", "row": "core view + flex direction", "column": "core view",
    "box": "core view", "panel": "core view", "card": "core view", "spacer": "core view + grow/shrink",
    "text": "core text", "heading": "retained core Text + Header role/live level + native typography presets", "paragraph": "core text", "label": "core text", "kbd": "core text",
    "text-field": "themed base Input", "secure-field": "themed base Input + masked",
    "input": "themed base Input or native TimeField", "search-field": "themed base Input", "textarea": "themed base Input + multiline",
    "checkbox": "themed base Checkbox", "scroll": "core Scroll", "image": "core Image + canonical URL/fit/name + Load ABI",
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

ROUTES.update({
    "drawer": "base controlled left Sheet + retained main content",
    "resizable": "base ResizeHandle + bounded retained local width",
    "edge-inset": "core grid + keyed main/pinned regions + scoped visibility",
    "list-item": "base Button/Accordion + keyed retained row content",
    "stack": "core same-cell grid + keyed retained layers",
    "overlay": "core local overlay + keyed retained layers",
    "alert": "themed inline alert + retained layers",
    "bubble": "themed bubble + reaction badge + retained layers",
    "spinner": "base Progress + native spinning SVG",
    "icon": "core SVG + base Tooltip",
    "avatar": "base Avatar with authored fallback",
    "status-bar": "themed core text",
    "link": "base Link with App/System navigation ownership",
    "accordion": "base controlled Accordion/Item/Trigger/Panel",
    "table": "base Table",
    "table-row": "public host equivalent of base TableRow + selection",
    "table-cell": "public host equivalent of base TableCell + authored width",
    "list-section": "core semantic group",
    "list-section-header": "core header group",
    "list-section-footer": "core footer group",
    "bottom-tabs": "shared native Tabs triggers + lazy retained keyed pages",
    "bottom-tab": "retained core Scroll region + separate model-owned base Tab trigger",
    "breadcrumb": "base Toolbar + retained authored children and keyed separators",
    "pagination": "base Toolbar + retained authored children",
    "stepper": "core List + keyed Step position/state context",
    "step": "semantic core host + live active/completed/pending indicator",
    "timeline": "core semantic List + retained authored TimelineItem children",
    "timeline-item": "interactive core host + themed marker/content/connector",
    "split": "base ResizablePanelGroup + keyed native ResizablePanel sizes and completed resize events",
    "view-that-fits": "retained native intrinsic layout + ordered fitting and inherited visibility",
    "context-menu": "native Menu for Button primary attachment; native ContextMenu for ListItem secondary attachment",
    "file-image": "retained core Image + native bounded local thumbnail in existing decode pool",
    "file-picker": "native pick_paths/OpenDialog + owner-scoped request task",
    "media-surface": "core Video + native URL playback and controls",
    "toast": "base Toast/ToastStack/ToastManager + one owner-scoped deadline",
    "tree": "base Tree + keyed metadata, native selection/expansion/action and virtualization",
})

HOST_EVENT_KINDS = {
    "root", "row", "column", "box", "panel", "card", "spacer", "dropdown-menu",
    "text", "heading", "paragraph", "label", "kbd", "text-field", "secure-field",
    "input", "search-field", "textarea", "scroll", "virtual-list", "image",
    "radio-group", "input-group", "input-group-actions", "divider", "list", "grid",
    "dialog", "popover", "tooltip", "select", "combobox", "menu-trigger",
    "stack", "overlay", "alert", "bubble", "icon", "status-bar", "table-row",
    "table-cell", "list-section", "list-section-header", "list-section-footer",
    "drawer", "resizable", "edge-inset", "bottom-tabs", "breadcrumb", "pagination",
    "stepper", "step", "timeline", "timeline-item", "split", "file-picker", "media-surface", "view-that-fits", "file-image", "context-menu",
}

# Concrete validator restrictions are distinct from accepted property gaps and
# qualifications that still require a native operating-system run.
RESTRICTIONS = {
    "context-menu": ["Attaches to one retained Button or ListItem; changing attachment mode on the same incarnation requires a new keyed host."],
    "file-image": ["Local paths or file URLs only; max-pixel-size is 1..4096, default 1024. Encoded input above 64 MiB fails decoding."],
    "file-picker": [
        "Only native files/folders dialogs; photo-library/camera sources and completion leases are rejected.",
        "File filters accept extension groups, not MIME or UTI filters; folders use native folder options.",
    ],
    "media-surface": ["Requires a nonempty URL; foreign surface resource IDs, including zero, are rejected."],
    "tree": [
        "Children are native item metadata, not arbitrary view/editor bodies; unsupported metadata properties and pointer callbacks are rejected.",
        "Use tree_item semantic selection/expansion/action callbacks; legacy pointer-enabled rows are rejected.",
    ],
    "input": ["input-type=color is rejected; time uses native TimeField for valid HH:MM/HH:MM:SS and rejects unsupported editing options; text blur/navigation observers require authored mount-time capability."],
    **{kind: ["Blur/navigation capability must be authored at mount; full NavigationKey is not implemented."] for kind in ("text-field", "secure-field", "search-field", "textarea")},
    "scroll": ["Orientation is native horizontal/vertical at mount; changing its effective axis on the same incarnation is rejected atomically."],
    "drawer": ["Requires exactly two canonical children: sidebar first and main content second."],
    "split": [
        "Requires exactly two canonical pane children; sizes and resize events use absolute points.",
        "Rejects ratio value, custom resize-handle-width, nonzero resize-handle-offset and pointer-enabled=true.",
        "Rejects nonzero resize-duration and authored resize-easing/resize-origin; uses the native 9-point handle.",
    ],
    "edge-inset": [
        "At most 32,760 children because native grid line indices use signed 16-bit values.",
        "Rejects any authored hover-*, pressed-*, focus-*, selected-* or disabled-* pooled state-paint property.",
        "Rejects opacity other than 1, nonempty shadow other than none, and any authored transition.",
    ],
    "list-item": [
        "Rejects change-enabled=true inline editing and true long-press-enabled, double-press-enabled or submit-enabled callbacks.",
        "Adding or removing expanded within the same incarnation is rejected; switching flat/disclosure mode requires a new node incarnation.",
    ],
    "avatar": ["Rejects authored image resources until the native image-resource bridge is available."],
    "image": [
        "Rejects any authored image resource ID, including zero and IDs supplied alongside a URL; use canonical url.",
        "Rejects any authored source-x/source-y/source-width/source-height crop rectangle property.",
        "Rejects loading=lazy; eager/default uses the native loader.",
        "Rejects any authored referrer-policy; the native transport's default policy remains.",
    ],
    "link": ["Without an authored press handler, URL navigation requires a valid external system URL; relative destinations are rejected."],
}

# These are reviewed omissions, not conclusions inferred from a string search.
# Filtering by canonical properties avoids asserting a property on the wrong kind.
GAPS = {
    "G1": (None, {"style-class"}, "Authored style-class has no adapter reader; native/style defaults remain."),
    "G13": (set(ROUTES) - {"overlay"}, {"alignment"}, "Authored layer alignment remains unimplemented outside local Overlay."),
    "G11": ({"button", "toggle-button"}, {"tooltip-keys"}, "Command shortcut hints are not forwarded; built-in icons, placement, size and variants have native bindings outside tabs."),
    "G3": ({"text-field", "secure-field", "input", "search-field", "textarea", "combobox"}, {"input-type"}, "Textarea Enter behavior is forwarded through native SubmitBehavior. Single-line inputs keep native submit/blur defaults; Authored blur submission uses native focus/composition with Enter deduplication; focused unmodified Up/Down forwards native navigation requests; color input remains rejected; valid 24-hour time uses native TimeField, preserving precision, change and submit events without replacing its native input. Empty/invalid times and unavailable editing options fail preflight. Other input hints and full NavigationKey require review."),
    "G5": ({"image"}, {"image", "source-x", "source-y", "source-width", "source-height", "referrer-policy"}, "Image forwards canonical URL, alt/label, fit, eager/default loading and native Load. Resource IDs, crop rectangles and authored referrer policy are explicitly rejected; loading=lazy is a value restriction listed separately, not a missing eager-loading path."),
    "G8": ({"list", "virtual-list"}, {"style", "list-style"}, "Container appearance and CSS list markers are not implemented by the Scroll/VirtualList routes."),
    "G9": ({"button", "row", "box"}, {"navigate-enabled"}, "Full NavigationKey payload remains unimplemented on generic calendar/container key handlers."),
    "G14": (None, {"pointer-capture"}, "Canonical pointer-capture remains unimplemented."),
    "G12": (set(ROUTES) - HOST_EVENT_KINDS, {"pointer-enabled", "long-press-enabled", "double-press-enabled"}, "Typed native behavior components do not expose generic root pointer/gesture projection; unit semantic events remain supported separately."),
}

TESTS = {
    "search-field": ['each_input_kind_projects_only_the_focused_editors_unmodified_arrows', 'initially_false_and_live_disabled_flags_remove_the_actual_bindings', 'composition_removes_navigation_and_shares_the_single_blur_composition_hook', 'focused_reorder_retains_the_editor_and_removal_releases_its_keys', 'absent_false_true_cannot_bypass_installed_capacity_and_remount_restores_navigation'],
    "input": ['opted_in_single_line_enter_reports_one_submit_before_its_native_blur', 'ordinary_blur_submits_the_committed_draft_once_and_keeps_both_inputs', 'textarea_enter_and_later_blur_are_distinct_requests_without_changing_native_focus', 'initially_false_policy_uses_live_blur_enabled_and_submit_flags_without_remounting', 'absent_then_false_cannot_bypass_installation_and_rejection_preserves_draft_and_generation', 'composition_is_not_submitted_early_and_its_committed_text_precedes_blur_submit', 'submit_handler_replacement_cannot_deliver_the_retired_inputs_following_blur'],
    "context-menu": ['attached_context_layout_matches_plain_size_grow_margins_intrinsics_and_stretch', 'native_context_menu_owns_secondary_keyboard_disabled_items_and_repeated_actions', 'context_menu_item_updates_preserve_native_item_identity_and_the_surrounding_editor', 'context_attachment_changes_roll_back_before_replacing_a_live_trigger_or_editor', 'button_context_attachment_is_a_native_primary_menu_with_keyboard_reopening'],
    "file-image": ['local_paths_caps_and_file_fit_preserve_the_downstream_contract', 'native_thumbnail_is_bounded_preserves_aspect_and_does_not_upscale', 'unchanged_request_does_not_reload_and_old_path_or_detached_completion_cannot_publish', 'failed_or_pending_replacement_clears_the_previous_file', 'detached_owner_drops_its_pending_completion', 'file_image_live_path_cap_and_fit_keep_native_host_and_reject_atomically'],
    "scroll": ["native_scroll_uses_the_authored_axis_and_keeps_editor_identity_and_draft"],
    "view-that-fits": ['ordered_choice_waits_for_unknown_predecessors_and_uses_last_as_fallback', 'both_axes_switch_without_remounting_or_losing_independent_drafts', 'keyboard_traversal_excludes_unselected_candidates', 'live_candidate_geometry_order_and_outer_visibility_use_retained_nodes'],    'textarea': ['single_line_inputs_keep_native_submit_and_blur_defaults', 'textarea_live_enter_policy_keeps_the_editor_and_native_line_break_rules', 'submit_flag_changes_are_checked_without_replacing_the_textarea', 'unsupported_input_policies_fail_before_any_text_or_identity_is_published', 'native_composition_survives_an_enter_policy_update_until_its_commit'],
    'tree': ['uncontrolled_native_tree_distinguishes_selection_from_double_press_action', 'controlled_values_refuse_then_accept_native_requests_without_custom_state', 'native_cursor_keys_skip_disabled_rows_and_keep_native_default_action', 'native_keys_survive_metadata_updates_and_reorder_while_outside_editor_is_retained', 'arbitrary_body_views_fail_atomically_and_retry_keeps_generation', 'native_tree_virtualizes_a_thousand_metadata_items', 'legacy_pointer_subscriptions_are_refused_before_other_edits_publish'],
    'toast': ['toast_is_non_flow_metadata_and_retains_arbitrary_native_children_on_update', 'native_timeout_does_not_restart_and_closed_source_incarnation_never_reopens', 'desktop_default_and_zero_persistence_use_native_lifecycle_without_idle_polling', 'native_hover_and_keyboard_focus_pause_timeout_then_resume_remaining_time', 'native_swipe_closes_once_and_source_detach_cancels_late_callbacks_before_reopen', 'native_stack_keeps_existing_identity_and_escape_closes_only_the_newest'],
    'media-surface': ['media_url_changes_keep_the_real_video_host_and_controlled_editor', 'foreign_surface_ids_and_empty_urls_fail_atomically', 'a_native_player_error_is_nonfatal_and_keeps_other_controls_working', 'public_native_video_properties_enable_controls_and_reuse_nsh_playback_defaults'],
    'file-picker': ['file_dialog_results_keep_exact_tokens_paths_and_authored_child_identity', 'native_cancel_is_dismiss_and_folder_dialog_uses_native_folder_options', 'disabled_requests_wait_for_enable_and_old_incarnations_cannot_deliver_answers', 'native_dialog_failure_is_a_result_and_unsupported_options_are_atomic', 'native_picked_paths_and_errors_reach_the_real_ocaml_callback_unchanged'],
    "heading": ["heading_default_and_live_levels_keep_the_actual_text_and_editor_identity", "heading_authored_styles_override_presets_and_invalid_changes_roll_back_atomically"],
    "image": ["canonical_url_fit_and_accessible_name_preserve_image_defaults", "url_fit_and_atomic_rejections_keep_the_image_and_editor_native_identity", "canonical_image_load_reaches_the_existing_ocaml_callback"],
    "drawer": ["drawer_uses_native_sheet_and_keeps_refused_selected_state"],
    "resizable": ["resizable_native_drag_clamps_and_reconciles_source_without_remounting"],
    "edge-inset": ["edge_inset_measures_all_pinned_children_and_scopes_surface_spacing_to_pins", "edge_inset_preserves_editor_identity_draft_and_focus_when_main_role_changes", "edge_inset_logical_edges_keep_physical_padding_in_rtl", "edge_inset_rejects_unavailable_pooled_paint_atomically", "edge_inset_parts_keep_surface_properties_off_the_main_host", "edge_inset_appear_follows_visibility_without_replacing_native_nodes"],
    "list-item": ["list_disclosure_partitions_body_and_nested_rows_without_replacing_the_editor", "list_row_rejects_unavailable_callback_semantics_and_mode_mutation_explicitly", "changing_native_list_mode_rolls_back_other_edits_and_preserves_retry_generation_and_ids"],
    "stack": ["layered_editor_keeps_native_identity_draft_and_keyboard_focus_across_reorder"],
    "overlay": ["local_overlay_preserves_intrinsic_content_and_child_alignment_override", "layered_editor_keeps_native_identity_draft_and_keyboard_focus_across_reorder"],
    "icon": ["icon_and_indeterminate_spinner_retain_native_identity_when_size_changes"],
    "spinner": ["icon_and_indeterminate_spinner_retain_native_identity_when_size_changes"],
    "avatar": ["url_only_link_shows_destination_and_avatar_keeps_verbatim_fallback", "avatar_resource_images_are_rejected_explicitly"],
    "link": ["native_link_uses_keyboard_activation_and_live_disabled_without_remounting", "relative_link_navigation_requires_an_authored_press_handler"],
    "alert": ["alert_and_bubble_retain_authored_body_when_title_or_reaction_changes"],
    "bubble": ["alert_and_bubble_retain_authored_body_when_title_or_reaction_changes"],
    "accordion": ["disclosure_is_controlled_and_keeps_its_editor_across_keyboard_close_reopen", "disclosure_without_a_toggle_callback_is_static_content"],
    "table": ["static_table_preserves_cell_and_editor_identity_through_a_text_update"],
    "table-row": ["static_table_preserves_cell_and_editor_identity_through_a_text_update"],
    "table-cell": ["static_table_preserves_cell_and_editor_identity_through_a_text_update"],
    "bottom-tabs": ["bottom_tabs_use_native_arrows_skip_disabled_and_follow_canonical_selection", "bottom_tab_pages_are_lazy_controlled_and_keep_editor_state_through_reorder", "bottom_tab_page_buttons_keep_their_own_activation_and_body_edits_do_not_reappear", "bottom_tab_effective_selection_matches_first_selected_and_first_child_defaults", "bottom_tab_page_keeps_its_own_scroll_position_when_hidden_and_shown"],
    "bottom-tab": ["bottom_tabs_use_native_arrows_skip_disabled_and_follow_canonical_selection", "bottom_tab_pages_are_lazy_controlled_and_keep_editor_state_through_reorder", "bottom_tab_page_buttons_keep_their_own_activation_and_body_edits_do_not_reappear", "bottom_tab_effective_selection_matches_first_selected_and_first_child_defaults", "bottom_tab_page_keeps_its_own_scroll_position_when_hidden_and_shown"],
    "breadcrumb": ["authored_navigation_uses_native_roving_without_activating_on_focus", "navigation_layout_reaches_children_and_reorder_keeps_editor_identity"],
    "pagination": ["authored_navigation_uses_native_roving_without_activating_on_focus", "navigation_layout_reaches_children_and_reorder_keeps_editor_identity"],
    "stepper": ["steps_follow_canonical_active_live_values_and_keyed_source_positions"],
    "step": ["steps_follow_canonical_active_live_values_and_keyed_source_positions"],
    "timeline": ["timeline_uses_live_content_marker_precedence_and_retains_its_host", "timeline_item_preserves_native_pointer_modifiers_and_keyboard_activation"],
    "timeline-item": ["timeline_uses_live_content_marker_precedence_and_retains_its_host", "timeline_item_preserves_native_pointer_modifiers_and_keyboard_activation"],
    "split": ['native_equal_panels_keep_user_sizes_without_model_echo_and_report_pixels_once', 'native_pixel_source_update_and_keyed_reorder_retain_both_editors_and_focus', 'native_constraints_and_notification_disable_do_not_add_a_second_resize_policy', 'native_rtl_report_selects_the_first_logical_panel_and_legacy_options_reject'],
    "checkbox": ["native_checkbox_mixed_state_is_controlled_until_the_model_resolves_it", "native_checkbox_detail_preserves_pointer_modifiers_and_controlled_proposals_once", "native_checkbox_keyboard_detail_and_disabled_input_share_the_native_owner"],
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
    "text-field": ["real_ocaml_edits_and_keyed_moves_keep_the_editor", "single_line_inputs_keep_native_submit_and_blur_defaults"],
    "row": ["canonical_space_between_places_children_at_opposite_edges"],
    "box": ["native_host_press_preserves_modifiers_pointer_payload_and_appear_without_text_stealing", "live_flags_guard_input_checkbox_and_host_callbacks_without_remounting", "a_container_observes_one_focus_entry_and_exit_from_its_real_input"],
    "column": ["column_detail_only_capability_does_not_emit_an_unsupported_ordinary_press"],
    "virtual-list": ["real_ocaml_sparse_rows_keep_focus_and_bound_both_trees_through_reorder", "native_cell_feedback_releases_distant_focus_without_scrolling_again", "eager_nearest_uses_native_root_geometry_and_reports_each_token_once"],
    "menu-item": ['menu_item_icon_check_hint_size_and_variant_update_without_replacing_children', 'menu_item_optional_parts_restore_in_place_after_removal', 'decorated_menu_items_keep_native_disabled_traversal_and_controlled_checks'],
    "dropdown-menu": ["native_menu_keyboard_skips_disabled_items_and_dispatches_the_existing_press", "structural_sibling_insertion_revalidates_existing_menu_ownership_atomically"],
    "menu-trigger": ["native_submenu_owns_right_arrow_focus_and_nested_selection"],
    "select": ["model_owned_select_can_refuse_open_then_dismiss_without_replacing_its_trigger", "pointer_only_controlled_picker_delivers_detail_once_without_semantic_activation", "keyboard_context_menu_uses_root_coordinates_without_a_fake_secondary_button"],
    "combobox": ["combobox_keeps_its_controlled_query_and_input_identity_through_popup_opening"],
    "popover": ["externally_anchored_popover_preserves_editor_identity_and_escape_restores_focus"],
    "tooltip": ["anchored_tooltip_uses_native_keyboard_hint_visibility_and_escape"],
}

EMITTED = {
    "button": {"press", "press-modifiers"}, "menu-item": {"press", "press-modifiers"},
    "toggle-button": {"toggle-changed"}, "toggle": {"toggle-changed", "toggle-changed-detail"}, "checkbox": {"toggle-changed", "toggle-changed-detail"}, "switch": {"toggle-changed"},
    "radio": {"change", "toggle-changed"}, "slider": {"value-changed"}, "number-stepper": {"value-changed"},
    "select": {"press", "press-modifiers"}, "combobox": {"press", "press-modifiers", "text-changed", "submit"},
    "drawer": {"toggle-changed"}, "list-item": {"press", "toggle-changed"},
    "link": {"press"}, "accordion": {"toggle-changed"}, "bottom-tab": {"press"},
    "dialog": {"dismiss"}, "sheet": {"dismiss"}, "popover": {"dismiss"},
    "image": {"load"}, "context-menu": {"dismiss"}, "split": {"value-changed"},
    "file-picker": {"picked", "dismiss"}, "toast": {"dismiss"},
    "virtual-list": {"visible-range", "scroll-completed", "virtual-window"},
}
for _kind in ROUTES:
    EMITTED.setdefault(_kind, set()).add("appear")
for _kind in HOST_EVENT_KINDS:
    EMITTED.setdefault(_kind, set()).update({"press", "press-modifiers", "press-detail", "pointer-down", "pointer-up", "pointer-move", "pointer-cancel", "pointer-enter", "pointer-leave", "context-menu-press", "long-press", "double-press", "focus-within-changed"})
for _kind in ("text-field", "secure-field", "input", "search-field", "textarea"):
    EMITTED.setdefault(_kind, set()).update({"text-changed", "submit", "navigate-previous", "navigate-next"})


def admitted(source):
    start = source.index("fn supported(kind: &str) -> bool")
    stop = source.index("\n}", start)
    return set(re.findall(r'"([a-z][a-z-]*)"', source[start:stop]))


def inventory():
    contract = json.loads((ROOT / "platform/nsh/contract.json").read_text())
    sources = {name: (ROOT / "platform/nsh/src" / name).read_text() for name in SOURCE_NAMES}
    supported = set().union(*(admitted(source) for name, source in sources.items()
                              if "fn supported(kind: &str) -> bool" in source))
    if supported != set(ROUTES):
        raise ValueError(f"Route catalog needs review: {sorted(supported ^ set(ROUTES))}")
    if not supported <= set(contract["kinds"]):
        raise ValueError("A native route is absent from the canonical contract")
    if not set(PLATFORM_EXCEPTIONS) <= set(contract["kinds"]) or set(PLATFORM_EXCEPTIONS) & supported:
        raise ValueError("Desktop exceptions must name canonical kinds without admitted routes")
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
        press_gap = routed and "press-enabled" in canonical["properties"] and kind not in HOST_EVENT_KINDS | {"button", "menu-item", "radio", "link", "bottom-tab", "list-item"}
        if press_gap:
            gaps["G10"] = ["press-enabled"]
        implemented = set(canonical["events"]) & EMITTED.get(kind, set())
        kinds.append({
            "kind": kind, "admitted_route": ROUTES.get(kind), "platform_exception": PLATFORM_EXCEPTIONS.get(kind), "canonical_properties": canonical["properties"],
            "canonical_events": canonical["events"], "verified_property_gaps": gaps,
            "enforced_restrictions": RESTRICTIONS.get(kind, []) if routed else [],
            "event_path_candidates": sorted(implemented),
            "events_without_renderer_transport": sorted(set(canonical["events"]) - implemented) if routed else [],
            "property_review_candidates_without_literal_reference": sorted(set(canonical["properties"]) - literal_names) if routed else [],
            "tests_present_in_source": {name: test_locations[name] for name in TESTS.get(kind, [])},
        })
    return {"scope": "Source inventory, not native OS qualification or proof of complete property support",
            "source_sha256": {name: hashlib.sha256(source.encode()).hexdigest() for name, source in sources.items()},
            "canonical_kind_count": len(kinds), "admitted_route_count": len(supported),
            "required_desktop_kind_count": len(kinds) - len(PLATFORM_EXCEPTIONS),
            "remaining_required_kind_count": len(kinds) - len(PLATFORM_EXCEPTIONS) - len(supported), "kinds": kinds}


def markdown(data):
    rows = ["# NSH source support inventory", "", "Generated by `python3 tooling/nsh_support_inventory.py`; check with `--check`.",
            "Use `--json` for every canonical property/event, known property gap, enforced", "restriction, conservative unreferenced-property candidate, test location and source hash.", "",
            f"The canonical contract contains **{data['canonical_kind_count']} kinds**; **{data['admitted_route_count']} have an admitted native route**.",
            f"The desktop scope requires **{data['required_desktop_kind_count']} kinds**, with **{data['remaining_required_kind_count']} routes still missing**.",
            "SwipeActions/SwipeAction are explicit mobile-only desktop exceptions; their common wire kinds and maintained mobile implementations remain.",
            "The remainder are explicitly rejected by `render::validate` before publication.",
            "An admitted route is **partial support**, not a claim that all its canonical", "properties, events, children or defaults are implemented. Source-listed tests", "are not rerun by this generator and do not establish Windows/Linux/macOS parity.", "",
            "## All canonical kinds", "", "P/E are canonical property/event counts. Gap IDs are expanded below.",
            "The JSON output also enumerates canonical events without a renderer transport.", "",
            "| Kind | Current native route or rejection | P/E | Verified property gaps | Focused test sources |", "| --- | --- | --- | --- | --- |"]
    for node in data["kinds"]:
        route = node["admitted_route"] or ("Mobile-only desktop exception" if node["platform_exception"] else "Explicitly unsupported")
        gaps = ", ".join(node["verified_property_gaps"]) or "—"
        tests = str(len(node["tests_present_in_source"])) if node["tests_present_in_source"] else "None mapped"
        rows.append(f"| `{node['kind']}` | {route} | {len(node['canonical_properties'])}/{len(node['canonical_events'])} | {gaps} | {tests} |")
    rows += ["", "## Verified gaps and priorities", "",
             "The canonical contract defines the listed properties. The current adapter does",
             "not implement the authored behavior on the indicated routes. The restrictions",
             "below identify known fail-closed values and transitions; remaining gaps need",
             "implementation or explicit rejection with migration notes. Acceptance alone",
             "is not a support guarantee.", ""]
    for key, (_, properties, description) in GAPS.items():
        rows += [f"- **{key}**: {description} Candidate properties: " + ", ".join(f"`{prop}`" for prop in sorted(properties)) + "."]
    rows += ["- **G10** is retired for current generic host routes: authored activation is now installed with live guards. Radio's true press-enabled value remains explicitly rejected.", "",
             "Priority 1: remaining typed-control pointer/modifier delivery, navigation", "and capture; remaining input hints; image resources/crop;", "menu-item icons. Priority 2: remaining appearance, class translation or explicit", "rejection, list appearance and metadata.", "",
             "## Event, child and default limitations", "",
             "- Native host routes deliver available modifier/pointer payloads; typed behavior", "  components generally expose unit events; Checkbox additionally projects native", "  checked/modifier detail without a synthetic observer wrapper. The JSON event-path", "  list is not a claim of full per-field parity. Appearance", "  uses the actual existing ref after native materialization, including disabled", "  controls; it is not an OS-visible-frame notification.",
             "- Scroll forwards a static horizontal axis to native Scroll.horizontal; absent or",
             "  explicit vertical uses its native default. Axis changes require a new keyed",
             "  node, while ordinary edits preserve native content/offset/editor identity.",
             "- FilePicker uses native paths and exact request tokens; cancellation emits Dismiss,",
             "  results/errors emit Picked. Busy requests do not queue or replace the dialog.",
             "  Headless service tests and a real OCaml Picked/Dismiss ABI test are mapped;",
             "  they do not qualify actual operating-system dialog UX.",
             "- MediaSurface uses native Video with controls and native playback defaults.",
             "  URL updates retain the player; playback errors are nonfatal renderer diagnostics.",
             "  Its tests inspect native properties and identity, not actual media decoding.",
             "- Tree delegates keyboard, selection, expansion, Action and virtualization to NSH.",
             "  Metadata projection/flattening is O(n); mounted rows are viewport-bounded.",
             "  Native SelectedChange/Expand/Collapse/Action target metadata callbacks; these",
             "  are not Tree-root event transports. No custom Tree focus controller is used.",
             "- Toast uses native lifecycle: 400ms entrance, then its TTL, then 200ms exit.",
             "  Hover/focus pause the native manager. Dismiss follows completion; a retained",
             "  closed incarnation stays closed until replaced. No application close veto exists.",
             "- Input change/submit and Checkbox toggle callbacks now honor live callback", "  flags and enabled state. Row/Column/Box use one native-ref focus transition", "  owner rather than duplicate direct Input focus handlers.",
             "- Host listeners are installed from authored initial capabilities. Enabling an", "  initially unauthored press/pointer/gesture capability after mount is explicitly", "  rejected atomically pending a public identity-preserving rebind path. Focus-within", "  flags on the three canonical containers can change live. Unused Text nodes get", "  no press listener, so they do not steal activation from enclosing commands.",
             "- Core text routes render the node's text value and discard their canonical", "  children. Container admission therefore does not prove rich/composed text.",
             "- Heading uses the same retained native Text host with Header role and live",
             "  accessibility_level. Its absent level is 2, preserving the replaced desktop",
             "  default; the canonical constructor writes only authored levels. Apple defaults",
             "  to 1 and Web forwards authored aria-level, so no common wire default is inferred.",
             "  Levels 1..6 use native 3xl/2xl/xl/lg/base/sm presets with bold weight; authored",
             "  typography and color win. At the native default scale these are 30/24/20/18/16/14",
             "  points, replacing the old desktop 28/26/24/22/20/18-point formula. Text supplies",
             "  the accessible name; Heading still rejects the noncanonical accessibility-label.",
             "  The mapped Headless tests cover level/default/override/identity/rollback behavior,",
             "  not operating-system screen-reader announcements or native screenshot metrics.",
             "- MenuItem binds icon/check/shortcut parts, native sizing/selection placement and",
             "  variant styling. Authored foreground wins over native checked/hover defaults.", "  This inventory does not infer canonical absent-property defaults from NSH's", "  defaults. Those need explicit cross-backend behavior tests and migration notes.",
             "- Button/toggle command icons use shared Web SVG assets, native retained size/variant", "  bindings and decorative glyph accessibility. Tab appearance, application icon", "  registration and shortcut hints still need qualification or implementation.", "- Native pointer states used by styles are separate from LUI pointer events.", "  Paint::read dynamically handles prefixed background/foreground/border/opacity/", "  shadow properties; the generator excludes these string-search false positives.", "",
             "- Image uses canonical url and live native source/fit/name bindings. Default fit",
             "  is stretch, fit means contain and fill means cover; an accessibility label wins",
             "  over alt. Successful native decoding emits Load through the existing C ABI.",
             "  The mapped headless tests check defaults, retention, stale incarnations and",
             "  atomic rejection; the real OCaml test dispatches an explicit Load. Neither",
             "  establishes native decoding, HTTP transport or screenshot/pixel fit accuracy.",
             "  Native decoding has a separate test_nsh_image_app.py packaged-app qualifier.",
             "- Drawer uses a controlled left Sheet: selected remains application owned;",
             "  Escape/backdrop requests toggle-changed only when enabled and toggle-enabled.",
             "  It introduces no separate dismiss transport. Its retained main editor survives",
             "  open/close and sidebar replacement in the mapped focused test.",
             "- Resizable uses native ResizeHandle capture with local bounded width. Authored",
             "  width changes reset it; unrelated edits preserve the user's width; min/max",
             "  updates clamp it. There is no resize-value callback in its canonical API.",
             "  Existing-root accessibility actions use 16-point steps; native keyboard arrows",
             "  and consolidated handle accessibility semantics are not established by the drag test.",
             "- EdgeInset preserves the first/main child and reserves measured space for",
             "  later/pinned children at top/bottom/leading/trailing. Logical edges follow RTL;",
             "  pooled padding/paint belongs to pinned content, not the main host. visible=false",
             "  returns pinned space while retaining native child identities. The appearance",
             "  visibility test is listed because its declaration exists; this generator",
             "  does not run it or qualify a native visible-frame notification.",
             "- BottomTabs uses separate native Tab triggers and lazy retained keyed pages.",
             "  The first source-selected child wins, else the first child even when disabled.",
             "  Unvisited pages are not materialized; visited hidden pages retain native editor",
             "  identities, drafts and scroll offsets. Page Buttons remain ordinary Buttons.",
             "  Scoped Appear follows each visible transition rather than body-only edits.",
             "  The mapped source tests do not by themselves qualify OS focus, IME or pixels.",
             "- Breadcrumb/Pagination keep authored children under native Toolbar roving focus;",
             "  focus movement does not itself activate them. Gap/main/cross reach the child row.",
             "  Breadcrumb separators follow keyed child positions without remounting editors.",
             "  These are authored-child adapters, not a flattened native data-owned pagination API.",
             "- Stepper derives Step state from keyed source positions and required nonnegative active.",
             "  Earlier/current/later positions are completed/active/pending; out-of-range active",
             "  values remain representable. Native semantics expose the current step without",
             "  synthesizing a selection callback. Timeline uses retained native hosts: icon wins",
             "  over indicator text, then a dot; connector defaults true; selected/variant/title/",
             "  description/meta remain live. TimelineItem preserves canonical native pointer",
             "  payloads through NativeEvents instead of substituting a unit-event-only Button.",
             "- Split uses native ResizablePanelGroup and keyed ResizablePanel children.",
             "  Absent sizes are equal; first-pane-width and pane min/max are absolute points.",
             "  User drags persist without model echo and report ValueChanged once at completion.",
             "  The native 9-point adjustable band owns capture and 10-point AT adjustments;",
             "  no legacy ratio solver, keyboard-arrow controller or close/refusal policy remains.",
             "  Programmatic sizing and keyed pane/editor retention have mapped source tests.",
             "- ListItem flat/disclosure composition preserves retained body and nested-row",
             "  identities. Its mapped rejection/rollback tests do not establish inline editing,",
             "  rich typed activation details, long/double press or Return-only submission.", "",
             "## Explicit restrictions already enforced", "",
             "Unsupported kinds; box display=contents; any authored white-space; true inert;", "nonzero container-relative-frame-inset; radio press-enabled=true; grid count", "above u16; virtual count above u32; unanchored tooltips; menu-role external", "popovers; nonzero popup alignment offset; invalid/mutated popup anchor source;", "menu-trigger icon and invalid menu shape; same-incarnation toolbar axis changes.", "Enabling an initially unauthored host event listener capability after mount also", "requires an explicit remount. See render::validate,", "validate_popup_shape, controls::validate, virtual_rows::validate and style::compile.", "",
             ]
    for kind, restrictions in RESTRICTIONS.items():
        rows += [f"- `{kind}`: " + " ".join(restrictions)]
    rows += ["", "These restrictions reject the entire transaction before publication, preserving",
             "accepted state and generation for a corrected retry.", "",
             "## Evidence and freshness", "",
             "Admission/routes: `platform/nsh/src/render.rs`, `controls.rs` and `controls/*`.", "Presentation:", "`style.rs` and `ui/`. Event delivery: `render.rs`, `app.rs`, and the native C ABI.", "The JSON test references identify actual test declarations, including real OCaml", "Todos/virtual rows and focused NSH control tests. A source reference is not a", "claim that a test covers every property on that kind.", "",
             "Unreferenced-property candidates in JSON are review prompts, not automatically", "verified omissions. Conversely, a literal reference elsewhere does not prove", "that a specific kind forwards that property. The reviewed gap catalog above", "uses the concrete route bodies, not literal presence alone.", "", "| Source | SHA-256 |", "| --- | --- |"]
    rows += [f"| `{name}` | `{digest}` |" for name, digest in data["source_sha256"].items()]
    rows += ["", "Concrete route evidence at this generated source checkpoint:", "",
             "| Gap | Source evidence |", "| --- | --- |",
             "| G1 | style.rs `compile`, render.rs `node`: authored style is compiled, but authored class has no reader |",
             "| G11 | controls.rs `command_content`; ui/controls.rs `CommandButtonProps` |",
             "| G12 | events.rs `NativeEvents::attach`; ComponentElement lacks public Interactive root handlers |",
             "| G3 | inputs.rs native SubmitBehavior/validation; controls.rs `picker` combobox Input defaults |",
             "| G4 | render.rs CheckboxProps and controls.rs toggle CheckboxProps omit authored indicator/detail props |",
             "| G5 | images.rs `source`/`fit`/`label`/`validate`; render.rs Image on_load; runtime.rs optional Load ABI |",
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
