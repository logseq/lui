# Native capability preflight coverage review

Source-only review of LUI `961107c7c071b04551587b39cc7cdd16f738c07a`
and Logseq `e6c0d7bdc47c000ba8c603e6621468c9b4808d84`.
No compiler, test, application, or performance run was performed for this report.
This is a proposal, not an expansion of the current admission policy.

## Current boundary

`platform/nsh/src/preflight.rs::validate_styles` validates captured presentation
and now reuses `inputs::validate_capabilities` for known input types and TimeField
options. `render.rs::validate` still owns other renderer capability restrictions.
The input split is the useful pattern: share the provider's pure option policy,
while leaving dynamic values, topology, resources, and transitions at their
existing runtime boundaries. Do not call the full renderer or canonical node
validator on a partial source probe.

The Logseq extractor, `deps/ui/nsh/static_style_sites.ml`, records known optional
arguments and substitutes empty children. Unknown optional arguments are omitted;
unknown required arguments defer the whole constructor. It currently captures
only dismissal/navigation callback presence. `static_style_probe.ml` records node
kind and properties, not a complete child graph. A missing property therefore
does not prove an authored absence, and a captured constructor does not prove
runtime reachability through an application helper.

## Proposed shared rule groups

| Priority | Existing provider owner | Conservative reusable rules | Required caution |
| --- | --- | --- | --- |
| 1 | `images.rs::validate` | Known foreign image resource, source rectangle, lazy loading, referrer policy; known image-fit enum | Keep file-image path/resource validation separate. Omitted URL/resource fields are not evidence of an invalid value. |
| 1 | `render.rs::validate` contents branch | Known unsupported kind; explicit disabled/inert state, owned hit/focus callbacks, role or accessibility label on a known contents anchor | Capture callback presence before relying on enabled flags. Preserve the existing reactive contents/physical transition diagnostic. |
| 1 | `controls.rs::validate`, `controls/collections.rs::validate` | Radio press activation; list-item long/double press or submit; known numeric grid/count overflow | Reuse exact existing rules. List-item change requires a known non-treeitem role; an omitted dynamic role cannot justify rejection. |
| 2 | `controls/surfaces/native_split.rs::validate` | Forbidden authored value/handle/origin options and known invalid easing/range | Factor options from the mandatory two-child check. Resolve dormant maintained-host helper ownership first. |
| 2 | `controls/basic.rs::validate`, `media.rs::validate` | Known avatar image resource; known foreign media surface; known edge-inset paint/opacity/shadow/transition restrictions | Do not infer media URL absence or edge-inset child count from the probe. No current native avatar/image-resource offender was found. |
| 3 | `file_picker.rs::dialog` | Known unsupported source or completion token | Filter validation depends on file/folder mode. Unknown directory mode must not be replaced with the absent false default. Do not open a dialog during preflight. |

These rules should remain in their existing provider modules as pure capability
functions reused by runtime validation and preflight. Validate the complete
captured property set once for capability interactions; isolated one-property
style probes must not invent missing companion-property errors. Do not duplicate
the provider rules in the OCaml extractor or introduce another property grammar.

## Actual Logseq source owners and false positives

- Native assets use URL images and URL video in `deps/ui/native/asset_dom.ml`
  (`asset_leaf`, around lines 211–218). Shared web asset code still authors lazy
  loading/referrer policy; it is not evidence of a native asset regression.
  `views_table.ml::gallery_remote_cover` explicitly selects eager/no-referrer
  policy on NSH. Image capability checks would protect these real families from
  future unsupported authored options; no current invalid native call was proven.
- `deps/ui/native/chrome.ml::left_split` and `right_split` (around 406/426)
  already omit native-forbidden handle/value options. However,
  `legacy_left_sidebar` contains `split ~resize_handle_width:0` around line 380;
  `left_sidebar` selects the separate native helper on NshHost around 398–401.
  A definition-scanning extractor cannot infer that callgraph exclusion.
  Introduce an explicit target guard at the legacy constructor owner before
  enforcing split options across the archive; do not relax the provider rule.
- Links require complete activation ownership. `Ui_parts.delegated_link` around
  line 91 enables and registers the native Press owner after constructing the
  Link; `routed_link` around 116 applies this to internal routes. Valid examples
  include `render_inline.ml` around 110/117 (`url="#"`) and shell routes.
  Running `controls/basic.rs` URL validation on the naked constructor would
  wrongly reject these wrappers. An omitted callback is not a proven unhandled
  URL. Retain URL/handler-dependent runtime validation until the probe has exact
  owner facts; do not evaluate wrappers or assume callbacks exist.
- Current navigation/property list items use ordinary Press, e.g.
  `ui_components.ml::nav_item` around 959 and
  `properties_select.ml` around 158. Current avatars are text-only in
  `graphs/collaborators.ml` around 158 and `comments_view.ml` around 292.
  These are useful valid-call controls, not confirmed unsupported calls.

Tree metadata restrictions require real ancestry and child kinds. Split/drawer
child counts, list-item disclosure topology, retained input-type changes,
context-menu attachment changes, native resource lookup, and generation identity
are not justified by a constructor-only partial probe. Keep their runtime
validation; any future compile-time proof must preserve valid dynamic calls and
backend-specific source selection.

## Required qualification before each expansion

Add actual native-target compile-failure fixtures for each known unsupported
option, including aliased constructors and inert named callbacks. Pair them with
dynamic-value, explicit false/None, supported sibling kind, shadowed module,
wrapper-owner, and other-backend branch positives. Keep dynamic boundary tests.
Do not execute callbacks, widen the literal grammar, infer missing values from
defaults, or claim that source validation proves native interaction behavior.

The constructor alias bug was independently fixed in Logseq commit
`68272b03a4`: call heads were normalized, but the result type `Input.t` was
compared without resolving its module alias. This report does not claim a
qualification result for that source change.
