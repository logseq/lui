# Native backend test coverage audit

Parity accounting between the upstream desktop-app UI framework's test
suite (read-only checkout at `~/repos/refapp`, 116 `*_test.go` files,
661 `Test*` functions under `internal/` and `ui/`) and our native backend
tests (217 `let test_*` functions across 13 `*_test.ml` files under
`platform/native/`).

How to read the tables:

- **asserts** — one line on what the upstream test checks.
- **covered by** —
  - `path:test_name` — an existing test covers the same semantics.
  - `🔲 suggested_name — owner` — a GAP row: no equivalent test exists;
    the suggested name and owning module are what the integrator should
    add (also listed as a checkbox in `gaps.md`).
  - `🔲 partial: path:test → add suggested_name — owner` — the cited test
    covers part of the semantics; the remainder is still a gap and gets a
    checkbox.
  - `➖ n/a — reason` — the upstream subsystem has no counterpart in the
    native backend (windowing shell, webview, updater, codegen tooling,
    menus, etc.); excluded from the gap count, listed for completeness.
- Benchmarks and `TestMain` are inventoried but never counted as gaps.

## Upstream `internal/` suite

### accelerators (`internal/accelerator`)

| test | asserts | covered by |
|---|---|---|
| TestParse | `CmdOrCtrl+K` resolves to the OS-appropriate modifier | 🔲 `test_accel_parse` — e2e |
| TestParseErrors | empty / unknown chords are rejected | 🔲 `test_accel_parse_errors` — e2e |
| TestString | accelerator round-trips to canonical `Ctrl+Shift+K` text | 🔲 `test_accel_to_string` — e2e |
| TestXDGTrigger | XDG keysym names (LOGO, XF86 media keys) map to triggers | 🔲 `test_accel_xdg_trigger` — e2e |

### darwin platform glue (`internal/darwin`)

| test | asserts | covered by |
|---|---|---|
| TestClipboardNativeAliasesAndFileList | clipboard aliases and file-list UTIs map to native formats | ➖ n/a — no ObjC/macOS pasteboard backend |
| TestClipboardFileReferenceURL | file-reference URLs decode to file paths | ➖ n/a — same |
| TestSuperFromDefinedClass | ObjC `super` dispatches to the defining class | ➖ n/a — no ObjC runtime glue |
| TestPoolOffMainThread | autorelease pools work off the main thread | ➖ n/a — same |
| TestDataDragFormatMappings | drag format <-> UTI mapping round-trips | ➖ n/a — no native drag subsystem |

### e2e — windows shell and content window (`internal/e2e`)

The upstream e2e suite drives a full desktop-app shell (windows, menus,
webview, IPC, downloads). Only the content-window rendering/input half
has a native counterpart.

| test | asserts | covered by |
|---|---|---|
| TestMain | shared harness entry, not a test | ➖ n/a — harness entry point |
| TestQuitDuringDialog | quit requested from a modal dialog exits cleanly | ➖ n/a — no window shell |
| TestBeforeRun | startup hook runs before the first window | 🔲 partial: platform/native/e2e/test/e2e_test.ml:test_boot_pipeline → add `test_host_before_run` — e2e |
| TestIframeCannotCall | iframe RPC attempts are rejected | ➖ n/a — no webview |
| TestPopupMenu | popup menu appears and selects on click | ➖ n/a — no menu subsystem |
| TestEarlyWindow | window opens before `run` finishes init | ➖ n/a — no window shell |
| TestIPCAndProtocol | IPC channel wiring and URL protocol handler | ➖ n/a — no webview/IPC |
| TestChannels | two named channels deliver messages both ways | ➖ n/a — same |
| TestReloadLoadHTML | reload keeps the window usable | ➖ n/a — same |
| TestEvalForms | eval returns values for each expression form | ➖ n/a — same |
| TestVibrancy | vibrancy/material option applied to the window | ➖ n/a — no window chrome |
| TestVibrancyWindowControls | window controls still respond under vibrancy | ➖ n/a — same |
| TestFullScreenToolbar | fullscreen toolbar integration | ➖ n/a — same |
| TestTrafficLightPosition | macOS traffic-light insets honored | ➖ n/a — same |
| TestFramelessResizeEdges | frameless window resizes from all edges | ➖ n/a — no window shell |
| TestDockedDevTools | devtools docks and resizes | ➖ n/a — no webview |
| TestWindowGeometryAndState | size/position/state persist across relaunch | ➖ n/a — no window shell |
| TestResizeFixedWindow | fixed-size window refuses resize | ➖ n/a — same |
| TestStrictCSP | strict CSP blocks disallowed loads | ➖ n/a — no webview |
| TestEmptyWindowMenu | empty menu spec builds a valid menu | ➖ n/a — no menu subsystem |
| TestFullScreenMenuBar | menu bar adapts to fullscreen | ➖ n/a — same |
| TestMenuLetters | menu accelerator letters parsed | ➖ n/a — same |
| TestCenterThenResize | centered window stays centered after resize | ➖ n/a — no window shell |
| TestNewWindowBounds | initial bounds applied on new window | ➖ n/a — same |
| TestSmallFixedWindow | tiny fixed window renders correctly | ➖ n/a — same |
| TestResizeBelowMinimum | resize clamps to minimum size | 🔲 partial: platform/native/e2e/test/e2e_test.ml:test_host_flags_and_resize → add `test_resize_below_minimum` — e2e |
| TestWindowState | maximized/fullscreen states round-trip | ➖ n/a — no window shell |
| TestFileDrop | OS file drop reaches the app | ➖ n/a — no file-drop subsystem |
| TestWindowExtras | misc window options (icon, skip taskbar…) | ➖ n/a — same |
| TestURLScheme | custom URL scheme registration and dispatch | ➖ n/a — no OS integration |
| TestOpenAtLogin | login-item registration toggles | ➖ n/a — same |
| TestPower | power assertions block/allow display sleep | ➖ n/a — same |
| TestDockMenu | dock menu shows and selects | ➖ n/a — no menu subsystem |
| TestPrintToPDF | print-to-PDF produces a file | ➖ n/a — no webview |
| TestPermissions | permission prompts grant/deny | ➖ n/a — same |
| TestDownloads | downloads start, progress, finish | ➖ n/a — same |
| TestClearBrowsingData | browsing data clears | ➖ n/a — same |
| TestFindInPage | find-in-page highlights and navigates | ➖ n/a — same |
| TestGlobalShortcut | global shortcut fires while unfocused | 🔲 `test_global_shortcut` — e2e |
| TestGlobalShortcutPortal | shortcut works via the XDG portal | 🔲 `test_global_shortcut_portal` — e2e |
| TestCloseEvents | close request events fire; prevent works | 🔲 `test_close_events` — e2e |
| TestCapturePage | page capture returns pixels | ➖ n/a — no webview |
| TestCallsEndWithTheWindow | closing the window resolves pending calls | 🔲 `test_calls_end_on_close` — e2e |
| TestWebViewFails | renderer crash surfaces an error event | ➖ n/a — no webview |
| TestMenuAndClipboard | menu action + clipboard work in the same window | ➖ n/a — no menu/clipboard shell |
| TestWindowOpenHandler | window.open requests are routed to the handler | ➖ n/a — no webview |
| TestMenuActivation | menu activation events reach the app | ➖ n/a — no menu subsystem |
| TestMenuActivationWindow | activation scoped to the right window | ➖ n/a — same |
| TestAutoHideMenuBar | auto-hide menu bar reveals on Alt | ➖ n/a — same |
| TestHiddenTitleBar | hidden title bar keeps traffic lights usable | ➖ n/a — no window chrome |
| TestJavaScriptAlert | JS alert shows and dismisses | ➖ n/a — no webview |
| TestWindowOpenAllowed | allowed popups create windows, denied don't | ➖ n/a — same |
| TestClick | synthetic click lands on the right element | platform/native/e2e/test/e2e_test.ml:test_press_add_remove_promote |
| TestContentWindowTextSelection | drag-select produces a selection | 🔲 `test_text_selection_drag` — e2e |
| TestContentWindowInputMethod | IME composition commits text | 🔲 `test_ime_composition` — e2e |
| TestContentWindowTextAreaInputMethod | IME works in multiline input | 🔲 `test_ime_textarea` — e2e |
| TestContentWindowTextBufferInputMethod | IME works on the text-buffer widget | 🔲 `test_ime_text_buffer` — e2e |
| TestContentWindowFileDrop | file drop inside content hits the target | ➖ n/a — no file-drop subsystem |
| TestContentWindowAccessibility | a11y tree reflects the UI | platform/native/lui_a11y/test/lui_a11y_test.ml:test_build_forest + test_flatten_preorder |
| TestContentWindowObserved | mutation-observer-style events fire | 🔲 `test_observed_events` — e2e |
| TestContentWindowListAccessibility | list rows expose a11y info | 🔲 partial: platform/native/lui_a11y/test/lui_a11y_test.ml:test_role_table_complete → add `test_a11y_list` — e2e |
| TestContentWindowListTypeToChoose | typing letters selects matching rows | 🔲 `test_list_type_to_choose` — e2e |
| TestContentWindowTyping | typed text reaches the model | platform/native/e2e/test/e2e_test.ml:test_text_changed |
| TestContentWindowComposingKeys | dead-key/composition keys handled | 🔲 `test_composing_keys` — e2e |
| TestContentWindow | click + keyboard drive the demo app | platform/native/e2e/test/e2e_test.ml:test_press_add_remove_promote |
| TestContentWindowVibrancy | vibrancy flag visible in content | ➖ n/a — no window chrome |
| TestContentWindowRepaintsWhatChanged | only damaged regions repaint | 🔲 `test_damage_repaints_only_changed` — lui_scene |
| TestContentWindowMenuButton | in-content menu button opens a menu | 🔲 `test_menu_button` — e2e |
| TestReorderByDragging | drag reorders list items | 🔲 `test_reorder_by_drag` — e2e |
| TestRouterSideButtons | mouse side buttons navigate back/forward | ➖ n/a — no router |
| TestContentWindowContextMenu | right-click context menu | 🔲 `test_context_menu` — e2e |
| TestContentWindowInspector | element inspector opens on the window | ➖ n/a — no inspector |
| TestPlugins | plugin system loads and calls | ➖ n/a — no plugin system |
| TestSQLitePlugin | SQLite plugin round-trips a query | ➖ n/a — same |
| TestContentWindowTextInputPrimitive | text-input primitive commits via IME | 🔲 `test_text_input_primitive` — e2e |
| TestContentWindowWebView | embedded webview renders | ➖ n/a — no webview |
| TestContentWindowWebViewTab | tab cycles focus through webview | ➖ n/a — same |
| TestContentWindowWebViewDrop | drop into webview works | ➖ n/a — same |
| TestContentWindowWebViewEditMenu | edit menu applies inside webview | ➖ n/a — same |
| TestContentWindowResizeFromFirstFrame | first-frame resize has correct content size | 🔲 partial: platform/native/e2e/test/e2e_test.ml:test_host_flags_and_resize → add `test_resize_first_frame` — e2e |
| TestUnifiedClipboardNativeRoundTrip | clipboard write+read round-trips all formats | ➖ n/a — no clipboard subsystem |
| TestUnifiedClipboardNativeFilesAndFailures | file clipboard + failure paths | ➖ n/a — same |
| TestUnifiedClipboardForeignOwnershipAndShutdown | foreign ownership change detected; shutdown safe | ➖ n/a — same |
| TestUnifiedClipboardNativePersistence | clipboard persists after app exits | ➖ n/a — same |
| TestUnifiedClipboardGTKForeignHTML | GTK foreign HTML reads | ➖ n/a — same |
| TestNativeGTKDataDrag | GTK drag negotiation + read | ➖ n/a — no drag subsystem |
| TestNativeGTKDragCancellationCleanup | cancelled drag cleans up | ➖ n/a — same |
| TestNativeDataRepresentations | drag data representations serialize | ➖ n/a — same |

### color gamut (`internal/gamut`)

| test | asserts | covered by |
|---|---|---|
| TestOklabKnownColors | Oklab<->linear conversions match known values | 🔲 `test_oklab_known_colors` — lui_paint |
| TestOklabRoundTrip | sRGB->Oklab->sRGB round-trips within epsilon | 🔲 `test_oklab_round_trip` — lui_paint |
| TestEncodeDecode | wide-color encode/decode round-trips, exact value | 🔲 `test_wide_encode_decode` — lui_paint |
| TestP3Matrices | P3<->XYZ matrices match published constants | 🔲 `test_p3_matrices` — lui_paint |
| TestMapInGamutIsExact | in-gamut colors map to themselves | 🔲 `test_gamut_map_in_gamut` — lui_paint |
| TestMapKeepsLightnessAndHue | gamut mapping preserves L and h, clamps C | 🔲 `test_gamut_map_preserves` — lui_paint |
| TestMapP3KeepsMoreThanSRGB | P3 target keeps more chroma than sRGB | 🔲 `test_gamut_map_p3_chroma` — lui_paint |
| TestMapOddInput | negative/NaN chroma degrades to gray, never NaN | 🔲 `test_gamut_map_odd_input` — lui_paint |
| TestMapExtremes | extreme inputs clamp to the gamut boundary | 🔲 `test_gamut_map_extremes` — lui_paint |

### GPU build and backends (`internal/gpu`)

| test | asserts | covered by |
|---|---|---|
| TestBuild | scene ops -> instanced draw buffers incl. glyph + atlas batches | platform/native/lui_gpu/test/lui_gpu_test.ml:test_build |
| TestBuildWide | wide-color set packed into instances | platform/native/lui_gpu/test/lui_gpu_test.ml:test_wide |
| TestSourceSum | shader source hash is CRLF-stable, 64 hex chars | 🔲 partial: platform/native/lui_gpu/test/lui_gpu_test.ml:test_shader_source → add `test_shader_source_sum` — lui_gpu |
| d3d11/TestDrawsAsTheCPURenderer | D3D11 output == CPU raster output | ➖ n/a — no D3D11 backend (GL parity covered by lui_gl test_gl_render) |
| d3d11/TestResizeSettles | frames settle after resize | 🔲 `test_gl_resize_settles` — lui_gl |
| d3d11/TestShaderBytecode | HLSL bytecode matches stored sums | ➖ n/a — no D3D11 backend |
| d3d11/TestComposed | composed/decorated draw path renders | ➖ n/a — same |
| d3d11/device/TestNew | device + context create | ➖ n/a — same |
| gl/TestDrawsAsTheCPURenderer | GL output == CPU raster output | platform/native/lui_gl/test/lui_gl_test.ml:test_gl_render |
| gl/TestPresentsFramesDrawnInMemory | client-rendered frames present correctly | platform/native/lui_gl/test/lui_gl_test.ml:test_gl_render |
| metal/TestDrawsAsTheCPURenderer | Metal output == CPU raster output (2 frames) | ➖ n/a — no Metal backend (GL parity covered by lui_gl test_gl_render) |
| metal/TestDrawingResourcesOnDemand | second pipeline variant creates resources lazily | 🔲 `test_gl_resources_on_demand` — lui_gl |
| metal/TestShaderLibrary | shader library source hash stable | 🔲 partial: platform/native/lui_gpu/test/lui_gpu_test.ml:test_shader_source → add `test_shader_source_sum` — lui_gpu |
| metal/TestWideColors | wide colors render on GPU | platform/native/lui_gpu/test/lui_gpu_test.ml:test_wide |

### linux platform glue (`internal/linux`)

| test | asserts | covered by |
|---|---|---|
| TestGPUDevice | GPU device probed from /dev + driver sysfs | ➖ n/a — no Linux device probing |

### raster — damage and CPU rendering (`internal/raster`)

| test | asserts | covered by |
|---|---|---|
| TestRendererRedrawsWhatChanged | damage rects stay inside changed regions (40 seeds x effects) | 🔲 `test_damage_redraws_what_changed` — lui_scene |
| TestRendererRedrawsEffects | effect/backdrop regions redraw under damage | 🔲 `test_damage_redraws_effects` — lui_scene |
| TestRendererSkipsUnchangedScenes | unchanged scene damages nothing; one op damages one rect | 🔲 `test_damage_skips_unchanged` — lui_scene |
| TestBandsDrawAsOne | banded render is pixel-identical to single pass | ➖ n/a — no banded raster path |
| TestRenderShapes | fill+shadow+clip+gradient produce expected pixels | 🔲 partial: platform/native/spike/test/test_spike_render.ml:test_sdf_fill → add `test_render_shapes` — lui_native |
| TestRenderText | glyph blit blends into the frame correctly | 🔲 partial: platform/native/spike/test/test_spike_render.ml:test_blit → add `test_render_text` — lui_native |
| TestOpaqueMaskCoverage | blend/mix-mask exhaustive 256x256 coverage table | 🔲 `test_opaque_mask_coverage` — lui_native |
| TestShadowShowsOutsideItsCast | shadow pixels appear outside the casting rect | 🔲 `test_shadow_outside_cast` — lui_native |
| TestShadowMatchesItsFormula | shadow alpha follows the Gaussian formula | 🔲 `test_shadow_formula` — lui_native |
| TestThinLineCoverage | sub-pixel-thin lines get proportional coverage | 🔲 `test_thin_line_coverage` — lui_native |

### scene — atlas and text coverage (`internal/scene`)

| test | asserts | covered by |
|---|---|---|
| TestAtlasZones | lasting glyphs pack bottom-up, transient top-down, shelf rounded to 4 | platform/native/test/lui_native_test.ml:test_atlas_alloc + test_atlas_transient |
| TestAtlasPutClearsPadding | reset clears padded bytes in the atlas | 🔲 `test_atlas_put_clears_padding` — lui_scene |
| TestAtlasRepackAndGrow | full atlas evicts + repacks on grow | platform/native/test/lui_native_test.ml:test_atlas_grow + test_atlas_repack |
| TestGammaRatios | coverage-correction gamma table: exact 4 floats, cached, edge gammas | platform/native/test/lui_native_test.ml:test_gamma_ratios |
| TestTextCoverage | text coverage correction: no-correct passthrough + corrected values | 🔲 `test_text_coverage` — lui_native |

### SVG decoding (`internal/svg`)

No SVG decoder exists in the native backend; every row is a gap owned by a
new `lui_svg` module (or `lui_image` if SVG lands inside it).

| test | asserts | covered by |
|---|---|---|
| TestFill | `<path fill>` paints correctly | 🔲 `test_svg_fill` — lui_svg (new) |
| TestPathSyntax | M/L/H/V/C/S/Q/T/A/Z path commands decode | 🔲 `test_svg_path_syntax` — lui_svg (new) |
| TestArcs | elliptical arc to cubic conversion | 🔲 `test_svg_arcs` — lui_svg (new) |
| TestFillRule | nonzero vs evenodd fill rules | 🔲 `test_svg_fill_rule` — lui_svg (new) |
| TestStrokeCaps | butt/round/square stroke caps | 🔲 `test_svg_stroke_caps` — lui_svg (new) |
| TestStrokeJoins | miter/round/bevel stroke joins | 🔲 `test_svg_stroke_joins` — lui_svg (new) |
| TestDashes | dash arrays + dash offset | 🔲 `test_svg_dashes` — lui_svg (new) |
| TestTransforms | transform= attribute math | 🔲 `test_svg_transforms` — lui_svg (new) |
| TestCurrentColor | `currentColor` resolves from context | 🔲 `test_svg_current_color` — lui_svg (new) |
| TestColors | named colors, hex, rgb(), rgba() | 🔲 `test_svg_colors` — lui_svg (new) |
| TestLinearGradient | linear gradient stops + vector | 🔲 `test_svg_linear_gradient` — lui_svg (new) |
| TestRadialGradient | radial gradient stops + focal | 🔲 `test_svg_radial_gradient` — lui_svg (new) |
| TestGroupOpacity | group opacity multiplies children | 🔲 `test_svg_group_opacity` — lui_svg (new) |
| TestClipPath | clipPath clips child paint | 🔲 `test_svg_clip_path` — lui_svg (new) |
| TestMask | mask element masks paint | 🔲 `test_svg_mask` — lui_svg (new) |
| TestStyleSheets | embedded `<style>` rules apply | 🔲 `test_svg_style_sheets` — lui_svg (new) |
| TestUse | `<use>` instantiates referenced elements | 🔲 `test_svg_use` — lui_svg (new) |
| TestDisplayAndVisibility | display=none / visibility=hidden honored | 🔲 `test_svg_display_visibility` — lui_svg (new) |
| TestSizeAndAspect | width/height/viewBox sizing + preserveAspectRatio | 🔲 `test_svg_size_aspect` — lui_svg (new) |
| TestOldEditors | tolerant of quirky output from old editors | 🔲 `test_svg_old_editors` — lui_svg (new) |
| TestErrors | malformed SVG returns error, never panic | 🔲 `test_svg_errors` — lui_svg (new) |
| TestIcons | icon set renders each glyph | 🔲 `test_svg_icons` — lui_svg (new) |
| TestUsesCurrentColor | icons recolor via currentColor | 🔲 `test_svg_uses_current_color` — lui_svg (new) |

### text layout (`internal/text`)

| test | asserts | covered by |
|---|---|---|
| TestLayoutWraps | long text wraps at the given width | platform/native/lui_text/test/lui_text_test.ml:test_shape_wrap |
| TestLayoutNewlinesAndEmpty | explicit newlines, empty string produces one empty line | platform/native/lui_text/test/lui_text_test.ml:test_newlines + test_empty |
| TestCarets | caret positions monotonic across a line | 🔲 `test_caret_positions` — lui_text |
| TestTruncation | over-width line truncates to fit | 🔲 `test_truncation` — lui_text |
| TestGlyphRaster | glyph rasterizes into an alpha mask | platform/native/lui_text/test/lui_text_test.ml:test_rasterize_mask |
| TestShadeOf | LCD subpixel shades computed per position | 🔲 `test_glyph_shades` — lui_text |
| TestGlyphShades | shade table across fractional offsets | 🔲 `test_glyph_shades` — lui_text |
| TestThick | emboldened glyph widens correctly | 🔲 `test_glyph_thick` — lui_text |
| TestFlat | flattened/hinted glyph metrics | 🔲 `test_glyph_flat` — lui_text |
| TestMaskLastsOnceDrawnAgain | glyph mask survives in atlas once redrawn | 🔲 `test_mask_lasts_drawn` — lui_scene |
| TestMakeRoom | atlas eviction frees space for a large mask | 🔲 partial: platform/native/test/lui_native_test.ml:test_atlas_repack → add `test_atlas_make_room` — lui_scene |
| TestMakeRoomForLongMasks | oversized run still fits after eviction | 🔲 `test_atlas_make_room_long` — lui_scene |
| TestRightToLeft | RTL paragraph shapes with reversed runs | platform/native/lui_text/test/lui_text_test.ml:test_rtl_paragraph |
| TestKeepSpaces | trailing spaces kept in the line box | 🔲 `test_keep_spaces` — lui_text |
| TestNoBreakWords | unbreakable words never split mid-word | 🔲 `test_no_break_words` — lui_text |
| TestEllipsis | truncation appends ellipsis glyph | 🔲 `test_ellipsis` — lui_text |
| TestColorEmoji | emoji shaped as color bitmap glyph | platform/native/lui_text/test/lui_text_test.ml:test_emoji_color_glyph |
| TestRegisterFont | runtime-registered font resolves | 🔲 `test_register_font` — lui_text |
| TestUIFamily | UI-default family resolves to a real font | 🔲 `test_ui_family` — lui_text |
| TestLetterSpacing | letter spacing widens advances | 🔲 `test_letter_spacing` — lui_text |
| TestFontFeatures | `kern` on/off changes shaping | 🔲 `test_font_features` — lui_text |
| TestParseFeatures | feature-string syntax parses | 🔲 `test_parse_features` — lui_text |
| TestSpans | styled spans produce per-run fonts | 🔲 `test_spans` — lui_text |
| TestEncodeSpans | span encoding round-trips | 🔲 `test_encode_spans` — lui_text |
| TestSpansAcrossParagraphs | spans split correctly across paragraphs | 🔲 `test_spans_across_paragraphs` — lui_text |
| TestDigitFeatures | tnum/pnum digit feature toggles | 🔲 `test_digit_features` — lui_text |
| TestFontListFallback | missing glyphs fall back through the font list | platform/native/lui_text/test/lui_text_test.ml:test_fallback_font |
| TestFontsOfManySizes | same text at many sizes shapes consistently | 🔲 `test_fonts_many_sizes` — lui_text |
| TestPlacement | glyph positions quantized to subpixel grid | platform/native/lui_text/test/lui_text_test.ml:test_subpixel_positions |
| TestDecorate | underline/strikethrough geometry | 🔲 `test_decorate` — lui_text |
| caret/TestVisualCaretAffinityAndNavigation | visual caret affinity on bidi edges; nav sequence | 🔲 `test_visual_caret_nav` — lui_text |
| caret/TestVisualSelectionKeepsBidiGaps | visual selection covers bidi gaps | 🔲 `test_visual_selection_bidi` — lui_text |
| caret/TestVisualCaretFractionalRunEdges | caret lands on fractional run edges | 🔲 `test_visual_caret_fractional` — lui_text |
| caret/TestVisualCaretWrapAndGraphemes | caret across wraps + grapheme clusters | 🔲 `test_visual_caret_wrap` — lui_text |
| caret/TestVisualCaretHitBeforeTrimmedWrapSpace | hit-test before trimmed trailing wrap space | 🔲 `test_caret_hit_wrap_space` — lui_text |
| memory/TestLayoutCacheBoundsScrollingMemory | layout cache bounds memory while scrolling | 🔲 `test_layout_cache_bounds` — lui_text |
| memory/TestLayoutCacheReusesDisplayedText | redisplayed text reuses cached layout | 🔲 `test_layout_cache_reuses` — lui_text |
| memory/TestLayoutCacheReleasesEvictedText | evicted layouts release memory | 🔲 `test_layout_cache_releases` — lui_text |
| memory/TestLayoutCacheKeepsFrequentlyUsedText | hot paragraphs stay cached | 🔲 `test_layout_cache_keeps_hot` — lui_text |
| memory/TestLayoutCacheSkipsOversizedParagraph | oversized paragraph bypasses cache | 🔲 `test_layout_cache_skips_oversized` — lui_text |
| memory/TestRetainedLayoutDoesNotRetainClearedCache | retained layout frees cleared cache | 🔲 `test_retained_layout_cache` — lui_text |
| memory/TestLayoutCacheDoesNotRetainExcerptSource | excerpt source not retained by cache | 🔲 `test_cache_no_retain_source` — lui_text |
| pango/TestPangoLayoutAtMeasuredWidth | pango layout width == measured width across families/sizes/strings | platform/native/lui_text_pango/test/lui_text_pango_test.ml:test_measure_matches |
| pango/TestPangoLayoutAtMeasuredWidthWithLetterSpacing | same with letter spacing | 🔲 `test_pango_letter_spacing` — lui_text_pango |

### codegen / migration / vet tooling (`internal/tsgen`, `internal/uimigrate`, `internal/uivet`)

| test | asserts | covered by |
|---|---|---|
| tsgen TestGenerate | generated TS source contents | ➖ n/a — no TS codegen |
| tsgen TestGeneratedCodeTypeChecks | generated code passes tsc | ➖ n/a — same |
| tsgen TestNames | camel/eventKey naming conventions | ➖ n/a — same |
| tsgen TestValidate | unsupported types rejected | ➖ n/a — same |
| tsgen TestStructFieldConflicts | field-name conflicts detected | ➖ n/a — same |
| uimigrate TestMigrationPreservesLocalValuePolling | rewrite keeps value polling | ➖ n/a — no Go-API migration tool |
| uimigrate TestMigrationAliasesScopesAndNilValues | alias scopes + nil values preserved | ➖ n/a — same |
| uimigrate TestMigrationPreservesNonUIAliases | non-UI aliases untouched | ➖ n/a — same |
| uimigrate TestMigrationBuilderCallbacks | builder callbacks rewritten correctly | ➖ n/a — same |
| uimigrate TestMigrationDotImportRequiresReview | dot-import flagged for review | ➖ n/a — same |
| uimigrate TestMigrationDoesNotChangeOtherBuilders | unrelated builders unchanged | ➖ n/a — same |
| uimigrate TestMigrationKeysBeforeConstruction | keys emitted before construction | ➖ n/a — same |
| uimigrate TestMigrationSharesPackageFieldsAndTupleHelpers | shared helpers deduped | ➖ n/a — same |
| uivet TestStoredValuesAndGoroutineCaptures | vet analysis flags stored values + captures | ➖ n/a — no Go vet analyzer |

### updater (`internal/update`)

| test | asserts | covered by |
|---|---|---|
| TestSuffixArray | bsdiff suffix array construction | ➖ n/a — no updater |
| TestDiffPatch | binary diff+patch round-trip | ➖ n/a — same |
| TestDelta | delta update applies | ➖ n/a — same |
| TestDesktopEntry | .desktop file rewrite | ➖ n/a — same |
| TestRefreshDesktopEntry | desktop-entry refresh | ➖ n/a — same |
| TestResolveFeed | GitHub release feed resolves latest | ➖ n/a — same |
| TestCompare | semver compare | ➖ n/a — same |
| TestSignatures | ed25519 signature verify | ➖ n/a — same |
| TestArchive | release archive unpacks | ➖ n/a — same |
| TestReleaseNotes | release notes render | ➖ n/a — same |

### windows platform glue (`internal/windows`)

| test | asserts | covered by |
|---|---|---|
| TestClipboardDIBRejectsInvalidGeometry | invalid DIB geometry rejected | ➖ n/a — no Win32 clipboard backend |
| TestTransferDataStreamPosition | clipboard/drag stream position across payload sizes | ➖ n/a — same |

## Upstream `ui/` suite — widget semantics layer

The upstream `ui/` package is a full widget toolkit with focus, shortcuts,
IME, a11y, lists, overlays, router and inspector subsystems. Our native
backend is the rendering-runtime layer (store -> paint -> scene -> GPU ->
host events), so most interaction-level rows are gaps owned by `e2e` (the
host event harness) unless noted.

### a11y (`ui/access_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestAccessibilityTree | a11y tree built when AccessibilityOn | platform/native/lui_a11y/test/lui_a11y_test.ml:test_build_forest + test_flatten_preorder + test_hidden_excluded |
| TestAccessibilityOfLists | list rows expose roles/labels | 🔲 partial: platform/native/lui_a11y/test/lui_a11y_test.ml:test_role_table_complete → add `test_a11y_list` — e2e |
| TestAccessibilityScrollsToARowNoLongerBuilt | scroll keeps a11y on unbuilt row | 🔲 `test_a11y_scroll_unbuilt_row` — e2e |
| TestAccessibilityOfTables | table cells exposed | 🔲 partial: platform/native/lui_a11y/test/lui_a11y_test.ml:test_role_table_complete → add `test_a11y_table` — e2e |
| TestAccessibilityOfOverlays | overlay content in tree | 🔲 `test_a11y_overlays` — e2e |
| TestRole | role prop maps to a11y role | platform/native/lui_a11y/test/lui_a11y_test.ml:test_role_table_complete + test_role_fallbacks + test_role_prop_override |
| TestInputMethodContext | IME context reported in a11y | 🔲 `test_a11y_ime_context` — e2e |

### action queries and pending edits (`ui/action_queries_test.go`, `ui/api_bench_test.go`, `ui/bench_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestActionQueriesReadPendingBoundEdit | action query sees uncommitted edit | 🔲 partial: platform/native/e2e/test/e2e_test.ml:test_text_changed → add `test_action_query_pending_edit` — e2e |
| TestScopedShortcutQueriesReadPendingBoundEdit | scoped shortcut sees pending edit | 🔲 `test_shortcut_pending_edit` — e2e |
| TestActionQueriesRespectFluentInputConfiguration | fluent input config honored | 🔲 `test_action_query_input_config` — e2e |
| TestValueFrameRetainedHeap (bench) | retained heap across frames | ➖ n/a — benchmark |
| testdata/TestValueFrameRetainedHeap (legacy bench) | same, legacy API variant | ➖ n/a — benchmark |
| TestDiffFrameAllocs (bench) | per-frame allocation budget | ➖ n/a — benchmark |

### widget bases (`ui/base_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestBasesHaveNoLook | bare bases draw nothing | 🔲 `test_bases_no_look` — e2e |
| TestToggleBases | toggle base toggles on click | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_checkbox + test_switch + test_radio → add `test_toggle_bases` — e2e |
| TestSliderBaseMapsItsContentBox | slider maps pointer to content box | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_slider → add `test_slider_content_box` — e2e |
| TestTabsBase | tab base switches pages | 🔲 `test_tabs_base` — e2e |
| TestSelectBase | select base opens and chooses | 🔲 `test_select_base` — e2e |
| TestDialogAndPopoverBases | dialog/popover bases open modal/non-modal | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_popup_xy → add `test_dialog_popover_bases` — e2e |
| TestDismissed | light-dismiss fires and closes | 🔲 `test_dismissed` — e2e |
| TestTextInputBase | text input base edits text | 🔲 partial: platform/native/e2e/test/e2e_test.ml:test_text_changed → add `test_text_input_base` — e2e |
| TestFocusRing | focus ring shows only on keyboard focus | 🔲 `test_focus_ring` — e2e |
| TestPopupsOpenWhereTheyFit | popup flips to fit the window | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_popup_xy → add `test_popups_open_where_fit` — e2e |
| TestEnterWithWindowShortcut | Enter triggers window-level shortcut | 🔲 `test_enter_window_shortcut` — e2e |

### bitmaps (`ui/bitmap_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestBitmapShowsSmallerSmoothly | downscaled bitmap stays smooth | 🔲 `test_bitmap_downscale` — lui_image |
| TestHalve | halved bitmaps keep quality | 🔲 `test_bitmap_halve` — lui_image |
| TestDecodeBitmapTurnsPhotosUpright | EXIF orientation applied | 🔲 `test_bitmap_exif` — lui_image |
| TestDecodeBitmapOfWebPAndBMP | WebP + BMP decode | 🔲 partial: platform/native/lui_image/test/lui_image_test.ml:test_decode_bmp → add `test_decode_webp` — lui_image |
| TestBitmapUpdate | updated bitmap repaints | 🔲 partial: platform/native/lui_image/test/lui_image_test.ml:test_cache_frame → add `test_bitmap_update` — lui_image |

### collapsible / combobox (`ui/collapsible_test.go`, `ui/combobox_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestCollapsible | section opens/closes and changes | 🔲 `test_collapsible` — e2e |
| TestCollapsibleAnimates | open/close animates | 🔲 `test_collapsible_animates` — e2e |
| TestAccordion | only one section open at once | 🔲 `test_accordion` — e2e |
| TestComboboxChosenRebuildsDependentUI | choosing rebuilds dependents | 🔲 `test_combobox_rebuild` — e2e |
| TestCombobox | combobox lists, filters, chooses | 🔲 `test_combobox` — e2e |
| TestComboboxAccessibility | combobox exposes a11y | 🔲 partial: platform/native/lui_a11y/test/lui_a11y_test.ml:test_state_flags → add `test_combobox_a11y` — e2e |
| TestAutocomplete | inline autocomplete completes | 🔲 `test_autocomplete` — e2e |
| TestSearchField | search field filters live | 🔲 `test_search_field` — e2e |
| TestTokenField | token field adds/removes tokens | 🔲 `test_token_field` — e2e |
| TestComboboxScrollsPastHighlight | popup scrolls to keep highlight visible | 🔲 `test_combobox_scroll_highlight` — e2e |
| TestSelectBaseScrollsToHighlight | select scrolls to highlighted item | 🔲 `test_select_scroll_highlight` — e2e |

### data drag / file drop (`ui/data_drag_test.go`, `ui/drop_test.go`, `ui/dragdrop_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestNativeDataDropNegotiatesAndReadsOnDrop | drop negotiates formats and reads data | 🔲 `test_data_drop_negotiate` — e2e |
| TestNativeTypedDropKeepsGoValue | typed value survives the drop | 🔲 `test_data_drop_typed` — e2e |
| TestNativeDragCancellationAndSourceRemoval | cancel + source removal clean up | 🔲 `test_drag_cancel_cleanup` — e2e |
| TestNativeDragCloseReleasesTextInputClient | drag close releases IME client | 🔲 `test_drag_close_releases_ime` — e2e |
| TestNativeDestinationRejectsMismatchDisabledAndFailedData | destination rejects bad/disabled/failed drags | 🔲 `test_drag_rejects` — e2e |
| TestDragAndDrop | app-level drag and drop moves data | 🔲 `test_drag_and_drop` — e2e |
| TestListReorder | drag reorders list | 🔲 `test_list_reorder` — e2e |
| TestGridReorder | drag reorders grid | 🔲 `test_grid_reorder` — e2e |
| TestFileDrops | file drop reaches handler with paths | 🔲 `test_file_drops` — e2e |

### date/time/color pickers (`ui/datetime_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestCalendar | calendar navigates and picks a date | 🔲 `test_calendar` — e2e |
| TestTimeInput | time input parses and edits | 🔲 `test_time_input` — e2e |
| TestColorPicker | color picker picks and previews | 🔲 `test_color_picker` — e2e |
| TestColorWell | color well opens picker | 🔲 `test_color_well` — e2e |

### editor input client (`ui/editor_input_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestWidgetInputUsesClientBetweenFrames | input client reused between frames | 🔲 `test_editor_client_between_frames` — e2e |
| TestWidgetCompositionHasOneUndoTransaction | composition is one undo unit | 🔲 `test_editor_composition_undo` — e2e |
| TestWidgetInputPrivacyAndReadonly | privacy/readonly inputs reject IME | 🔲 `test_editor_privacy_readonly` — e2e |
| TestWidgetBidiSelectionCopyReplaceAndUndo | bidi selection copy/replace/undo | 🔲 `test_editor_bidi_selection` — e2e |
| TestWidgetNativeQueryDoesNotRetainOldDocument | native query releases old document | 🔲 `test_editor_query_no_retain` — e2e |
| TestWidgetSingleLineLayoutReleasesOldDocument | single-line relayout releases document | 🔲 `test_editor_layout_release` — e2e |
| TestWidgetNativeQueryMalformedUTF8 | malformed UTF-8 in query handled | 🔲 `test_editor_malformed_utf8` — e2e |

### feedback — toasts, dialogs, breadcrumbs (`ui/feedback_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestToastAction | toast action button fires | 🔲 `test_toast_action` — e2e |
| TestCheckboxGroup | grouped checkboxes share state | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_checkbox → add `test_checkbox_group` — e2e |
| TestBreadcrumbs | breadcrumb trail navigates | 🔲 `test_breadcrumbs` — e2e |
| TestAlertDialog | alert dialog opens and confirms | 🔲 `test_alert_dialog` — e2e |
| TestAlertDialogEscape | Escape cancels the dialog | 🔲 `test_alert_dialog_escape` — e2e |
| TestAlertDialogKeepOpen | action can keep dialog open | 🔲 `test_alert_dialog_keep_open` — e2e |
| TestFindBar | find bar searches and navigates matches | 🔲 `test_find_bar` — e2e |

### forms (`ui/form_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestField | labelled field wraps a control | 🔲 `test_field` — e2e |
| TestFieldDisabled | fieldset disables children | 🔲 `test_field_disabled` — e2e |
| TestFormLayout | form layout aligns labels and controls | 🔲 `test_form_layout` — e2e |

### frame/build semantics (`ui/frame_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestValueHandleExpiresBeforeStorageReuse | expired value handles detected before storage reuse | 🔲 `test_value_handle_expiry` — e2e |
| TestCapturedContextUsesCurrentParent | captured context rebinds to current parent | 🔲 `test_captured_context_parent` — e2e |
| TestActionsRunAfterBuildOnce | actions run once after build | 🔲 `test_actions_after_build` — e2e |
| TestDeferredControlIdentityAndConfiguration | deferred control keeps identity + config | 🔲 `test_deferred_control` — e2e |
| TestReferenceFocusWaitsForControl | focus-by-reference waits for the control | 🔲 `test_refocus_waits` — e2e |
| TestDeferredInputOptions | deferred input options apply | 🔲 `test_deferred_input_options` — e2e |
| TestValueHandlesDetachClosedWindow | handles detach on window close | 🔲 `test_handles_detach_close` — e2e |
| TestCustomPartsUseCheckedValuesAndKeys | custom parts validate values + keys | 🔲 `test_custom_parts` — e2e |
| TestPublicRowScopeAndKeyboardActions | row scope + keyboard actions public | 🔲 `test_row_scope_keyboard` — e2e |
| TestWindowServicesOutliveBuild | window services survive the build | 🔲 `test_services_outlive_build` — e2e |
| TestExpiredHandleDiagnosticsAndSlotReuse | expired handle diagnostics; slots reused | 🔲 `test_handle_diagnostics` — e2e |
| TestHandleQueriesBeforeBindingAndAcrossWindows | handle queries work pre-bind and across windows | 🔲 `test_handle_queries` — e2e |
| TestHandleShortcutBeforeBindingDropsHiddenControl | shortcut dropped for hidden control | 🔲 `test_shortcut_hidden_control` — e2e |
| TestFocusBindingDistinguishesRequestedAndActual | requested vs actual focus distinguished | 🔲 `test_focus_binding` — e2e |
| TestBoundInputRunsAfterAllConfiguration | bound input applies after config | 🔲 `test_bound_input_timing` — e2e |
| TestChangedCommitsLocalValueBeforeReturning | Changed commits local value first | 🔲 partial: platform/native/e2e/test/e2e_test.ml:test_text_changed → add `test_changed_commits` — e2e |
| TestResponseQueriesCommitLocalText | response queries commit local text | 🔲 `test_response_commit_text` — e2e |
| TestResponseQueriesProcessLaterControls | queries process later controls | 🔲 `test_response_later_controls` — e2e |
| TestChangedCommitsLocalCompositeValues | composite values commit | 🔲 `test_changed_composite` — e2e |
| TestChangedAppliesSliderOptionsBeforeInput | slider options apply before input | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_slider → add `test_changed_slider_options` — e2e |
| TestChangeActionsCommitDerivedValuesBeforeRebuild | derived values commit pre-rebuild | 🔲 `test_changed_derived` — e2e |
| TestNoticeActionsCommitDerivedText | notice actions commit derived text | 🔲 `test_notice_derived_text` — e2e |
| TestGenerationWrapRetiresOwner | generation wrap retires owner | 🔲 partial: platform/native/e2e/test/e2e_test.ml:test_echo_suppressed → add `test_generation_wrap` — e2e |
| TestHandleBoundsBetweenBuilds | handle bounds consistent between builds | 🔲 `test_handle_bounds` — e2e |
| TestCloseWhileBuilding | closing mid-build is safe | 🔲 `test_close_while_building` — e2e |

### frame stats (`ui/framestats_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestFrameStatsSetting | setting parsed | 🔲 `test_framestats_setting` — e2e |
| TestFrameStats | stats collected per frame | 🔲 `test_framestats` — e2e |

### GPU availability/fallback (`ui/gpu_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestGPUComesBack | GPU path resumes after loss | 🔲 `test_gpu_comes_back` — lui_gl |
| TestSoftwareUntilTheGPUIsBack | software rendering while GPU is down | 🔲 `test_software_fallback` — lui_gl |
| TestNoGPUFromTheStart | software path when GPU never appears | 🔲 `test_no_gpu_start` — lui_gl |
| TestEveryFrameOnTheGPU | every frame uses GPU when available | 🔲 `test_every_frame_gpu` — lui_gl |

### grid view (`ui/gridview_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestGridView | grid lays out and selects | 🔲 `test_gridview` — e2e |
| TestGridViewChoosesSeveral | multi-select in grid | 🔲 `test_gridview_multi` — e2e |
| TestGridViewResizes | grid adapts to resize | 🔲 `test_gridview_resizes` — e2e |

### indicators (`ui/indicators_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestSpinner | spinner animates/renders | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_spinner → add `test_spinner_behavior` — e2e |
| TestMeter | meter shows value | 🔲 `test_meter` — e2e |
| TestRating | rating widget sets stars | 🔲 `test_rating` — e2e |
| TestStepper | stepper increments/decrements | 🔲 `test_stepper` — e2e |
| TestStepSlider | stepped slider snaps | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_slider → add `test_step_slider` — e2e |
| TestRangeSlider | range slider moves both thumbs | 🔲 `test_range_slider` — e2e |
| TestAvatar | avatar renders image/initials | 🔲 `test_avatar` — e2e |
| TestInitials | initials incl. CJK render | 🔲 `test_initials` — e2e |

### inline content (`ui/inline_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestInlineLink | inline link renders and clicks | 🔲 `test_inline_link` — e2e |
| TestInlineStyles | inline spans restyle | 🔲 `test_inline_styles` — e2e |
| TestInlineInteraction | inline widgets interact | 🔲 `test_inline_interaction` — e2e |
| TestInlineOnlyText | non-text inline content panics | 🔲 `test_inline_only_text_panics` — e2e |

### inspector (`ui/inspector_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestInspectorOpensAndCloses | inspector toggles | ➖ n/a — no inspector tool |
| TestInspectorFollowsTheContent | inspector tracks content | ➖ n/a — same |
| TestInspectorPicksAndDescribes | element picking + describe | ➖ n/a — same |
| TestInspectorTree | inspector tree view | ➖ n/a — same |
| TestInspectorTabs | inspector tab panels | ➖ n/a — same |
| TestInspectorDarkPalette | inspector uses dark palette | ➖ n/a — same |
| TestInspectorSettles | inspector stops settling frames | ➖ n/a — same |
| TestInspectorInsetShadow | inset shadow inside inspector | ➖ n/a — same |

### layout grow (`ui/layout_grow_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestGrowInColumnOfContentHeight | grow expands inside content-height column | platform/native/lui_flex/test/lui_flex_test.ml:test_flex_grow |

### element lifetime/state (`ui/lifetime_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestOptionalElementInput | optional element input binds/unbinds | 🔲 `test_optional_element_input` — e2e |
| TestListStateFocusAndShortcutsFollowCurrentBuild | state focus/shortcuts follow current build | 🔲 `test_list_state_focus` — e2e |
| TestListStateFocusDuringRowBuild | focus set during row build applies | 🔲 `test_list_focus_during_build` — e2e |
| TestListStateInputRequiresItsActiveContext | state input needs active context | 🔲 `test_list_state_context` — e2e |

### sideways list (`ui/list_sideways_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestListRowWidth | row width fills the list | 🔲 `test_list_row_width` — e2e |
| TestListRowWidthFits | row width fits content | 🔲 `test_list_row_width_fits` — e2e |

### virtual list (`ui/list_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestListVariableHeights | variable-height rows lay out | 🔲 `test_list_variable_heights` — e2e |
| TestListFillsTheFirstFrame | first frame fills viewport | 🔲 `test_list_fills_first_frame` — e2e |
| TestListHugeScrollsByFractions | huge scrolls land by fractions | 🔲 `test_list_huge_scrolls` — e2e |
| TestListScrollTo | ScrollTo aligns a row | 🔲 `test_list_scroll_to` — e2e |
| TestListKeepsPlaceAsRowsAboveChange | scroll position kept when rows above change | 🔲 `test_list_keeps_place` — e2e |
| TestListKeys | arrow keys move the choice | 🔲 `test_list_keys` — e2e |
| TestListFollowEnd | FollowEnd sticks to the end | 🔲 `test_list_follow_end` — e2e |
| TestListFollowEndStartsAtTheEnd | FollowEnd starts at end | 🔲 `test_list_follow_end_start` — e2e |
| TestListJustifyEnd | justify-end packs rows at bottom | 🔲 `test_list_justify_end` — e2e |
| TestListGapAndPadding | gap + padding applied | 🔲 `test_list_gap_padding` — e2e |
| TestListRowsGoAway | removed rows disappear | 🔲 `test_list_rows_go_away` — e2e |
| TestListSelection | selection state tracked | 🔲 `test_list_selection` — e2e |
| TestListKeysKeepTheChoice | keys keep the chosen row | 🔲 `test_list_keys_keep_choice` — e2e |
| TestListKeepsTheFocusedRow | focused row stays visible | 🔲 `test_list_keeps_focused` — e2e |
| TestListStickyHeaders | sticky headers pin | 🔲 `test_list_sticky_headers` — e2e |
| TestListRowsShowBelowThePinnedHeader | rows show under pinned header | 🔲 `test_list_rows_below_pinned` — e2e |
| TestListStickyHeadersSkipTheChoice | choice skips sticky headers | 🔲 `test_list_sticky_skip_choice` — e2e |
| TestListScrollBarDragReachesTheEnd | scrollbar drag reaches the end | 🔲 `test_list_scrollbar_end` — e2e |
| TestListScrollBarDragFollowsThePointerAsEstimatesChange | scrollbar tracks pointer as estimates update | 🔲 `test_list_scrollbar_estimates` — e2e |
| TestListStateOfTwoListsPanics | shared state on two lists panics | 🔲 `test_list_two_states_panic` — e2e |
| TestListTabRevealsRows | Tab reveals rows | 🔲 `test_list_tab_reveals` — e2e |
| TestListViewSeesWhereItIs | list knows its scroll position | 🔲 `test_list_view_position` — e2e |
| TestListKeepsPlaceAcrossResizes | position kept across resizes | 🔲 `test_list_keeps_place_resize` — e2e |
| TestListKeepsPlaceWhenBuiltAnew | position kept across rebuild | 🔲 `test_list_keeps_place_rebuild` — e2e |
| TestListNewStateStartsAtTheStart | new state starts at top | 🔲 `test_list_new_state_start` — e2e |
| TestListHeights | measured heights model honored | 🔲 `test_list_heights` — e2e |
| TestListPinnedHeaderHandlesAClickOnce | pinned header click fires once | 🔲 `test_list_pinned_click_once` — e2e |
| TestListScrollAndRowsAboveInOneFrame | scroll + new rows settle in one frame | 🔲 `test_list_scroll_rows_one_frame` — e2e |
| TestListEndShowsTheEnd | end-of-list shows last row | 🔲 `test_list_end` — e2e |
| TestListScrollsByTheStepIntoRowsNotMeasured | step-scroll into unmeasured rows | 🔲 `test_list_step_unmeasured` — e2e |
| TestListTrackScrollBeforeTheFirstFrame | track scroll pre-first-frame works | 🔲 `test_list_track_prefirst` — e2e |
| TestListOfManyStates | many independent list states | 🔲 `test_list_many_states` — e2e |
| TestListRevealsAFarRowWithoutAGap | far-row reveal has no gap | 🔲 `test_list_reveal_far` — e2e |
| TestListSizedByItsRows | list sized by rows | 🔲 `test_list_sized_by_rows` — e2e |
| TestListEmpty | empty list renders | 🔲 `test_list_empty` — e2e |
| TestListChoiceAtTheEnds | choice clamps at both ends | 🔲 `test_list_choice_ends` — e2e |

### memory discipline (`ui/memory_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestRemovedContentReleasesResources | removed content frees resources | 🔲 partial: platform/native/e2e/test/e2e_test.ml:test_dispose → add `test_removed_releases` — e2e |
| TestElementArenaFollowsViewSize | element arena sized to view | 🔲 `test_element_arena_size` — e2e |
| TestEditorUndoReleasesOldDocument | undo frees old document | 🔲 `test_editor_undo_release` — e2e |
| TestEditorDiscardedRedoReleasesDocument | discarded redo frees document | 🔲 `test_editor_redo_release` — e2e |
| TestEditorSmallDocumentReleasesIndexes | small doc frees indexes | 🔲 `test_editor_index_release` — e2e |
| TestEditorParagraphLayoutReleasesOldDocument | paragraph relayout frees document | 🔲 `test_editor_paragraph_release` — e2e |

### menus (`ui/menu_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestContextMenu | context menu opens on right-click | 🔲 `test_context_menu` — e2e |
| TestInnermostContextMenu | innermost menu wins | 🔲 `test_innermost_menu` — e2e |
| TestContextMenuFromTheKeyboard | keyboard opens context menu | 🔲 `test_menu_keyboard` — e2e |
| TestTextInputContextMenu | text input menu offers edit items | 🔲 `test_input_context_menu` — e2e |
| TestAccelerator | accelerator string renders correctly | 🔲 `test_menu_accelerator_string` — e2e |
| TestMenuButton | menu button opens menu | 🔲 `test_menu_button` — e2e |
| TestMenuButtonAccessibility | menu button exposes a11y | 🔲 partial: platform/native/lui_a11y/test/lui_a11y_test.ml:test_state_flags → add `test_menu_button_a11y` — e2e |
| TestMenuAndContextMenuOfOneElement | menu + context coexist on one element | 🔲 `test_menu_and_context` — e2e |

### modifiers / outline (`ui/modifiers_test.go`, `ui/outline_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestModifiersHeld | held modifier state reported | 🔲 `test_modifiers_held` — e2e |
| TestOutline | tree outline expands/collapses | 🔲 `test_outline` — e2e |
| TestOutlineBuildsWhatShows | outline builds only visible nodes | 🔲 `test_outline_lazy` — e2e |
| TestOutlineTable | tabular outline renders | 🔲 `test_outline_table` — e2e |
| TestOutlineExpandsForAssistiveTechnology | a11y expand requests honored | 🔲 `test_outline_a11y` — e2e |

### paint and repaint (`ui/paint_test.go`, `ui/repaint_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestAnimatedPathShowsInEveryFrame | animated path drawn each frame | 🔲 `test_animated_path` — lui_paint |
| TestFramesStayWholeWhenTheAtlasFills | frames stay whole when atlas fills | 🔲 `test_atlas_full_frames` — lui_gl |
| TestFramesRedrawOnlyWhatChanged | only damaged regions redraw | 🔲 `test_damage_redraws_only_changed` — lui_scene |
| TestOpaqueUnderElements | opaque optimization under elements | 🔲 `test_opaque_under` — lui_gl |
| TestRepaintFrames | repaint requests produce frames | 🔲 partial: platform/native/e2e/test/e2e_test.ml:test_host_flags_and_resize → add `test_repaint_frames` — e2e |
| TestRepaintOnlyInView | repaints limited to visible area | 🔲 `test_repaint_in_view` — e2e |
| TestPainterAfter | painter draws after content | 🔲 `test_painter_after` — e2e |
| TestIndicatorsRepaint | indicator repaints keep ticking | 🔲 `test_indicators_repaint` — e2e |
| TestHeldWhileOccluded | held state survives occlusion | 🔲 `test_held_occluded` — e2e |

### paste / preferences (`ui/paste_test.go`, `ui/preferences_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestOnPaste | paste event delivers text | 🔲 `test_on_paste` — e2e |
| TestThemeFollowsTheAccent | theme follows accent preference | 🔲 `test_theme_accent` — e2e |
| TestThemeFollowsContrastAndTextSize | contrast + text-size prefs apply | 🔲 `test_theme_contrast_size` — e2e |
| TestAnimateWithoutMotion | reduce-motion disables animation | 🔲 `test_animate_no_motion` — e2e |
| TestOwnThemeIgnoresPreferences | custom theme ignores OS prefs | 🔲 `test_own_theme_prefs` — e2e |

### primitives (`ui/primitives_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestAccessStatesOfYourOwn | element reads its own states | 🔲 `test_access_own_states` — e2e |
| TestReadOnlyInput | readonly input rejects edits | 🔲 `test_readonly_input` — e2e |
| TestComposing | composition state exposed during IME | 🔲 `test_composing` — e2e |
| TestOpenURLOutcome | open-URL reports outcome | 🔲 `test_open_url` — e2e |
| TestPopoverLightDismiss | light dismiss closes popover | 🔲 `test_popover_light_dismiss` — e2e |
| TestAttachTo | attach keeps children anchored | 🔲 `test_attach_to` — e2e |
| TestModalOverlayOfYourOwn | modal overlay blocks behind | 🔲 `test_modal_overlay` — e2e |
| TestSliderBaseSettings | slider settings apply | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_slider → add `test_slider_settings` — e2e |
| TestSelectHighlight | select highlights chosen item | 🔲 `test_select_highlight` — e2e |
| TestDisabledStepper | disabled stepper rejects input | 🔲 `test_disabled_stepper` — e2e |
| TestSnapToTheStepsDecimals | value snaps to decimal steps | 🔲 `test_snap_decimals` — e2e |
| TestPathsLookTheSameWhateverDrewBefore | path output independent of draw history | 🔲 `test_paths_state_independent` — lui_gl |
| TestStrokesAreAsWideAsAsked | stroke widths honored exactly | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_per_edge_borders → add `test_stroke_widths` — lui_paint |
| TestDrawer | drawer slides over content | 🔲 `test_drawer` — e2e |
| TestPopoverScrollsWithItsAnchor | popover tracks anchor while scrolling | 🔲 `test_popover_scroll_anchor` — e2e |
| TestEscapeClosesTheInnerPopover | Escape closes innermost popover only | 🔲 `test_escape_inner_popover` — e2e |
| TestAttachToInlineText | attach anchored to inline text | 🔲 `test_attach_inline_text` — e2e |
| TestRangeSteps | range widget steps correctly | 🔲 `test_range_steps` — e2e |
| TestPasteDuringFrame | paste mid-frame handled | 🔲 `test_paste_during_frame` — e2e |

### rich text (`ui/richtext_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestRichText | styled spans render | 🔲 `test_rich_text` — lui_text |
| TestMeasureTextAgain | measure-text cache consistent | 🔲 `test_measure_text_cache` — lui_text |

### router (`ui/router_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestRouteMatch | route patterns match | ➖ n/a — no router |
| TestRouterHistory | history push/pop | ➖ n/a — same |
| TestRouterView | routed view renders | ➖ n/a — same |
| TestRouterKeepsPages | back-stack keeps pages | ➖ n/a — same |
| TestRouterFocus | focus follows route | ➖ n/a — same |
| TestRouterTransition | route transitions | ➖ n/a — same |
| TestRouterNested | nested routers | ➖ n/a — same |
| TestAnnounce | route changes announced | ➖ n/a — same |
| TestEditorLeavesHistoryKeys | editor leaves history keys to router | ➖ n/a — same |
| TestRouterLayouts | routed layouts | ➖ n/a — same |

### focus scope and overlays (`ui/scope_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestDialogKeepsTheFocus | modal dialog traps focus | 🔲 `test_dialog_focus_trap` — e2e |
| TestEscapeClosesTheOverlayOnTop | Escape closes top overlay | 🔲 `test_escape_top_overlay` — e2e |
| TestOverlayGivesTheFocusBack | closing overlay restores focus | 🔲 `test_overlay_focus_back` — e2e |
| TestShortcutsWaitBehindADialog | shortcuts blocked behind dialog | 🔲 `test_shortcuts_behind_dialog` — e2e |
| TestPopoverFollowsItsAnchor | popover follows anchor on relayout | 🔲 `test_popover_follow_anchor` — e2e |
| TestBehindADialogIsHidden | behind-dialog content hidden from a11y | 🔲 partial: platform/native/lui_a11y/test/lui_a11y_test.ml:test_hidden_excluded → add `test_dialog_hides_a11y` — e2e |
| TestEscapeGoesToTheFocusedElementFirst | Escape targets focused element first | 🔲 `test_escape_focused_first` — e2e |

### scrolling (`ui/scroll_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestTrackScroll | scrollbar track drag scrolls | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_scrollbar → add `test_track_scroll` — e2e |
| TestTrackScrollSettles | track scroll settles | 🔲 `test_track_scroll_settles` — e2e |
| TestTrackScrollFollowsTheEnd | scroll follows the end on append | 🔲 `test_track_scroll_end` — e2e |
| TestTrackScrollPerPage | page-up/down in track | 🔲 `test_track_scroll_page` — e2e |
| TestTrackScrollList | track scroll in a list | 🔲 `test_track_scroll_list` — e2e |
| TestScrollIntoView | scrolls element into view | 🔲 `test_scroll_into_view` — e2e |
| TestScrollIntoViewNested | nested scroll containers | 🔲 `test_scroll_into_view_nested` — e2e |
| TestTabScrollsTheFocusIntoView | Tab scrolls focused element into view | 🔲 `test_tab_scrolls_focus` — e2e |

### selection (`ui/select_test.go`, `ui/selection_test.go`, `ui/selection_press_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestSelectableText | text selects by drag | 🔲 `test_selectable_text` — e2e |
| TestPressedSelectionRebuildsBeforePaint | pressed state rebuilds before paint | 🔲 partial: platform/native/e2e/test/e2e_test.ml:test_press_add_remove_promote → add `test_pressed_rebuilds` — e2e |
| TestButtonClickStillWaitsForRelease | click commits on release | 🔲 `test_click_waits_release` — e2e |
| TestClickModifiers | shift/ctrl click modifiers | 🔲 `test_click_modifiers` — e2e |
| TestListChoosesSeveral | multi-select with mouse | 🔲 `test_list_multi_select` — e2e |
| TestListExtendsTheChoiceWithTheKeys | keys extend the choice | 🔲 `test_list_extend_keys` — e2e |
| TestListMovesWithoutChoosing | move cursor without choosing | 🔲 `test_list_move_no_choose` — e2e |
| TestListChoiceOfSeveralFollowsItsItems | multi-choice follows items | 🔲 `test_list_choice_follows` — e2e |
| TestListTypeToChoose | type-to-choose selects | 🔲 `test_list_type_choose` — e2e |
| TestListTypeToChooseLeavesShortcuts | typing leaves shortcuts intact | 🔲 `test_type_choose_shortcuts` — e2e |
| TestListPageKeys | page keys move selection | 🔲 `test_list_page_keys` — e2e |
| TestAccessibilityOfListsChoosingSeveral | a11y reports multi-selection | 🔲 partial: platform/native/lui_a11y/test/lui_a11y_test.ml:test_checked_states → add `test_a11y_list_multi` — e2e |
| TestTableChoosesSeveral | table multi-select | 🔲 `test_table_multi_select` — e2e |
| TestSelectionOfAnotherKeyPanics | choosing foreign key panics | 🔲 `test_selection_wrong_key` — e2e |
| TestListTypeRightAfterAClick | typing after click works | 🔲 `test_type_after_click` — e2e |

### inset shadow (`ui/shadow_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestInsetShadow | inset shadow paints inside the edge | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_inset_shadow_op → add `test_inset_shadow_pixels` — lui_native |

### sidebar (`ui/sidebar_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestSidebar | collapsible sidebar behaves | 🔲 `test_sidebar` — e2e |

### style (`ui/style_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestGrid | grid template layout | platform/native/lui_layout/test/lui_layout_test.ml:test_grid_wraps |
| TestFlexOptions | flex direction/justify/align options | platform/native/lui_flex/test/lui_flex_test.ml:test_justify_center + test_flex_grow + test_wrap |
| TestBorderWidths | per-edge border widths paint | platform/native/lui_paint/test/lui_paint_test.ml:test_per_edge_borders |
| TestPaints | fills + gradients paint | platform/native/lui_paint/test/lui_paint_test.ml:test_fill_op + test_gradient + test_gradient_variants |
| TestTextDecorations | underline/strikethrough render | 🔲 `test_text_decorations` — lui_paint |
| TestTextOptions | text style options apply | 🔲 `test_text_options` — lui_paint |
| TestButtonLabelsAtIntrinsicWidth | buttons size to label | 🔲 `test_button_intrinsic_width` — e2e |
| TestInvisible | invisible element draws nothing | platform/native/lui_paint/test/lui_paint_test.ml:test_invisible |
| TestClipOneWay | clip affects children only | platform/native/lui_paint/test/lui_paint_test.ml:test_clip |
| TestScrollBoth | two-axis scroll | 🔲 `test_scroll_both` — e2e |
| TestScrollbarInsets | scrollbar reserves space | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_scrollbar → add `test_scrollbar_insets` — e2e |
| TestScrollContentShrinks | scrollable content shrinks to fit | 🔲 `test_scroll_content_shrinks` — e2e |
| TestEasingAndLoop | easings + looped animations | 🔲 `test_easings` — e2e |
| TestIconRotates | icon rotation renders | 🔲 `test_icon_rotates` — lui_paint |
| TestImageFitsAndGray | image fit modes + grayscale | 🔲 partial: platform/native/lui_image/test/lui_image_test.ml:test_fit → add `test_image_gray` — lui_image |
| TestMeasureAndDrawText | measured text paints correctly | platform/native/lui_text/test/lui_text_test.ml:test_measure_matches + test_rasterize_mask |
| TestDebugAndCursors | debug outlines + cursor styles | 🔲 `test_debug_cursors` — e2e |
| TestCursorStopsAtClickable | cursor changes on clickable | 🔲 `test_cursor_clickable` — e2e |
| TestThemeUnits | theme units resolve to px | 🔲 `test_theme_units` — lui_paint |
| TestReviewedEdges | edge-box value parsing | platform/native/lui_paint/test/lui_paint_test.ml:test_edges |

### SVG widgets (`ui/svg_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestIconTakesTheTextColorAndSize | icon inherits text color/size | 🔲 `test_icon_text_color` — lui_svg (new) |
| TestIconDrawsItsShapeOnce | icon shape drawn once | 🔲 `test_icon_draws_once` — lui_svg (new) |
| TestImageOfAnSVG | SVG renders as image | 🔲 `test_image_of_svg` — lui_svg (new) |
| TestPictureFollowsTheTextColor | SVG picture recolors with text | 🔲 `test_svg_picture_color` — lui_svg (new) |
| TestIconsInAccessibility | icons visible in a11y | 🔲 `test_svg_icons_a11y` — lui_svg (new) |
| TestPainterDrawsSVGs | painter can draw SVGs | 🔲 `test_painter_svg` — lui_svg (new) |
| TestParseSVGErrors | parse errors propagate | 🔲 `test_svg_parse_errors` — lui_svg (new) |

### table (`ui/table_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestTableSort | column sort works | 🔲 `test_table_sort` — e2e |
| TestTableResize | column resize works | 🔲 `test_table_resize` — e2e |
| TestTableReorder | column reorder works | 🔲 `test_table_reorder` — e2e |
| TestTableReorderFar | far reorder works | 🔲 `test_table_reorder_far` — e2e |
| TestTableScrollsSideways | horizontal scroll | 🔲 `test_table_scroll_sideways` — e2e |
| TestEditableTextInTable | editable cells edit | 🔲 `test_table_editable` — e2e |
| TestEditableText | editable text control | 🔲 `test_editable_text` — e2e |
| TestTableRoundRows | rounded row rendering | 🔲 `test_table_round_rows` — e2e |

### text buffer (`ui/text_buffer_test.go`, `ui/text_buffer_bench_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestTextBufferRandomEditsAndSnapshots | random edits + snapshots stay consistent | 🔲 `test_text_buffer_edits` — lui_text |
| TestTextBufferNativeRangesMalformedAndZero | malformed/zero ranges handled | 🔲 `test_text_buffer_ranges` — lui_text |
| TestTextBufferOwnsBoundedChunks | bounded chunk storage | 🔲 `test_text_buffer_chunks` — lui_text |
| TestTextBufferConcurrentSnapshots | concurrent snapshots safe | 🔲 `test_text_buffer_concurrent` — lui_text |
| TestTextBufferEditAllocationIsBounded (bench) | edit allocation bounded | ➖ n/a — benchmark |

### text input client (`ui/text_input_client_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestTextInputClientCompositionAndReplacement | composition + replacement ranges | 🔲 `test_tic_composition` — e2e |
| TestTextInputClientNativeEndBeforeCommit | native-end ordering before commit | 🔲 `test_tic_end_before_commit` — e2e |
| TestTextInputClientQueriesGeometryAndLifetime | geometry + lifetime queries | 🔲 `test_tic_geometry_lifetime` — e2e |
| TestTextInputClientSwappingAndTypedNil | client swap + typed nil | 🔲 `test_tic_swapping` — e2e |
| TestTextInputSurroundingUnicodeAndReversedSelection | surrounding text + reversed selection | 🔲 `test_tic_surrounding` — e2e |
| TestTextLayoutUTF16GraphemesAndBidiRanges | UTF16 grapheme + bidi ranges | 🔲 `test_tic_utf16_ranges` — lui_text |
| TestTextLayoutVisualCaretUTF16 | visual caret in UTF16 units | 🔲 `test_tic_visual_caret_utf16` — lui_text |

### textarea (`ui/textarea_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestBufferEdits | buffer edit fuzz stays consistent | 🔲 `test_textarea_buffer_edits` — e2e |
| TestBufferSetUTF8 | malformed UTF-8 input handled | 🔲 `test_textarea_set_utf8` — e2e |
| TestBufferWords | word boundaries correct | 🔲 `test_textarea_words` — e2e |
| TestBufferGraphemes | grapheme clusters correct | 🔲 `test_textarea_graphemes` — e2e |
| TestHeights | line heights after edits | 🔲 `test_textarea_heights` — e2e |
| TestTextAreaLaysOutAsWholeText | whole-text layout | 🔲 `test_textarea_layout_whole` — e2e |
| TestTextAreaUndo | undo/redo restores text | 🔲 `test_textarea_undo` — e2e |
| TestTextAreaScrolls | textarea scrolls | 🔲 `test_textarea_scrolls` — e2e |
| TestTextAreaSelectsAsWholeText | selection across whole text | 🔲 `test_textarea_select_whole` — e2e |
| TestTextAreaUndoAppChanges | undo covers app changes | 🔲 `test_textarea_undo_app` — e2e |
| TestTextAreaUndoAppLog | undo log matches app log | 🔲 `test_textarea_undo_log` — e2e |
| TestTextAreaSharesValue | value shared with model | 🔲 `test_textarea_shares_value` — e2e |
| TestTextAreaRevealsWrapped | caret reveals wrapped lines | 🔲 `test_textarea_reveals_wrapped` — e2e |
| TestTextAreaKeepsViewOnAppText | view keeps app text visible | 🔲 `test_textarea_keeps_view` — e2e |
| TestTextAreaShowsThroughPadding | padding does not hide text | 🔲 `test_textarea_padding` — e2e |
| TestTextAreaPassword | password mode masks text | 🔲 `test_textarea_password` — e2e |
| TestTextAreaInForm | textarea inside a form | 🔲 `test_textarea_in_form` — e2e |
| TestTextAreaLinesFollowWrappedText | line numbers follow wraps | 🔲 `test_textarea_lines_wrap` — e2e |
| TestTextSelection | text selection in textarea | 🔲 `test_textarea_selection` — e2e |
| TestPlaceholderWithFixedLineHeight | placeholder at fixed line height | 🔲 `test_textarea_placeholder_height` — e2e |
| TestInputTextAlign | text alignment options | 🔲 `test_input_text_align` — e2e |
| TestInputPasswordToggles | password visibility toggle | 🔲 `test_input_password_toggle` — e2e |
| TestInputPlaceholderStaysOnItsLine | placeholder stays on its line | 🔲 `test_input_placeholder_line` — e2e |
| TestInputShowsItsStartUnfocused | start shown when unfocused | 🔲 `test_input_start_unfocused` — e2e |
| TestTextRanges | text range queries | 🔲 `test_text_ranges` — e2e |
| TestTextRangesWhileComposing | ranges during composition | 🔲 `test_text_ranges_composing` — e2e |

### textbuffer input (`ui/textbuffer_input_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestBufferInputsEditComposeAndUndo | edit/compose/undo on buffer input | 🔲 `test_buffer_input_undo` — e2e |
| TestBufferAreaNativeQueriesAndLineEditing | native queries + line editing | 🔲 `test_buffer_area_queries` — e2e |
| TestBufferInputBidiReplacementAndExternalChange | bidi replace + external change | 🔲 `test_buffer_input_bidi` — e2e |
| TestBufferInputBindingSwapAndStringCompatibility | binding swap + string compat | 🔲 `test_buffer_input_swap` — e2e |

### text lines (`ui/textlines_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestTextLines | line count/top/at/rows queries | 🔲 partial: platform/native/lui_text/test/lui_text_test.ml:test_metrics → add `test_text_lines` — lui_text |
| TestTextLinesBeforeLayout | queries safe before layout | 🔲 `test_text_lines_before_layout` — lui_text |

### text selection (`ui/textselection_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestSelectableContainerMultiClick | multi-click extends selection | 🔲 `test_sel_multi_click` — e2e |
| TestSelectableContainerOrderAndOverlap | order + overlap of selections | 🔲 `test_sel_order_overlap` — e2e |
| TestSelectableContainerScroll | selection survives scroll | 🔲 `test_sel_scroll` — e2e |
| TestSelectableInlineParagraphRebuild | inline paragraph rebuild keeps selection | 🔲 `test_sel_inline_rebuild` — e2e |
| TestSelectableContainer | container selection | 🔲 `test_sel_container` — e2e |
| TestSelectableContainerKeyboard | keyboard selection | 🔲 `test_sel_keyboard` — e2e |
| TestSelectableContainerScopesAndControls | scopes + controls coexist | 🔲 `test_sel_scopes` — e2e |
| TestSelectableContainerInlineAndRebuild | inline + rebuild | 🔲 `test_sel_inline` — e2e |
| TestSelectableContainerChangingOtherText | changing other text keeps selection | 🔲 `test_sel_other_text` — e2e |
| TestSelectableContainerFocusAndDisable | focus + disable clear selection | 🔲 `test_sel_focus_disable` — e2e |
| TestSelectableTextContextMenu | selection context menu | 🔲 `test_sel_context_menu` — e2e |
| TestTextInputContextMenuEditItems | edit menu items act on selection | 🔲 `test_sel_edit_items` — e2e |
| TestSelectionColor | selection color renders | 🔲 `test_sel_color` — e2e |

### text style (`ui/textstyle_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestLetterSpacingAndFeatures | letter spacing + feature params reach layout | 🔲 `test_letter_spacing_features` — lui_text |

### theme (`ui/theme_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestSpacingScalesWidgets | spacing scale propagates to widgets | 🔲 `test_theme_spacing` — e2e |
| TestParseHex | hex color parsing | platform/native/lui_paint/test/lui_paint_test.ml:test_hex |
| TestInverseColors | light/dark inverse computed | 🔲 `test_theme_inverse` — lui_paint |
| TestInverseFillsTooltipsAndToasts | inverse fills on tooltips/toasts | 🔲 `test_inverse_fills` — e2e |

### toast (`ui/toast_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestToastViewportBase | toast positions in viewport | 🔲 `test_toast_viewport` — e2e |
| TestToastManager | manager queues toasts | 🔲 `test_toast_manager` — e2e |
| TestToastDescription | description text renders | 🔲 `test_toast_description` — e2e |
| TestToastExits | toast exits cleanly | 🔲 `test_toast_exits` — e2e |

### toggles / toolbar (`ui/toggle_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestFocusGroupIsOneTabStop | focus group is one tab stop | 🔲 `test_focus_group_tab` — e2e |
| TestFocusGroupLeavesKeysToWhatTakesThem | keys pass to consumers | 🔲 `test_focus_group_keys` — e2e |
| TestRadioGroupArrowsChoose | arrows choose radio option | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_radio → add `test_radio_arrows` — e2e |
| TestToggle | toggle flips state | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_switch + test_checkbox → add `test_toggle_behavior` — e2e |
| TestSegmented | segmented control selects | 🔲 `test_segmented` — e2e |
| TestTabsAreOneTabStop | tab strip is one tab stop | 🔲 `test_tabs_tab_stop` — e2e |
| TestToolbarOverflows | overflow moves items to menu | 🔲 `test_toolbar_overflow` — e2e |
| TestToolbarAccessibility | toolbar exposes a11y | 🔲 partial: platform/native/lui_a11y/test/lui_a11y_test.ml:test_state_flags → add `test_toolbar_a11y` — e2e |
| TestToolbarEntersAtItsFirst | toolbar focuses first item | 🔲 `test_toolbar_enter_first` — e2e |

### tooltip (`ui/tooltip_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestTooltipBase | tooltip shows on hover | 🔲 `test_tooltip_base` — e2e |
| TestTooltipFocus | tooltip on keyboard focus | 🔲 `test_tooltip_focus` — e2e |
| TestTooltipAnchored | tooltip anchored to element | 🔲 `test_tooltip_anchored` — e2e |
| TestTooltipInnermost | innermost tooltip wins | 🔲 `test_tooltip_innermost` — e2e |

### transitions (`ui/transition_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestTransitionMovesElements | elements animate position | 🔲 `test_transition_moves` — e2e |
| TestTransitionResizesAndLaysOutContent | resize transitions relayout | 🔲 `test_transition_resizes` — e2e |
| TestTransitionEntersAndExits | enter/exit transitions | 🔲 `test_transition_enter_exit` — e2e |
| TestTransitionFadesColors | color fades | 🔲 `test_transition_fades` — e2e |
| TestTransitionWithoutMotion | reduce-motion skips animation | 🔲 `test_transition_no_motion` — e2e |
| TestDuplicateKeys | duplicate keys handled | 🔲 `test_transition_dup_keys` — e2e |
| TestDividers | dividers transition | 🔲 `test_transition_dividers` — e2e |
| TestListDividers | list dividers transition | 🔲 `test_transition_list_dividers` — e2e |
| TestAttach | attach transitions with content | 🔲 `test_transition_attach` — e2e |
| TestTransitionResizesAList | list resizes transition | 🔲 `test_transition_list_resize` — e2e |

### misc app-level (`ui/ui_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestDemoRenders | demo app renders non-blank | 🔲 partial: platform/native/e2e/test/e2e_test.ml:test_boot_pipeline → add `test_demo_renders` — e2e |
| TestClickCounts | clicks increment the counter | platform/native/e2e/test/e2e_test.ml:test_press_add_remove_promote |
| TestTyping | typed text reaches input | platform/native/e2e/test/e2e_test.ml:test_text_changed |
| TestTextInputFollowsTheFocusAtOnce | text input takes focus immediately | 🔲 `test_input_follows_focus` — e2e |
| TestKeyOnAWidget | key dispatch to widget | 🔲 `test_key_on_widget` — e2e |
| TestTitleBar | window title bar | ➖ n/a — no window chrome |
| TestEmacsKeys | emacs-style editing keys | 🔲 `test_emacs_keys` — e2e |
| TestListScrollsAndSelects | list scrolls + selects together | 🔲 `test_list_scroll_select` — e2e |
| TestTabFocus | Tab moves focus + Enter activates | 🔲 `test_tab_focus` — e2e |
| TestAutoFocus | autofocus lands on open | 🔲 `test_auto_focus` — e2e |
| TestKeyboardScrolling | keys scroll under pointer / focused slider | 🔲 `test_keyboard_scrolling` — e2e |
| TestElementsGoneInARebuild | removed elements unbuild on rebuild | platform/native/e2e/test/e2e_test.ml:test_move_remove_drop + platform/native/lui_store/test/lui_store_test.ml:test_drop_subtree |
| TestRecycledStateIsFresh | recycled element state is fresh | 🔲 `test_recycled_state` — e2e |
| TestHoverWhilePressed | hover tracked while pressed | 🔲 `test_hover_while_pressed` — e2e |

### webview widget (`ui/webview_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestWebViewPlacement | webview lays out with siblings | ➖ n/a — no webview |
| TestWebViewHole | rounded webview clips to hole | ➖ n/a — same |
| TestWebViewOpacity | opacity applies to webview | ➖ n/a — same |
| TestWebViewTab | Tab through webview | ➖ n/a — same |
| TestWebViewClipped | webview clipped in scroll | ➖ n/a — same |
| TestWebViewNotOpaque | webview not treated opaque for under-drawing | ➖ n/a — same |
| TestPopoverLastPressDecides | last press decides popover outcome | 🔲 `test_popover_last_press` — e2e |

### wide color (`ui/widecolor_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestOklchInsideSRGBHasNoWideColor | in-sRGB oklch has no wide payload | 🔲 `test_oklch_srgb` — lui_paint |
| TestOklchOutsideSRGBKeepsWideColor | out-of-gamut keeps wide payload | 🔲 partial: platform/native/lui_gpu/test/lui_gpu_test.ml:test_wide → add `test_wide_color_value` — lui_paint |
| TestOklchOddInput | NaN/negative handled | 🔲 `test_oklch_odd_input` — lui_paint |
| TestMixWide | mixing wide color drops wide correctly | 🔲 `test_mix_wide` — lui_paint |
| TestBackgroundDrawsNearestSRGB | sRGB surface draws nearest color | 🔲 `test_wide_draws_nearest` — lui_paint |
| TestWideShadowStripesGradientAndText | wide color through shadow/stripes/gradient/text | 🔲 partial: platform/native/lui_gpu/test/lui_gpu_test.ml:test_wide → add `test_wide_paint_paths` — lui_paint |
| TestWideOnlyWhereItShows | wide dropped where it has no effect | 🔲 `test_wide_only_where_shows` — lui_paint |
| TestWideDecorationsDividersAndTextBackground | wide in decorations/dividers/text bg | 🔲 `test_wide_decorations` — lui_paint |
| TestThemeAccentTakesOklch | theme accent keeps wide | 🔲 `test_theme_accent_oklch` — lui_paint |
| TestPictureOfAWideColor | picture not redrawn for same-sRGB wide | 🔲 `test_picture_wide` — lui_svg (new) |
| TestWideFramesOnGPU | wide surfaces drive wide GPU frames | 🔲 partial: platform/native/lui_gpu/test/lui_gpu_test.ml:test_wide → add `test_wide_frames_gpu` — lui_gpu |
| TestEffectColor | EffectColor returns sRGB + wide pair | 🔲 partial: platform/native/lui_gpu/test/lui_gpu_test.ml:test_effect_backdrop → add `test_effect_color` — lui_gpu |

### more widgets (`ui/widgets_more_test.go`)

| test | asserts | covered by |
|---|---|---|
| TestTabs | tabs switch + Changed fires | 🔲 `test_tabs` — e2e |
| TestSplit | split pane divider drags | 🔲 `test_split` — e2e |
| TestSplitVertical | vertical split works | 🔲 `test_split_vertical` — e2e |
| TestNumberInput | number input steps | 🔲 `test_number_input` — e2e |
| TestToast | toast appears on action | 🔲 `test_toast` — e2e |
| TestTable | table renders + selects + opens | 🔲 `test_table` — e2e |
| TestTableRows | header/row sections render | 🔲 `test_table_rows` — e2e |
| TestTree | tree expand/collapse/select | 🔲 `test_tree` — e2e |
| TestDateInput | date input picks date | 🔲 `test_date_input` — e2e |
| TestDateInputWide | date input wide layout | 🔲 `test_date_input_wide` — e2e |
| TestProgressReverse | progress bar reverses | 🔲 partial: platform/native/lui_paint/test/lui_paint_test.ml:test_progress → add `test_progress_reverse` — lui_paint |
| TestTooltipHidesOnPress | tooltip hides on press | 🔲 `test_tooltip_hides_press` — e2e |

## Appendix A — our native test inventory (191 tests, 11 files)

### platform/native/e2e/test/e2e_test.ml (10)

| test | asserts |
|---|---|
| test_boot_pipeline | boot batch builds store: 12 nodes, roots/kinds, generation 1 |
| test_text_changed | text-change event updates model draft + field prop, marks dirty, emits glyph ops + summary |
| test_press_add_remove_promote | press adds item; remove promotes child; store + dirty reflect both |
| test_unsupported_event_rejected | value-change/press on text-field raise |
| test_echo_suppressed | echo event flushes without new generation |
| test_dispose | dispose empties the store |
| test_scene_ops | scene batch: node count, roots, scroll children, extension kind/id, op sequence |
| test_move_remove_drop | move reorders children, remove detaches to root; parents + dirty tracked |
| test_invalid_ops_ignored | ops on missing nodes ignored, nothing dirtied |
| test_host_flags_and_resize | repaint flag set/cleared; resize reallocates frame buffer + scene size |

### platform/native/test/lui_native_test.ml (12)

| test | asserts |
|---|---|
| test_atlas_alloc | alloc positions advance; oversized alloc fails |
| test_atlas_transient | transient zone top lowered then restored |
| test_atlas_changes | per-rect change list; generation mismatch reports full |
| test_atlas_grow | grow doubles width and bumps generation |
| test_atlas_repack | repack repositions all entries |
| test_fit_radii | corner radii scaled to fit the rect |
| test_corners_continuous | negative/continuous corners handled |
| test_inner_radii | inner radii inset correctly |
| test_sd_round_rect | rounded-rect SDF sign inside/outside/edge |
| test_gamma_ratios | coverage-correction gamma ratios finite |
| test_backdrop_of | backdrop rect covers reach, clamped to frame |
| test_blur_weight | gaussian blur weight: sigma0==1, decays |
| test_pipeline | style to fill-op pipeline picks right color |

### platform/native/lui_flex/test/lui_flex_test.ml (29)

| test | asserts |
|---|---|
| test_row | row lays children horizontally |
| test_column | column stacks children vertically |
| test_justify_center | justify-center packs children centrally |
| test_justify_space_between | space-between distributes |
| test_justify_space_evenly | space-evenly distributes |
| test_flex_grow | grow factor expands children |
| test_flex_shrink | shrink factor contracts children |
| test_min_max | min/max sizes clamp layout |
| test_wrap | wrap pushes children to next line |
| test_wrap_gap | gap between wrapped lines |
| test_column_gap | column gap applied |
| test_row_gap | row gap applied |
| test_absolute_offsets | absolute child offsets applied |
| test_absolute_trailing | trailing absolute offsets applied |
| test_absolute_ignored_in_flow | absolute child ignored in flow |
| test_nested_padding | padding nests correctly |
| test_deep_nesting | deeply nested flex resolves |
| test_percent_dims | percent dims resolve against parent |
| test_percent_against_inner | percent resolves against inner size |
| test_percent_margin | percent margins resolve |
| test_percent_flex_basis | percent flex basis resolves |
| test_auto_container | auto container sizes to content |
| test_auto_margin_main | auto margin on main axis |
| test_auto_margin_split | auto margins split space |
| test_align_stretch | align-stretch fills cross axis |
| test_align_center | align-center centers on cross axis |
| test_row_reverse | row-reverse order |
| test_measure_leaf | measure fn sizes leaf nodes |
| test_measure_is_leaf | measured nodes treated as leaves |

### platform/native/lui_gl/test/lui_gl_test.ml (7)

| test | asserts |
|---|---|
| test_pack_offsets | vertex attribute offsets/stride exact (11 attrs, 176 bytes) |
| test_pack_batches | batches packed with rect float data |
| test_pack_spans | batch spans + scissor rect per clip |
| test_clamp_scissor | scissor clamped to frame bounds |
| test_atlas_plan | atlas plan: Nothing / Upload / Recreate per change + gen |
| test_effect_source | compiled effect GLSL contains expected source |
| test_gl_render | GL output == CPU raster: same pixels, non-blank, red fill center |

### platform/native/lui_gpu/test/lui_gpu_test.ml (11)

| test | asserts |
|---|---|
| test_build | scene ops -> instanced batches incl. glyph + image batches + scissors |
| test_nested_clips | nested clips produce nested scissor batches |
| test_empty_clip_skips | empty clip drops its instances |
| test_clip_off_frame | off-frame clips intersect scissor correctly |
| test_holes | hole batches flagged and merged |
| test_effect_backdrop | effect batches carry backdrop area/down/radius |
| test_glyph_kinds | mask/color/clip glyph kinds emitted |
| test_gradient_glyphs | gradient text produces gradient glyph ops |
| test_wide | wide colors packed into instances |
| test_float32_packing | 44-float instance layout exact incl. f32 rounding |
| test_shader_source | shader source embedded in library |

### platform/native/lui_image/test/lui_image_test.ml (22)

| test | asserts |
|---|---|
| test_decode_rgba_png | RGBA PNG decodes per-pixel incl. alpha |
| test_decode_rgb_png | RGB PNG decodes opaque |
| test_decode_greya_png | gray+alpha PNG decodes |
| test_decode_pnm | P6/P5 PNM decode |
| test_decode_bmp | BMP decodes all 4 corners |
| test_decode_gif | GIF frames decode |
| test_decode_jpeg_unsupported | JPEG returns unsupported |
| test_decode_errors | empty/garbage/truncated input errors cleanly |
| test_scene_image | image ops carry premultiplied pixels |
| test_upload | atlas upload premultiplies + records gen/transient |
| test_upload_mask_atlas_rejected | bpp=1 atlas rejected for images |
| test_upload_grows | atlas grows on demand, bumps gen |
| test_upload_too_big | oversized upload errors |
| test_upload_lasting | lasting entries keep pixels |
| test_cache_decode | decode cache memoizes + tracks bytes |
| test_cache_atlas_entry | same image reuses atlas entry, no rewrite |
| test_cache_frame | transient re-uploads per frame; lasting untouched |
| test_cache_stale_gen | stale gen forces re-upload |
| test_cache_lru | LRU evicts oldest, keeps hot |
| test_fit | Fill/Natural/Contain/Cover fit rects |

### platform/native/lui_paint/test/lui_paint_test.ml (38)

| test | asserts |
|---|---|
| test_hex | #rgb/#rrggbb/#rrggbbaa parse; unknown name -> None |
| test_edges | 1/2/3/4-value edge parsing |
| test_fill_op | fill op carries color + radius |
| test_children_order | children paint in order |
| test_invisible | invisible node emits no ops |
| test_clip | clip op clips children |
| test_gradient | linear gradient direction + colors |
| test_gradient_variants | oklab/stripes/45deg variants |
| test_dashed_border | dashed border flag set |
| test_per_edge_borders | per-edge widths |
| test_per_edge_border_colors | per-edge colors |
| test_shadow_parse | shadow spec: dx/dy/blur/alpha/outset/inset/spread |
| test_shadow_op | shadow op rect/blur/color |
| test_inset_shadow_op | inset shadow deflates rect |
| test_state_background | hover state background wins |
| test_state_precedence | pressed > hover precedence |
| test_selected_shadow | selected+hover shadow composition |
| test_disabled_opacity | disabled halves opacity |
| test_opacity_multiply | opacity multiplies down the tree |
| test_zindex | z-index reorders paint |
| test_display_contents | display:contents paints child only |
| test_position_absolute | absolute position applied |
| test_position_relative | relative offset applied |
| test_popup_xy | popup positioned at xy |
| test_layout_override | layout override rect honored |
| test_divider | 1px divider at right y |
| test_spacer | spacer emits no ops |
| test_progress | progress track/fill fractions |
| test_checkbox | checked checkbox: accent fill + check glyph |
| test_checkbox_unchecked | unchecked: bordered hollow box |
| test_switch | switch track accent + thumb right-aligned |
| test_radio | radio outer accent + inner dot |
| test_spinner | spinner edges on three arcs |
| test_slider | slider track/fill/thumb position |
| test_scrollbar | scrollbar thumb size + right edge |
| test_extension | unknown extension emits no ops |
| test_coverage_table | every prop classified Painted/Host/Unmapped |

### platform/native/lui_store/test/lui_store_test.ml (10)

| test | asserts |
|---|---|
| test_create_and_insert | insert builds tree + preorder |
| test_insert_order | middle insert keeps order |
| test_move_child | reorder within parent |
| test_move_across_parents | reparent updates both parents |
| test_drop_subtree | drop removes subtree + marks dirty |
| test_props | prop set/remove |
| test_extension | extension kind/id + prop cleanup |
| test_dirty | dirty set drains once |
| test_root_ids | root listing |
| test_ops_on_missing_are_ignored | ops on missing nodes ignored |

### platform/native/lui_text/test/lui_text_test.ml (24)

| test | asserts |
|---|---|
| test_metrics | font metrics: size/ascent/descent/leading/line-height |
| test_create_named | named font resolves with size + family |
| test_create_missing_family | missing family still produces a font |
| test_create_same_args_same_font | identical args share the font |
| test_weight_changes_glyphs | bold produces different bitmaps |
| test_italic | italic face resolves |
| test_monospace | monospace face resolves |
| test_shape_ascii | shaping: line range, runs, glyph count, advance, cluster, width |
| test_shape_wrap | shaped lines respect wrap width |
| test_measure_matches | measured width matches layout |
| test_newlines | newlines split lines |
| test_cjk | CJK shapes |
| test_mixed_runs | mixed-script runs shape |
| test_rtl_paragraph | RTL paragraph orders runs correctly |
| test_emoji_color_glyph | emoji -> color bitmap glyph |
| test_fallback_font | missing glyphs use fallback font |
| test_rasterize_mask | glyph rasterizes alpha mask |
| test_rasterize_determinism | rasterization deterministic |
| test_rasterize_subpixel | subpixel offsets rasterize |
| test_rasterize_scale | scaled rasterization |
| test_rasterize_invalid | invalid glyph handled |
| test_subpixel_positions | positions quantized to subpixel grid |
| test_baseline | baseline offset correct |
| test_empty | empty string shapes to empty |
| test_run_font_matches | shaped runs use requested font |

### platform/native/lui_text_pango/test/lui_text_pango_test.ml (24)

Same 24 test names as `lui_text_test.ml`, run against the pango backend —
par proves both text stacks agree on metrics, shaping, RTL, emoji,
fallback and rasterization semantics.

### platform/native/lui_layout/test/lui_layout_test.ml (9)

| test | asserts |
|---|---|
| test_column_padding_gap | column placement honors padding + gap |
| test_grid_wraps | grid cells wrap into tracks |
| test_absolute_inset | absolute child inset placed |
| test_text_measured | text node measured for size |
| test_percent_size | percent sizes resolve |
| test_nested_column_in_row | nested column inside row |
| test_run_placements | placement runs; p_override cleared |
| test_display_none_absent | display:none yields no rect |
| test_rebuild_after_mutation | layout rebuild tracks mutation |

### platform/native/spike/test/test_spike_render.ml (4)

| test | asserts |
|---|---|
| test_coverage | coverage ramp across edge distances |
| test_deterministic | render checksum deterministic |
| test_sdf_fill | SDF fill produces expected pixels |
| test_blit | glyph blit lands in frame |
## Coverage ratio by area

| area | ref tests | n/a | covered | gaps | ratio |
|---|---|---|---|---|---|
| internal/accelerator | 4 | 0 | 0 | 4 | 0% |
| internal/darwin | 5 | 5 | 0 | 0 | n/a |
| internal/e2e | 88 | 64 | 4 | 20 | 17% |
| internal/gamut | 9 | 0 | 0 | 9 | 0% |
| internal/gpu | 14 | 5 | 5 | 4 | 56% |
| internal/linux | 1 | 1 | 0 | 0 | n/a |
| internal/raster | 10 | 1 | 0 | 9 | 0% |
| internal/scene | 5 | 0 | 3 | 2 | 60% |
| internal/svg | 23 | 0 | 0 | 23 | 0% |
| internal/text | 44 | 0 | 8 | 36 | 18% |
| codegen / migration / vet tooling (`internal/tsgen`, `internal/uimigrate`, `internal/uivet`) | 14 | 14 | 0 | 0 | n/a |
| internal/update | 10 | 10 | 0 | 0 | n/a |
| internal/windows | 2 | 2 | 0 | 0 | n/a |
| ui/access_test.go | 7 | 0 | 2 | 5 | 29% |
| action queries and pending edits (`ui/action_queries_test.go`, `ui/api_bench_test.go`, `ui/bench_test.go`) | 5 | 2 | 0 | 3 | 0% |
| ui/base_test.go | 11 | 0 | 0 | 11 | 0% |
| ui/bitmap_test.go | 5 | 0 | 0 | 5 | 0% |
| collapsible / combobox (`ui/collapsible_test.go`, `ui/combobox_test.go`) | 11 | 0 | 0 | 11 | 0% |
| data drag / file drop (`ui/data_drag_test.go`, `ui/drop_test.go`, `ui/dragdrop_test.go`) | 9 | 0 | 0 | 9 | 0% |
| ui/datetime_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/editor_input_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/feedback_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/form_test.go | 3 | 0 | 0 | 3 | 0% |
| ui/frame_test.go | 25 | 0 | 0 | 25 | 0% |
| ui/framestats_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/gpu_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/gridview_test.go | 3 | 0 | 0 | 3 | 0% |
| ui/indicators_test.go | 8 | 0 | 0 | 8 | 0% |
| ui/inline_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/inspector_test.go | 8 | 8 | 0 | 0 | n/a |
| ui/layout_grow_test.go | 1 | 0 | 1 | 0 | 100% |
| ui/lifetime_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/list_sideways_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/list_test.go | 36 | 0 | 0 | 36 | 0% |
| ui/memory_test.go | 6 | 0 | 0 | 6 | 0% |
| ui/menu_test.go | 8 | 0 | 0 | 8 | 0% |
| modifiers / outline (`ui/modifiers_test.go`, `ui/outline_test.go`) | 5 | 0 | 0 | 5 | 0% |
| paint and repaint (`ui/paint_test.go`, `ui/repaint_test.go`) | 9 | 0 | 0 | 9 | 0% |
| paste / preferences (`ui/paste_test.go`, `ui/preferences_test.go`) | 5 | 0 | 0 | 5 | 0% |
| ui/primitives_test.go | 19 | 0 | 0 | 19 | 0% |
| ui/richtext_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/router_test.go | 10 | 10 | 0 | 0 | n/a |
| ui/scope_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/scroll_test.go | 8 | 0 | 0 | 8 | 0% |
| selection (`ui/select_test.go`, `ui/selection_test.go`, `ui/selection_press_test.go`) | 15 | 0 | 0 | 15 | 0% |
| ui/shadow_test.go | 1 | 0 | 0 | 1 | 0% |
| ui/sidebar_test.go | 1 | 0 | 0 | 1 | 0% |
| ui/style_test.go | 20 | 0 | 8 | 12 | 40% |
| ui/svg_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/table_test.go | 8 | 0 | 0 | 8 | 0% |
| text buffer (`ui/text_buffer_test.go`, `ui/text_buffer_bench_test.go`) | 5 | 1 | 0 | 4 | 0% |
| ui/text_input_client_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/textarea_test.go | 26 | 0 | 0 | 26 | 0% |
| ui/textbuffer_input_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/textlines_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/textselection_test.go | 13 | 0 | 0 | 13 | 0% |
| ui/textstyle_test.go | 1 | 0 | 0 | 1 | 0% |
| ui/theme_test.go | 4 | 0 | 1 | 3 | 25% |
| ui/toast_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/toggle_test.go | 9 | 0 | 0 | 9 | 0% |
| ui/tooltip_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/transition_test.go | 10 | 0 | 0 | 10 | 0% |
| ui/ui_test.go | 14 | 1 | 3 | 10 | 23% |
| ui/webview_test.go | 7 | 6 | 0 | 1 | 0% |
| ui/widecolor_test.go | 12 | 0 | 0 | 12 | 0% |
| ui/widgets_more_test.go | 12 | 0 | 0 | 12 | 0% |
| platform/native/e2e/test/e2e_test.ml (10) | 0 | 0 | 0 | 0 | n/a |
| platform/native/test/lui_native_test.ml (12) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_flex/test/lui_flex_test.ml (29) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_gl/test/lui_gl_test.ml (7) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_gpu/test/lui_gpu_test.ml (11) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_image/test/lui_image_test.ml (22) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_paint/test/lui_paint_test.ml (38) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_store/test/lui_store_test.ml (10) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_text/test/lui_text_test.ml (24) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_text_pango/test/lui_text_pango_test.ml (24) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_layout/test/lui_layout_test.ml (9) | 0 | 0 | 0 | 0 | n/a |
| platform/native/spike/test/test_spike_render.ml (4) | 0 | 0 | 0 | 0 | n/a |
| **total** | 660 | 130 | 35 | 495 | **7%** |

Ratios count rows with a `path:test_name` citation against non-n/a rows;
partially-covered rows count as gaps until their suggested test lands.
## Appendix A — our native test inventory (191 tests, 11 files)

### platform/native/e2e/test/e2e_test.ml (10)

| test | asserts |
|---|---|
| test_boot_pipeline | boot batch builds store: 12 nodes, roots/kinds, generation 1 |
| test_text_changed | text-change event updates model draft + field prop, marks dirty, emits glyph ops + summary |
| test_press_add_remove_promote | press adds item; remove promotes child; store + dirty reflect both |
| test_unsupported_event_rejected | value-change/press on text-field raise |
| test_echo_suppressed | echo event flushes without new generation |
| test_dispose | dispose empties the store |
| test_scene_ops | scene batch: node count, roots, scroll children, extension kind/id, op sequence |
| test_move_remove_drop | move reorders children, remove detaches to root; parents + dirty tracked |
| test_invalid_ops_ignored | ops on missing nodes ignored, nothing dirtied |
| test_host_flags_and_resize | repaint flag set/cleared; resize reallocates frame buffer + scene size |

### platform/native/test/lui_native_test.ml (12)

| test | asserts |
|---|---|
| test_atlas_alloc | alloc positions advance; oversized alloc fails |
| test_atlas_transient | transient zone top lowered then restored |
| test_atlas_changes | per-rect change list; generation mismatch reports full |
| test_atlas_grow | grow doubles width and bumps generation |
| test_atlas_repack | repack repositions all entries |
| test_fit_radii | corner radii scaled to fit the rect |
| test_corners_continuous | negative/continuous corners handled |
| test_inner_radii | inner radii inset correctly |
| test_sd_round_rect | rounded-rect SDF sign inside/outside/edge |
| test_gamma_ratios | coverage-correction gamma ratios finite |
| test_backdrop_of | backdrop rect covers reach, clamped to frame |
| test_blur_weight | gaussian blur weight: sigma0==1, decays |
| test_pipeline | style to fill-op pipeline picks right color |

### platform/native/lui_flex/test/lui_flex_test.ml (29)

| test | asserts |
|---|---|
| test_row | row lays children horizontally |
| test_column | column stacks children vertically |
| test_justify_center | justify-center packs children centrally |
| test_justify_space_between | space-between distributes |
| test_justify_space_evenly | space-evenly distributes |
| test_flex_grow | grow factor expands children |
| test_flex_shrink | shrink factor contracts children |
| test_min_max | min/max sizes clamp layout |
| test_wrap | wrap pushes children to next line |
| test_wrap_gap | gap between wrapped lines |
| test_column_gap | column gap applied |
| test_row_gap | row gap applied |
| test_absolute_offsets | absolute child offsets applied |
| test_absolute_trailing | trailing absolute offsets applied |
| test_absolute_ignored_in_flow | absolute child ignored in flow |
| test_nested_padding | padding nests correctly |
| test_deep_nesting | deeply nested flex resolves |
| test_percent_dims | percent dims resolve against parent |
| test_percent_against_inner | percent resolves against inner size |
| test_percent_margin | percent margins resolve |
| test_percent_flex_basis | percent flex basis resolves |
| test_auto_container | auto container sizes to content |
| test_auto_margin_main | auto margin on main axis |
| test_auto_margin_split | auto margins split space |
| test_align_stretch | align-stretch fills cross axis |
| test_align_center | align-center centers on cross axis |
| test_row_reverse | row-reverse order |
| test_measure_leaf | measure fn sizes leaf nodes |
| test_measure_is_leaf | measured nodes treated as leaves |

### platform/native/lui_gl/test/lui_gl_test.ml (7)

| test | asserts |
|---|---|
| test_pack_offsets | vertex attribute offsets/stride exact (11 attrs, 176 bytes) |
| test_pack_batches | batches packed with rect float data |
| test_pack_spans | batch spans + scissor rect per clip |
| test_clamp_scissor | scissor clamped to frame bounds |
| test_atlas_plan | atlas plan: Nothing / Upload / Recreate per change + gen |
| test_effect_source | compiled effect GLSL contains expected source |
| test_gl_render | GL output == CPU raster: same pixels, non-blank, red fill center |

### platform/native/lui_gpu/test/lui_gpu_test.ml (11)

| test | asserts |
|---|---|
| test_build | scene ops -> instanced batches incl. glyph + image batches + scissors |
| test_nested_clips | nested clips produce nested scissor batches |
| test_empty_clip_skips | empty clip drops its instances |
| test_clip_off_frame | off-frame clips intersect scissor correctly |
| test_holes | hole batches flagged and merged |
| test_effect_backdrop | effect batches carry backdrop area/down/radius |
| test_glyph_kinds | mask/color/clip glyph kinds emitted |
| test_gradient_glyphs | gradient text produces gradient glyph ops |
| test_wide | wide colors packed into instances |
| test_float32_packing | 44-float instance layout exact incl. f32 rounding |
| test_shader_source | shader source embedded in library |

### platform/native/lui_image/test/lui_image_test.ml (22)

| test | asserts |
|---|---|
| test_decode_rgba_png | RGBA PNG decodes per-pixel incl. alpha |
| test_decode_rgb_png | RGB PNG decodes opaque |
| test_decode_greya_png | gray+alpha PNG decodes |
| test_decode_pnm | P6/P5 PNM decode |
| test_decode_bmp | BMP decodes all 4 corners |
| test_decode_gif | GIF frames decode |
| test_decode_jpeg_unsupported | JPEG returns unsupported |
| test_decode_errors | empty/garbage/truncated input errors cleanly |
| test_scene_image | image ops carry premultiplied pixels |
| test_upload | atlas upload premultiplies + records gen/transient |
| test_upload_mask_atlas_rejected | bpp=1 atlas rejected for images |
| test_upload_grows | atlas grows on demand, bumps gen |
| test_upload_too_big | oversized upload errors |
| test_upload_lasting | lasting entries keep pixels |
| test_cache_decode | decode cache memoizes + tracks bytes |
| test_cache_atlas_entry | same image reuses atlas entry, no rewrite |
| test_cache_frame | transient re-uploads per frame; lasting untouched |
| test_cache_stale_gen | stale gen forces re-upload |
| test_cache_lru | LRU evicts oldest, keeps hot |
| test_fit | Fill/Natural/Contain/Cover fit rects |

### platform/native/lui_paint/test/lui_paint_test.ml (38)

| test | asserts |
|---|---|
| test_hex | #rgb/#rrggbb/#rrggbbaa parse; unknown name -> None |
| test_edges | 1/2/3/4-value edge parsing |
| test_fill_op | fill op carries color + radius |
| test_children_order | children paint in order |
| test_invisible | invisible node emits no ops |
| test_clip | clip op clips children |
| test_gradient | linear gradient direction + colors |
| test_gradient_variants | oklab/stripes/45deg variants |
| test_dashed_border | dashed border flag set |
| test_per_edge_borders | per-edge widths |
| test_per_edge_border_colors | per-edge colors |
| test_shadow_parse | shadow spec: dx/dy/blur/alpha/outset/inset/spread |
| test_shadow_op | shadow op rect/blur/color |
| test_inset_shadow_op | inset shadow deflates rect |
| test_state_background | hover state background wins |
| test_state_precedence | pressed > hover precedence |
| test_selected_shadow | selected+hover shadow composition |
| test_disabled_opacity | disabled halves opacity |
| test_opacity_multiply | opacity multiplies down the tree |
| test_zindex | z-index reorders paint |
| test_display_contents | display:contents paints child only |
| test_position_absolute | absolute position applied |
| test_position_relative | relative offset applied |
| test_popup_xy | popup positioned at xy |
| test_layout_override | layout override rect honored |
| test_divider | 1px divider at right y |
| test_spacer | spacer emits no ops |
| test_progress | progress track/fill fractions |
| test_checkbox | checked checkbox: accent fill + check glyph |
| test_checkbox_unchecked | unchecked: bordered hollow box |
| test_switch | switch track accent + thumb right-aligned |
| test_radio | radio outer accent + inner dot |
| test_spinner | spinner edges on three arcs |
| test_slider | slider track/fill/thumb position |
| test_scrollbar | scrollbar thumb size + right edge |
| test_extension | unknown extension emits no ops |
| test_coverage_table | every prop classified Painted/Host/Unmapped |

### platform/native/lui_store/test/lui_store_test.ml (10)

| test | asserts |
|---|---|
| test_create_and_insert | insert builds tree + preorder |
| test_insert_order | middle insert keeps order |
| test_move_child | reorder within parent |
| test_move_across_parents | reparent updates both parents |
| test_drop_subtree | drop removes subtree + marks dirty |
| test_props | prop set/remove |
| test_extension | extension kind/id + prop cleanup |
| test_dirty | dirty set drains once |
| test_root_ids | root listing |
| test_ops_on_missing_are_ignored | ops on missing nodes ignored |

### platform/native/lui_text/test/lui_text_test.ml (24)

| test | asserts |
|---|---|
| test_metrics | font metrics: size/ascent/descent/leading/line-height |
| test_create_named | named font resolves with size + family |
| test_create_missing_family | missing family still produces a font |
| test_create_same_args_same_font | identical args share the font |
| test_weight_changes_glyphs | bold produces different bitmaps |
| test_italic | italic face resolves |
| test_monospace | monospace face resolves |
| test_shape_ascii | shaping: line range, runs, glyph count, advance, cluster, width |
| test_shape_wrap | shaped lines respect wrap width |
| test_measure_matches | measured width matches layout |
| test_newlines | newlines split lines |
| test_cjk | CJK shapes |
| test_mixed_runs | mixed-script runs shape |
| test_rtl_paragraph | RTL paragraph orders runs correctly |
| test_emoji_color_glyph | emoji -> color bitmap glyph |
| test_fallback_font | missing glyphs use fallback font |
| test_rasterize_mask | glyph rasterizes alpha mask |
| test_rasterize_determinism | rasterization deterministic |
| test_rasterize_subpixel | subpixel offsets rasterize |
| test_rasterize_scale | scaled rasterization |
| test_rasterize_invalid | invalid glyph handled |
| test_subpixel_positions | positions quantized to subpixel grid |
| test_baseline | baseline offset correct |
| test_empty | empty string shapes to empty |
| test_run_font_matches | shaped runs use requested font |

### platform/native/lui_text_pango/test/lui_text_pango_test.ml (24)

Same 24 test names as `lui_text_test.ml`, run against the pango backend —
par proves both text stacks agree on metrics, shaping, RTL, emoji,
fallback and rasterization semantics.

### platform/native/lui_layout/test/lui_layout_test.ml (9)

| test | asserts |
|---|---|
| test_column_padding_gap | column placement honors padding + gap |
| test_grid_wraps | grid cells wrap into tracks |
| test_absolute_inset | absolute child inset placed |
| test_text_measured | text node measured for size |
| test_percent_size | percent sizes resolve |
| test_nested_column_in_row | nested column inside row |
| test_run_placements | placement runs; p_override cleared |
| test_display_none_absent | display:none yields no rect |
| test_rebuild_after_mutation | layout rebuild tracks mutation |

### platform/native/spike/test/test_spike_render.ml (4)

| test | asserts |
|---|---|
| test_coverage | coverage ramp across edge distances |
| test_deterministic | render checksum deterministic |
| test_sdf_fill | SDF fill produces expected pixels |
| test_blit | glyph blit lands in frame |
## Coverage ratio by area

| area | ref tests | n/a | covered | gaps | ratio |
|---|---|---|---|---|---|
| internal/accelerator | 4 | 0 | 0 | 4 | 0% |
| internal/darwin | 5 | 5 | 0 | 0 | n/a |
| internal/e2e | 88 | 64 | 4 | 20 | 17% |
| internal/gamut | 9 | 0 | 0 | 9 | 0% |
| internal/gpu | 14 | 5 | 5 | 4 | 56% |
| internal/linux | 1 | 1 | 0 | 0 | n/a |
| internal/raster | 10 | 1 | 0 | 9 | 0% |
| internal/scene | 5 | 0 | 3 | 2 | 60% |
| internal/svg | 23 | 0 | 0 | 23 | 0% |
| internal/text | 44 | 0 | 8 | 36 | 18% |
| codegen / migration / vet tooling (`internal/tsgen`, `internal/uimigrate`, `internal/uivet`) | 14 | 14 | 0 | 0 | n/a |
| internal/update | 10 | 10 | 0 | 0 | n/a |
| internal/windows | 2 | 2 | 0 | 0 | n/a |
| ui/access_test.go | 7 | 0 | 2 | 5 | 29% |
| action queries and pending edits (`ui/action_queries_test.go`, `ui/api_bench_test.go`, `ui/bench_test.go`) | 5 | 2 | 0 | 3 | 0% |
| ui/base_test.go | 11 | 0 | 0 | 11 | 0% |
| ui/bitmap_test.go | 5 | 0 | 0 | 5 | 0% |
| collapsible / combobox (`ui/collapsible_test.go`, `ui/combobox_test.go`) | 11 | 0 | 0 | 11 | 0% |
| data drag / file drop (`ui/data_drag_test.go`, `ui/drop_test.go`, `ui/dragdrop_test.go`) | 9 | 0 | 0 | 9 | 0% |
| ui/datetime_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/editor_input_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/feedback_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/form_test.go | 3 | 0 | 0 | 3 | 0% |
| ui/frame_test.go | 25 | 0 | 0 | 25 | 0% |
| ui/framestats_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/gpu_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/gridview_test.go | 3 | 0 | 0 | 3 | 0% |
| ui/indicators_test.go | 8 | 0 | 0 | 8 | 0% |
| ui/inline_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/inspector_test.go | 8 | 8 | 0 | 0 | n/a |
| ui/layout_grow_test.go | 1 | 0 | 1 | 0 | 100% |
| ui/lifetime_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/list_sideways_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/list_test.go | 36 | 0 | 0 | 36 | 0% |
| ui/memory_test.go | 6 | 0 | 0 | 6 | 0% |
| ui/menu_test.go | 8 | 0 | 0 | 8 | 0% |
| modifiers / outline (`ui/modifiers_test.go`, `ui/outline_test.go`) | 5 | 0 | 0 | 5 | 0% |
| paint and repaint (`ui/paint_test.go`, `ui/repaint_test.go`) | 9 | 0 | 0 | 9 | 0% |
| paste / preferences (`ui/paste_test.go`, `ui/preferences_test.go`) | 5 | 0 | 0 | 5 | 0% |
| ui/primitives_test.go | 19 | 0 | 0 | 19 | 0% |
| ui/richtext_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/router_test.go | 10 | 10 | 0 | 0 | n/a |
| ui/scope_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/scroll_test.go | 8 | 0 | 0 | 8 | 0% |
| selection (`ui/select_test.go`, `ui/selection_test.go`, `ui/selection_press_test.go`) | 15 | 0 | 0 | 15 | 0% |
| ui/shadow_test.go | 1 | 0 | 0 | 1 | 0% |
| ui/sidebar_test.go | 1 | 0 | 0 | 1 | 0% |
| ui/style_test.go | 20 | 0 | 7 | 13 | 35% |
| ui/svg_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/table_test.go | 8 | 0 | 0 | 8 | 0% |
| text buffer (`ui/text_buffer_test.go`, `ui/text_buffer_bench_test.go`) | 5 | 1 | 0 | 4 | 0% |
| ui/text_input_client_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/textarea_test.go | 26 | 0 | 0 | 26 | 0% |
| ui/textbuffer_input_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/textlines_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/textselection_test.go | 13 | 0 | 0 | 13 | 0% |
| ui/textstyle_test.go | 1 | 0 | 0 | 1 | 0% |
| ui/theme_test.go | 4 | 0 | 1 | 3 | 25% |
| ui/toast_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/toggle_test.go | 9 | 0 | 0 | 9 | 0% |
| ui/tooltip_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/transition_test.go | 10 | 0 | 0 | 10 | 0% |
| ui/ui_test.go | 14 | 1 | 3 | 10 | 23% |
| ui/webview_test.go | 7 | 6 | 0 | 1 | 0% |
| ui/widecolor_test.go | 12 | 0 | 0 | 12 | 0% |
| ui/widgets_more_test.go | 12 | 0 | 0 | 12 | 0% |
| platform/native/e2e/test/e2e_test.ml (10) | 0 | 0 | 0 | 0 | n/a |
| platform/native/test/lui_native_test.ml (12) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_flex/test/lui_flex_test.ml (29) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_gl/test/lui_gl_test.ml (7) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_gpu/test/lui_gpu_test.ml (11) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_image/test/lui_image_test.ml (22) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_paint/test/lui_paint_test.ml (38) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_store/test/lui_store_test.ml (10) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_text/test/lui_text_test.ml (24) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_text_pango/test/lui_text_pango_test.ml (24) | 0 | 0 | 0 | 0 | n/a |
| platform/native/spike/test/test_spike_render.ml (4) | 0 | 0 | 0 | 0 | n/a |
| **total** | 660 | 130 | 34 | 496 | **6%** |

Ratios count rows with a `path:test_name` citation against non-n/a rows;
partially-covered rows count as gaps until their suggested test lands.
## Appendix A — our native test inventory (217 tests, 13 files)

### platform/native/e2e/test/e2e_test.ml (10)

| test | asserts |
|---|---|
| test_boot_pipeline | boot batch builds store: 12 nodes, roots/kinds, generation 1 |
| test_text_changed | text-change event updates model draft + field prop, marks dirty, emits glyph ops + summary |
| test_press_add_remove_promote | press adds item; remove promotes child; store + dirty reflect both |
| test_unsupported_event_rejected | value-change/press on text-field raise |
| test_echo_suppressed | echo event flushes without new generation |
| test_dispose | dispose empties the store |
| test_scene_ops | scene batch: node count, roots, scroll children, extension kind/id, op sequence |
| test_move_remove_drop | move reorders children, remove detaches to root; parents + dirty tracked |
| test_invalid_ops_ignored | ops on missing nodes ignored, nothing dirtied |
| test_host_flags_and_resize | repaint flag set/cleared; resize reallocates frame buffer + scene size |

### platform/native/test/lui_native_test.ml (12)

| test | asserts |
|---|---|
| test_atlas_alloc | alloc positions advance; oversized alloc fails |
| test_atlas_transient | transient zone top lowered then restored |
| test_atlas_changes | per-rect change list; generation mismatch reports full |
| test_atlas_grow | grow doubles width and bumps generation |
| test_atlas_repack | repack repositions all entries |
| test_fit_radii | corner radii scaled to fit the rect |
| test_corners_continuous | negative/continuous corners handled |
| test_inner_radii | inner radii inset correctly |
| test_sd_round_rect | rounded-rect SDF sign inside/outside/edge |
| test_gamma_ratios | coverage-correction gamma ratios finite |
| test_backdrop_of | backdrop rect covers reach, clamped to frame |
| test_blur_weight | gaussian blur weight: sigma0==1, decays |
| test_pipeline | style to fill-op pipeline picks right color |

### platform/native/lui_flex/test/lui_flex_test.ml (29)

| test | asserts |
|---|---|
| test_row | row lays children horizontally |
| test_column | column stacks children vertically |
| test_justify_center | justify-center packs children centrally |
| test_justify_space_between | space-between distributes |
| test_justify_space_evenly | space-evenly distributes |
| test_flex_grow | grow factor expands children |
| test_flex_shrink | shrink factor contracts children |
| test_min_max | min/max sizes clamp layout |
| test_wrap | wrap pushes children to next line |
| test_wrap_gap | gap between wrapped lines |
| test_column_gap | column gap applied |
| test_row_gap | row gap applied |
| test_absolute_offsets | absolute child offsets applied |
| test_absolute_trailing | trailing absolute offsets applied |
| test_absolute_ignored_in_flow | absolute child ignored in flow |
| test_nested_padding | padding nests correctly |
| test_deep_nesting | deeply nested flex resolves |
| test_percent_dims | percent dims resolve against parent |
| test_percent_against_inner | percent resolves against inner size |
| test_percent_margin | percent margins resolve |
| test_percent_flex_basis | percent flex basis resolves |
| test_auto_container | auto container sizes to content |
| test_auto_margin_main | auto margin on main axis |
| test_auto_margin_split | auto margins split space |
| test_align_stretch | align-stretch fills cross axis |
| test_align_center | align-center centers on cross axis |
| test_row_reverse | row-reverse order |
| test_measure_leaf | measure fn sizes leaf nodes |
| test_measure_is_leaf | measured nodes treated as leaves |

### platform/native/lui_gl/test/lui_gl_test.ml (7)

| test | asserts |
|---|---|
| test_pack_offsets | vertex attribute offsets/stride exact (11 attrs, 176 bytes) |
| test_pack_batches | batches packed with rect float data |
| test_pack_spans | batch spans + scissor rect per clip |
| test_clamp_scissor | scissor clamped to frame bounds |
| test_atlas_plan | atlas plan: Nothing / Upload / Recreate per change + gen |
| test_effect_source | compiled effect GLSL contains expected source |
| test_gl_render | GL output == CPU raster: same pixels, non-blank, red fill center |

### platform/native/lui_gpu/test/lui_gpu_test.ml (11)

| test | asserts |
|---|---|
| test_build | scene ops -> instanced batches incl. glyph + image batches + scissors |
| test_nested_clips | nested clips produce nested scissor batches |
| test_empty_clip_skips | empty clip drops its instances |
| test_clip_off_frame | off-frame clips intersect scissor correctly |
| test_holes | hole batches flagged and merged |
| test_effect_backdrop | effect batches carry backdrop area/down/radius |
| test_glyph_kinds | mask/color/clip glyph kinds emitted |
| test_gradient_glyphs | gradient text produces gradient glyph ops |
| test_wide | wide colors packed into instances |
| test_float32_packing | 44-float instance layout exact incl. f32 rounding |
| test_shader_source | shader source embedded in library |

### platform/native/lui_image/test/lui_image_test.ml (20)

| test | asserts |
|---|---|
| test_decode_rgba_png | RGBA PNG decodes per-pixel incl. alpha |
| test_decode_rgb_png | RGB PNG decodes opaque |
| test_decode_greya_png | gray+alpha PNG decodes |
| test_decode_pnm | P6/P5 PNM decode |
| test_decode_bmp | BMP decodes all 4 corners |
| test_decode_gif | GIF frames decode |
| test_decode_jpeg_unsupported | JPEG returns unsupported |
| test_decode_errors | empty/garbage/truncated input errors cleanly |
| test_scene_image | image ops carry premultiplied pixels |
| test_upload | atlas upload premultiplies + records gen/transient |
| test_upload_mask_atlas_rejected | bpp=1 atlas rejected for images |
| test_upload_grows | atlas grows on demand, bumps gen |
| test_upload_too_big | oversized upload errors |
| test_upload_lasting | lasting entries keep pixels |
| test_cache_decode | decode cache memoizes + tracks bytes |
| test_cache_atlas_entry | same image reuses atlas entry, no rewrite |
| test_cache_frame | transient re-uploads per frame; lasting untouched |
| test_cache_stale_gen | stale gen forces re-upload |
| test_cache_lru | LRU evicts oldest, keeps hot |
| test_fit | Fill/Natural/Contain/Cover fit rects |

### platform/native/lui_paint/test/lui_paint_test.ml (37)

| test | asserts |
|---|---|
| test_hex | #rgb/#rrggbb/#rrggbbaa parse; unknown name -> None |
| test_edges | 1/2/3/4-value edge parsing |
| test_fill_op | fill op carries color + radius |
| test_children_order | children paint in order |
| test_invisible | invisible node emits no ops |
| test_clip | clip op clips children |
| test_gradient | linear gradient direction + colors |
| test_gradient_variants | oklab/stripes/45deg variants |
| test_dashed_border | dashed border flag set |
| test_per_edge_borders | per-edge widths |
| test_per_edge_border_colors | per-edge colors |
| test_shadow_parse | shadow spec: dx/dy/blur/alpha/outset/inset/spread |
| test_shadow_op | shadow op rect/blur/color |
| test_inset_shadow_op | inset shadow deflates rect |
| test_state_background | hover state background wins |
| test_state_precedence | pressed > hover precedence |
| test_selected_shadow | selected+hover shadow composition |
| test_disabled_opacity | disabled halves opacity |
| test_opacity_multiply | opacity multiplies down the tree |
| test_zindex | z-index reorders paint |
| test_display_contents | display:contents paints child only |
| test_position_absolute | absolute position applied |
| test_position_relative | relative offset applied |
| test_popup_xy | popup positioned at xy |
| test_layout_override | layout override rect honored |
| test_divider | 1px divider at right y |
| test_spacer | spacer emits no ops |
| test_progress | progress track/fill fractions |
| test_checkbox | checked checkbox: accent fill + check glyph |
| test_checkbox_unchecked | unchecked: bordered hollow box |
| test_switch | switch track accent + thumb right-aligned |
| test_radio | radio outer accent + inner dot |
| test_spinner | spinner edges on three arcs |
| test_slider | slider track/fill/thumb position |
| test_scrollbar | scrollbar thumb size + right edge |
| test_extension | unknown extension emits no ops |
| test_coverage_table | every prop classified Painted/Host/Unmapped |

### platform/native/lui_store/test/lui_store_test.ml (10)

| test | asserts |
|---|---|
| test_create_and_insert | insert builds tree + preorder |
| test_insert_order | middle insert keeps order |
| test_move_child | reorder within parent |
| test_move_across_parents | reparent updates both parents |
| test_drop_subtree | drop removes subtree + marks dirty |
| test_props | prop set/remove |
| test_extension | extension kind/id + prop cleanup |
| test_dirty | dirty set drains once |
| test_root_ids | root listing |
| test_ops_on_missing_are_ignored | ops on missing nodes ignored |

### platform/native/lui_text/test/lui_text_test.ml (25)

| test | asserts |
|---|---|
| test_metrics | font metrics: size/ascent/descent/leading/line-height |
| test_create_named | named font resolves with size + family |
| test_create_missing_family | missing family still produces a font |
| test_create_same_args_same_font | identical args share the font |
| test_weight_changes_glyphs | bold produces different bitmaps |
| test_italic | italic face resolves |
| test_monospace | monospace face resolves |
| test_shape_ascii | shaping: line range, runs, glyph count, advance, cluster, width |
| test_shape_wrap | shaped lines respect wrap width |
| test_measure_matches | measured width matches layout |
| test_newlines | newlines split lines |
| test_cjk | CJK shapes |
| test_mixed_runs | mixed-script runs shape |
| test_rtl_paragraph | RTL paragraph orders runs correctly |
| test_emoji_color_glyph | emoji -> color bitmap glyph |
| test_fallback_font | missing glyphs use fallback font |
| test_rasterize_mask | glyph rasterizes alpha mask |
| test_rasterize_determinism | rasterization deterministic |
| test_rasterize_subpixel | subpixel offsets rasterize |
| test_rasterize_scale | scaled rasterization |
| test_rasterize_invalid | invalid glyph handled |
| test_subpixel_positions | positions quantized to subpixel grid |
| test_baseline | baseline offset correct |
| test_empty | empty string shapes to empty |
| test_run_font_matches | shaped runs use requested font |

### platform/native/lui_text_pango/test/lui_text_pango_test.ml (25)

Same 24 test names as `lui_text_test.ml`, run against the pango backend —
par proves both text stacks agree on metrics, shaping, RTL, emoji,
fallback and rasterization semantics.

### platform/native/lui_a11y/test/lui_a11y_test.ml (17)

| test | asserts |
|---|---|
| test_role_table_complete | every standard kind maps to a role |
| test_role_fallbacks | unknown/extension kinds fall back correctly |
| test_role_prop_override | role prop overrides kind default; expanded state |
| test_name_precedence | name sources resolve in precedence order |
| test_accessibility_label_prop | accessibility-label prop surfaces |
| test_description_precedence | description sources resolve in order |
| test_descendant_name | text descendants join into parent name |
| test_checked_states | checked/mixed/unchecked states |
| test_state_flags | focusable/disabled/selected/required/read-only flags |
| test_value | value nodes carry values |
| test_build_forest | forest roots + children from store |
| test_flatten_preorder | preorder flattening of tree |
| test_hidden_excluded | hidden/display-none subtrees excluded |
| test_extension_kept | extension nodes kept with id + name |
| test_update_marks_only_changed | sync marks only changed nodes |
| test_update_structure | sync tracks adds/drops/visibility flips |
| test_focus_tracking | focused node tracked + moved |

### platform/native/lui_layout/test/lui_layout_test.ml (9)

| test | asserts |
|---|---|
| test_column_padding_gap | column placement honors padding + gap |
| test_grid_wraps | grid cells wrap into tracks |
| test_absolute_inset | absolute child inset placed |
| test_text_measured | text node measured for size |
| test_percent_size | percent sizes resolve |
| test_nested_column_in_row | nested column inside row |
| test_run_placements | placement runs; p_override cleared |
| test_display_none_absent | display:none yields no rect |
| test_rebuild_after_mutation | layout rebuild tracks mutation |

### platform/native/spike/test/test_spike_render.ml (4)

| test | asserts |
|---|---|
| test_coverage | coverage ramp across edge distances |
| test_deterministic | render checksum deterministic |
| test_sdf_fill | SDF fill produces expected pixels |
| test_blit | glyph blit lands in frame |
## Coverage ratio by area

| area | ref tests | n/a | covered | gaps | ratio |
|---|---|---|---|---|---|
| internal/accelerator | 4 | 0 | 0 | 4 | 0% |
| internal/darwin | 5 | 5 | 0 | 0 | n/a |
| internal/e2e | 88 | 64 | 3 | 21 | 12% |
| internal/gamut | 9 | 0 | 0 | 9 | 0% |
| internal/gpu | 14 | 5 | 5 | 4 | 56% |
| internal/linux | 1 | 1 | 0 | 0 | n/a |
| internal/raster | 10 | 1 | 0 | 9 | 0% |
| internal/scene | 5 | 0 | 3 | 2 | 60% |
| internal/svg | 23 | 0 | 0 | 23 | 0% |
| internal/text | 44 | 0 | 8 | 36 | 18% |
| codegen / migration / vet tooling (`internal/tsgen`, `internal/uimigrate`, `internal/uivet`) | 14 | 14 | 0 | 0 | n/a |
| internal/update | 10 | 10 | 0 | 0 | n/a |
| internal/windows | 2 | 2 | 0 | 0 | n/a |
| ui/access_test.go | 7 | 0 | 0 | 7 | 0% |
| action queries and pending edits (`ui/action_queries_test.go`, `ui/api_bench_test.go`, `ui/bench_test.go`) | 5 | 2 | 0 | 3 | 0% |
| ui/base_test.go | 11 | 0 | 0 | 11 | 0% |
| ui/bitmap_test.go | 5 | 0 | 0 | 5 | 0% |
| collapsible / combobox (`ui/collapsible_test.go`, `ui/combobox_test.go`) | 11 | 0 | 0 | 11 | 0% |
| data drag / file drop (`ui/data_drag_test.go`, `ui/drop_test.go`, `ui/dragdrop_test.go`) | 9 | 0 | 0 | 9 | 0% |
| ui/datetime_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/editor_input_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/feedback_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/form_test.go | 3 | 0 | 0 | 3 | 0% |
| ui/frame_test.go | 25 | 0 | 0 | 25 | 0% |
| ui/framestats_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/gpu_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/gridview_test.go | 3 | 0 | 0 | 3 | 0% |
| ui/indicators_test.go | 8 | 0 | 0 | 8 | 0% |
| ui/inline_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/inspector_test.go | 8 | 8 | 0 | 0 | n/a |
| ui/layout_grow_test.go | 1 | 0 | 1 | 0 | 100% |
| ui/lifetime_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/list_sideways_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/list_test.go | 36 | 0 | 0 | 36 | 0% |
| ui/memory_test.go | 6 | 0 | 0 | 6 | 0% |
| ui/menu_test.go | 8 | 0 | 0 | 8 | 0% |
| modifiers / outline (`ui/modifiers_test.go`, `ui/outline_test.go`) | 5 | 0 | 0 | 5 | 0% |
| paint and repaint (`ui/paint_test.go`, `ui/repaint_test.go`) | 9 | 0 | 0 | 9 | 0% |
| paste / preferences (`ui/paste_test.go`, `ui/preferences_test.go`) | 5 | 0 | 0 | 5 | 0% |
| ui/primitives_test.go | 19 | 0 | 0 | 19 | 0% |
| ui/richtext_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/router_test.go | 10 | 10 | 0 | 0 | n/a |
| ui/scope_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/scroll_test.go | 8 | 0 | 0 | 8 | 0% |
| selection (`ui/select_test.go`, `ui/selection_test.go`, `ui/selection_press_test.go`) | 15 | 0 | 0 | 15 | 0% |
| ui/shadow_test.go | 1 | 0 | 0 | 1 | 0% |
| ui/sidebar_test.go | 1 | 0 | 0 | 1 | 0% |
| ui/style_test.go | 20 | 0 | 7 | 13 | 35% |
| ui/svg_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/table_test.go | 8 | 0 | 0 | 8 | 0% |
| text buffer (`ui/text_buffer_test.go`, `ui/text_buffer_bench_test.go`) | 5 | 1 | 0 | 4 | 0% |
| ui/text_input_client_test.go | 7 | 0 | 0 | 7 | 0% |
| ui/textarea_test.go | 26 | 0 | 0 | 26 | 0% |
| ui/textbuffer_input_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/textlines_test.go | 2 | 0 | 0 | 2 | 0% |
| ui/textselection_test.go | 13 | 0 | 0 | 13 | 0% |
| ui/textstyle_test.go | 1 | 0 | 0 | 1 | 0% |
| ui/theme_test.go | 4 | 0 | 1 | 3 | 25% |
| ui/toast_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/toggle_test.go | 9 | 0 | 0 | 9 | 0% |
| ui/tooltip_test.go | 4 | 0 | 0 | 4 | 0% |
| ui/transition_test.go | 10 | 0 | 0 | 10 | 0% |
| ui/ui_test.go | 14 | 1 | 3 | 10 | 23% |
| ui/webview_test.go | 7 | 6 | 0 | 1 | 0% |
| ui/widecolor_test.go | 12 | 0 | 0 | 12 | 0% |
| ui/widgets_more_test.go | 12 | 0 | 0 | 12 | 0% |
| platform/native/e2e/test/e2e_test.ml (10) | 0 | 0 | 0 | 0 | n/a |
| platform/native/test/lui_native_test.ml (12) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_flex/test/lui_flex_test.ml (29) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_gl/test/lui_gl_test.ml (7) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_gpu/test/lui_gpu_test.ml (11) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_image/test/lui_image_test.ml (22) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_paint/test/lui_paint_test.ml (38) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_store/test/lui_store_test.ml (10) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_text/test/lui_text_test.ml (24) | 0 | 0 | 0 | 0 | n/a |
| platform/native/lui_text_pango/test/lui_text_pango_test.ml (24) | 0 | 0 | 0 | 0 | n/a |
| platform/native/spike/test/test_spike_render.ml (4) | 0 | 0 | 0 | 0 | n/a |
| **total** | 660 | 130 | 31 | 499 | **6%** |

Ratios count rows with a `path:test_name` citation against non-n/a rows;
partially-covered rows count as gaps until their suggested test lands.

## Appendix A — our native test inventory (217 tests, 13 files)

### platform/native/e2e/test/e2e_test.ml (10)

| test | asserts |
|---|---|
| test_boot_pipeline | boot batch builds store: 12 nodes, roots/kinds, generation 1 |
| test_text_changed | text-change event updates model draft + field prop, marks dirty, emits glyph ops + summary |
| test_press_add_remove_promote | press adds item; remove promotes child; store + dirty reflect both |
| test_unsupported_event_rejected | value-change/press on text-field raise |
| test_echo_suppressed | echo event flushes without new generation |
| test_dispose | dispose empties the store |
| test_scene_ops | scene batch: node count, roots, scroll children, extension kind/id, op sequence |
| test_move_remove_drop | move reorders children, remove detaches to root; parents + dirty tracked |
| test_invalid_ops_ignored | ops on missing nodes ignored, nothing dirtied |
| test_host_flags_and_resize | repaint flag set/cleared; resize reallocates frame buffer + scene size |

### platform/native/test/lui_native_test.ml (12)

| test | asserts |
|---|---|
| test_atlas_alloc | alloc positions advance; oversized alloc fails |
| test_atlas_transient | transient zone top lowered then restored |
| test_atlas_changes | per-rect change list; generation mismatch reports full |
| test_atlas_grow | grow doubles width and bumps generation |
| test_atlas_repack | repack repositions all entries |
| test_fit_radii | corner radii scaled to fit the rect |
| test_corners_continuous | negative/continuous corners handled |
| test_inner_radii | inner radii inset correctly |
| test_sd_round_rect | rounded-rect SDF sign inside/outside/edge |
| test_gamma_ratios | coverage-correction gamma ratios finite |
| test_backdrop_of | backdrop rect covers reach, clamped to frame |
| test_blur_weight | gaussian blur weight: sigma0==1, decays |
| test_pipeline | style to fill-op pipeline picks right color |

### platform/native/lui_flex/test/lui_flex_test.ml (29)

| test | asserts |
|---|---|
| test_row | row lays children horizontally |
| test_column | column stacks children vertically |
| test_justify_center | justify-center packs children centrally |
| test_justify_space_between | space-between distributes |
| test_justify_space_evenly | space-evenly distributes |
| test_flex_grow | grow factor expands children |
| test_flex_shrink | shrink factor contracts children |
| test_min_max | min/max sizes clamp layout |
| test_wrap | wrap pushes children to next line |
| test_wrap_gap | gap between wrapped lines |
| test_column_gap | column gap applied |
| test_row_gap | row gap applied |
| test_absolute_offsets | absolute child offsets applied |
| test_absolute_trailing | trailing absolute offsets applied |
| test_absolute_ignored_in_flow | absolute child ignored in flow |
| test_nested_padding | padding nests correctly |
| test_deep_nesting | deeply nested flex resolves |
| test_percent_dims | percent dims resolve against parent |
| test_percent_against_inner | percent resolves against inner size |
| test_percent_margin | percent margins resolve |
| test_percent_flex_basis | percent flex basis resolves |
| test_auto_container | auto container sizes to content |
| test_auto_margin_main | auto margin on main axis |
| test_auto_margin_split | auto margins split space |
| test_align_stretch | align-stretch fills cross axis |
| test_align_center | align-center centers on cross axis |
| test_row_reverse | row-reverse order |
| test_measure_leaf | measure fn sizes leaf nodes |
| test_measure_is_leaf | measured nodes treated as leaves |

### platform/native/lui_gl/test/lui_gl_test.ml (7)

| test | asserts |
|---|---|
| test_pack_offsets | vertex attribute offsets/stride exact (11 attrs, 176 bytes) |
| test_pack_batches | batches packed with rect float data |
| test_pack_spans | batch spans + scissor rect per clip |
| test_clamp_scissor | scissor clamped to frame bounds |
| test_atlas_plan | atlas plan: Nothing / Upload / Recreate per change + gen |
| test_effect_source | compiled effect GLSL contains expected source |
| test_gl_render | GL output == CPU raster: same pixels, non-blank, red fill center |

### platform/native/lui_gpu/test/lui_gpu_test.ml (11)

| test | asserts |
|---|---|
| test_build | scene ops -> instanced batches incl. glyph + image batches + scissors |
| test_nested_clips | nested clips produce nested scissor batches |
| test_empty_clip_skips | empty clip drops its instances |
| test_clip_off_frame | off-frame clips intersect scissor correctly |
| test_holes | hole batches flagged and merged |
| test_effect_backdrop | effect batches carry backdrop area/down/radius |
| test_glyph_kinds | mask/color/clip glyph kinds emitted |
| test_gradient_glyphs | gradient text produces gradient glyph ops |
| test_wide | wide colors packed into instances |
| test_float32_packing | 44-float instance layout exact incl. f32 rounding |
| test_shader_source | shader source embedded in library |

### platform/native/lui_image/test/lui_image_test.ml (20)

| test | asserts |
|---|---|
| test_decode_rgba_png | RGBA PNG decodes per-pixel incl. alpha |
| test_decode_rgb_png | RGB PNG decodes opaque |
| test_decode_greya_png | gray+alpha PNG decodes |
| test_decode_pnm | P6/P5 PNM decode |
| test_decode_bmp | BMP decodes all 4 corners |
| test_decode_gif | GIF frames decode |
| test_decode_jpeg_unsupported | JPEG returns unsupported |
| test_decode_errors | empty/garbage/truncated input errors cleanly |
| test_scene_image | image ops carry premultiplied pixels |
| test_upload | atlas upload premultiplies + records gen/transient |
| test_upload_mask_atlas_rejected | bpp=1 atlas rejected for images |
| test_upload_grows | atlas grows on demand, bumps gen |
| test_upload_too_big | oversized upload errors |
| test_upload_lasting | lasting entries keep pixels |
| test_cache_decode | decode cache memoizes + tracks bytes |
| test_cache_atlas_entry | same image reuses atlas entry, no rewrite |
| test_cache_frame | transient re-uploads per frame; lasting untouched |
| test_cache_stale_gen | stale gen forces re-upload |
| test_cache_lru | LRU evicts oldest, keeps hot |
| test_fit | Fill/Natural/Contain/Cover fit rects |

### platform/native/lui_paint/test/lui_paint_test.ml (37)

| test | asserts |
|---|---|
| test_hex | #rgb/#rrggbb/#rrggbbaa parse; unknown name -> None |
| test_edges | 1/2/3/4-value edge parsing |
| test_fill_op | fill op carries color + radius |
| test_children_order | children paint in order |
| test_invisible | invisible node emits no ops |
| test_clip | clip op clips children |
| test_gradient | linear gradient direction + colors |
| test_gradient_variants | oklab/stripes/45deg variants |
| test_dashed_border | dashed border flag set |
| test_per_edge_borders | per-edge widths |
| test_per_edge_border_colors | per-edge colors |
| test_shadow_parse | shadow spec: dx/dy/blur/alpha/outset/inset/spread |
| test_shadow_op | shadow op rect/blur/color |
| test_inset_shadow_op | inset shadow deflates rect |
| test_state_background | hover state background wins |
| test_state_precedence | pressed > hover precedence |
| test_selected_shadow | selected+hover shadow composition |
| test_disabled_opacity | disabled halves opacity |
| test_opacity_multiply | opacity multiplies down the tree |
| test_zindex | z-index reorders paint |
| test_display_contents | display:contents paints child only |
| test_position_absolute | absolute position applied |
| test_position_relative | relative offset applied |
| test_popup_xy | popup positioned at xy |
| test_layout_override | layout override rect honored |
| test_divider | 1px divider at right y |
| test_spacer | spacer emits no ops |
| test_progress | progress track/fill fractions |
| test_checkbox | checked checkbox: accent fill + check glyph |
| test_checkbox_unchecked | unchecked: bordered hollow box |
| test_switch | switch track accent + thumb right-aligned |
| test_radio | radio outer accent + inner dot |
| test_spinner | spinner edges on three arcs |
| test_slider | slider track/fill/thumb position |
| test_scrollbar | scrollbar thumb size + right edge |
| test_extension | unknown extension emits no ops |
| test_coverage_table | every prop classified Painted/Host/Unmapped |

### platform/native/lui_store/test/lui_store_test.ml (10)

| test | asserts |
|---|---|
| test_create_and_insert | insert builds tree + preorder |
| test_insert_order | middle insert keeps order |
| test_move_child | reorder within parent |
| test_move_across_parents | reparent updates both parents |
| test_drop_subtree | drop removes subtree + marks dirty |
| test_props | prop set/remove |
| test_extension | extension kind/id + prop cleanup |
| test_dirty | dirty set drains once |
| test_root_ids | root listing |
| test_ops_on_missing_are_ignored | ops on missing nodes ignored |

### platform/native/lui_text/test/lui_text_test.ml (25)

| test | asserts |
|---|---|
| test_metrics | font metrics: size/ascent/descent/leading/line-height |
| test_create_named | named font resolves with size + family |
| test_create_missing_family | missing family still produces a font |
| test_create_same_args_same_font | identical args share the font |
| test_weight_changes_glyphs | bold produces different bitmaps |
| test_italic | italic face resolves |
| test_monospace | monospace face resolves |
| test_shape_ascii | shaping: line range, runs, glyph count, advance, cluster, width |
| test_shape_wrap | shaped lines respect wrap width |
| test_measure_matches | measured width matches layout |
| test_newlines | newlines split lines |
| test_cjk | CJK shapes |
| test_mixed_runs | mixed-script runs shape |
| test_rtl_paragraph | RTL paragraph orders runs correctly |
| test_emoji_color_glyph | emoji -> color bitmap glyph |
| test_fallback_font | missing glyphs use fallback font |
| test_rasterize_mask | glyph rasterizes alpha mask |
| test_rasterize_determinism | rasterization deterministic |
| test_rasterize_subpixel | subpixel offsets rasterize |
| test_rasterize_scale | scaled rasterization |
| test_rasterize_invalid | invalid glyph handled |
| test_subpixel_positions | positions quantized to subpixel grid |
| test_baseline | baseline offset correct |
| test_empty | empty string shapes to empty |
| test_run_font_matches | shaped runs use requested font |

### platform/native/lui_text_pango/test/lui_text_pango_test.ml (25)

Same 24 test names as `lui_text_test.ml`, run against the pango backend —
par proves both text stacks agree on metrics, shaping, RTL, emoji,
fallback and rasterization semantics.

### platform/native/lui_a11y/test/lui_a11y_test.ml (17)

| test | asserts |
|---|---|
| test_role_table_complete | every standard kind maps to a role |
| test_role_fallbacks | unknown/extension kinds fall back correctly |
| test_role_prop_override | role prop overrides kind default; expanded state |
| test_name_precedence | name sources resolve in precedence order |
| test_accessibility_label_prop | accessibility-label prop surfaces |
| test_description_precedence | description sources resolve in order |
| test_descendant_name | text descendants join into parent name |
| test_checked_states | checked/mixed/unchecked states |
| test_state_flags | focusable/disabled/selected/required/read-only flags |
| test_value | value nodes carry values |
| test_build_forest | forest roots + children from store |
| test_flatten_preorder | preorder flattening of tree |
| test_hidden_excluded | hidden/display-none subtrees excluded |
| test_extension_kept | extension nodes kept with id + name |
| test_update_marks_only_changed | sync marks only changed nodes |
| test_update_structure | sync tracks adds/drops/visibility flips |
| test_focus_tracking | focused node tracked + moved |

### platform/native/lui_layout/test/lui_layout_test.ml (9)

| test | asserts |
|---|---|
| test_column_padding_gap | column placement honors padding + gap |
| test_grid_wraps | grid cells wrap into tracks |
| test_absolute_inset | absolute child inset placed |
| test_text_measured | text node measured for size |
| test_percent_size | percent sizes resolve |
| test_nested_column_in_row | nested column inside row |
| test_run_placements | placement runs; p_override cleared |
| test_display_none_absent | display:none yields no rect |
| test_rebuild_after_mutation | layout rebuild tracks mutation |

### platform/native/spike/test/test_spike_render.ml (4)

| test | asserts |
|---|---|
| test_coverage | coverage ramp across edge distances |
| test_deterministic | render checksum deterministic |
| test_sdf_fill | SDF fill produces expected pixels |
| test_blit | glyph blit lands in frame |
## GAP SUMMARY

495 gaps: **0 P0** correctness-critical, **495 P1** semantics, **0 P2** platform edges.
Owner is the module that should grow the test; `e2e` means the host event harness, `lui_native` the shared `platform/native/test` file.

### P0 — correctness-critical (raster/damage/pixel parity)

1. `test_damage_repaints_only_changed` — lui_scene — covers TestContentWindowRepaintsWhatChanged
2. `test_damage_redraws_what_changed` — lui_scene — covers TestRendererRedrawsWhatChanged
3. `test_damage_redraws_effects` — lui_scene — covers TestRendererRedrawsEffects
4. `test_damage_skips_unchanged` — lui_scene — covers TestRendererSkipsUnchangedScenes
5. `test_render_shapes` — lui_native — covers TestRenderShapes (partially covered)
6. `test_render_text` — lui_native — covers TestRenderText (partially covered)
7. `test_opaque_mask_coverage` — lui_native — covers TestOpaqueMaskCoverage
8. `test_shadow_outside_cast` — lui_native — covers TestShadowShowsOutsideItsCast
9. `test_shadow_formula` — lui_native — covers TestShadowMatchesItsFormula
10. `test_thin_line_coverage` — lui_native — covers TestThinLineCoverage
11. `test_atlas_full_frames` — lui_gl — covers TestFramesStayWholeWhenTheAtlasFills
12. `test_damage_redraws_only_changed` — lui_scene — covers TestFramesRedrawOnlyWhatChanged
13. `test_paths_state_independent` — lui_gl — covers TestPathsLookTheSameWhateverDrewBefore
14. `test_inset_shadow_pixels` — lui_native — covers TestInsetShadow (partially covered)

### P1 — semantics (text layout / IME / a11y / widget behavior)

15. `test_host_before_run` — e2e — covers TestBeforeRun (partially covered)
16. `test_text_selection_drag` — e2e — covers TestContentWindowTextSelection
17. `test_ime_composition` — e2e — covers TestContentWindowInputMethod
18. `test_ime_textarea` — e2e — covers TestContentWindowTextAreaInputMethod
19. `test_ime_text_buffer` — e2e — covers TestContentWindowTextBufferInputMethod
20. `test_observed_events` — e2e — covers TestContentWindowObserved
21. `test_a11y_list` — e2e — covers TestContentWindowListAccessibility (partially covered)
22. `test_list_type_to_choose` — e2e — covers TestContentWindowListTypeToChoose
23. `test_composing_keys` — e2e — covers TestContentWindowComposingKeys
24. `test_menu_button` — e2e — covers TestContentWindowMenuButton
25. `test_context_menu` — e2e — covers TestContentWindowContextMenu
26. `test_text_input_primitive` — e2e — covers TestContentWindowTextInputPrimitive
27. `test_oklab_known_colors` — lui_paint — covers TestOklabKnownColors
28. `test_oklab_round_trip` — lui_paint — covers TestOklabRoundTrip
29. `test_wide_encode_decode` — lui_paint — covers TestEncodeDecode
30. `test_p3_matrices` — lui_paint — covers TestP3Matrices
31. `test_gamut_map_in_gamut` — lui_paint — covers TestMapInGamutIsExact
32. `test_gamut_map_preserves` — lui_paint — covers TestMapKeepsLightnessAndHue
33. `test_gamut_map_p3_chroma` — lui_paint — covers TestMapP3KeepsMoreThanSRGB
34. `test_gamut_map_odd_input` — lui_paint — covers TestMapOddInput
35. `test_gamut_map_extremes` — lui_paint — covers TestMapExtremes
36. `test_text_coverage` — lui_native — covers TestTextCoverage
37. `test_svg_fill` — lui_svg (new) — covers TestFill
38. `test_svg_path_syntax` — lui_svg (new) — covers TestPathSyntax
39. `test_svg_arcs` — lui_svg (new) — covers TestArcs
40. `test_svg_fill_rule` — lui_svg (new) — covers TestFillRule
41. `test_svg_stroke_caps` — lui_svg (new) — covers TestStrokeCaps
42. `test_svg_stroke_joins` — lui_svg (new) — covers TestStrokeJoins
43. `test_svg_dashes` — lui_svg (new) — covers TestDashes
44. `test_svg_transforms` — lui_svg (new) — covers TestTransforms
45. `test_svg_current_color` — lui_svg (new) — covers TestCurrentColor
46. `test_svg_colors` — lui_svg (new) — covers TestColors
47. `test_svg_linear_gradient` — lui_svg (new) — covers TestLinearGradient
48. `test_svg_radial_gradient` — lui_svg (new) — covers TestRadialGradient
49. `test_svg_group_opacity` — lui_svg (new) — covers TestGroupOpacity
50. `test_svg_clip_path` — lui_svg (new) — covers TestClipPath
51. `test_svg_mask` — lui_svg (new) — covers TestMask
52. `test_svg_style_sheets` — lui_svg (new) — covers TestStyleSheets
53. `test_svg_use` — lui_svg (new) — covers TestUse
54. `test_svg_display_visibility` — lui_svg (new) — covers TestDisplayAndVisibility
55. `test_svg_size_aspect` — lui_svg (new) — covers TestSizeAndAspect
56. `test_svg_old_editors` — lui_svg (new) — covers TestOldEditors
57. `test_svg_errors` — lui_svg (new) — covers TestErrors
58. `test_svg_icons` — lui_svg (new) — covers TestIcons
59. `test_svg_uses_current_color` — lui_svg (new) — covers TestUsesCurrentColor
60. `test_caret_positions` — lui_text — covers TestCarets
61. `test_truncation` — lui_text — covers TestTruncation
62. `test_atlas_make_room` — lui_scene — covers TestMakeRoom (partially covered)
63. `test_atlas_make_room_long` — lui_scene — covers TestMakeRoomForLongMasks
64. `test_keep_spaces` — lui_text — covers TestKeepSpaces
65. `test_no_break_words` — lui_text — covers TestNoBreakWords
66. `test_ellipsis` — lui_text — covers TestEllipsis
67. `test_letter_spacing` — lui_text — covers TestLetterSpacing
68. `test_font_features` — lui_text — covers TestFontFeatures
69. `test_parse_features` — lui_text — covers TestParseFeatures
70. `test_spans` — lui_text — covers TestSpans
71. `test_encode_spans` — lui_text — covers TestEncodeSpans
72. `test_spans_across_paragraphs` — lui_text — covers TestSpansAcrossParagraphs
73. `test_digit_features` — lui_text — covers TestDigitFeatures
74. `test_decorate` — lui_text — covers TestDecorate
75. `test_visual_caret_nav` — lui_text — covers caret/TestVisualCaretAffinityAndNavigation
76. `test_visual_selection_bidi` — lui_text — covers caret/TestVisualSelectionKeepsBidiGaps
77. `test_visual_caret_fractional` — lui_text — covers caret/TestVisualCaretFractionalRunEdges
78. `test_visual_caret_wrap` — lui_text — covers caret/TestVisualCaretWrapAndGraphemes
79. `test_caret_hit_wrap_space` — lui_text — covers caret/TestVisualCaretHitBeforeTrimmedWrapSpace
80. `test_layout_cache_bounds` — lui_text — covers memory/TestLayoutCacheBoundsScrollingMemory
81. `test_layout_cache_reuses` — lui_text — covers memory/TestLayoutCacheReusesDisplayedText
82. `test_layout_cache_releases` — lui_text — covers memory/TestLayoutCacheReleasesEvictedText
83. `test_layout_cache_keeps_hot` — lui_text — covers memory/TestLayoutCacheKeepsFrequentlyUsedText
84. `test_layout_cache_skips_oversized` — lui_text — covers memory/TestLayoutCacheSkipsOversizedParagraph
85. `test_retained_layout_cache` — lui_text — covers memory/TestRetainedLayoutDoesNotRetainClearedCache
86. `test_cache_no_retain_source` — lui_text — covers memory/TestLayoutCacheDoesNotRetainExcerptSource
87. `test_pango_letter_spacing` — lui_text_pango — covers pango/TestPangoLayoutAtMeasuredWidthWithLetterSpacing
88. `test_a11y_list` — e2e — covers TestAccessibilityOfLists (partially covered)
89. `test_a11y_scroll_unbuilt_row` — e2e — covers TestAccessibilityScrollsToARowNoLongerBuilt
90. `test_a11y_table` — e2e — covers TestAccessibilityOfTables (partially covered)
91. `test_a11y_overlays` — e2e — covers TestAccessibilityOfOverlays
92. `test_a11y_ime_context` — e2e — covers TestInputMethodContext
93. `test_action_query_pending_edit` — e2e — covers TestActionQueriesReadPendingBoundEdit (partially covered)
94. `test_shortcut_pending_edit` — e2e — covers TestScopedShortcutQueriesReadPendingBoundEdit
95. `test_action_query_input_config` — e2e — covers TestActionQueriesRespectFluentInputConfiguration
96. `test_bases_no_look` — e2e — covers TestBasesHaveNoLook
97. `test_toggle_bases` — e2e — covers TestToggleBases (partially covered)
98. `test_slider_content_box` — e2e — covers TestSliderBaseMapsItsContentBox (partially covered)
99. `test_tabs_base` — e2e — covers TestTabsBase
100. `test_select_base` — e2e — covers TestSelectBase
101. `test_dialog_popover_bases` — e2e — covers TestDialogAndPopoverBases (partially covered)
102. `test_dismissed` — e2e — covers TestDismissed
103. `test_text_input_base` — e2e — covers TestTextInputBase (partially covered)
104. `test_focus_ring` — e2e — covers TestFocusRing
105. `test_popups_open_where_fit` — e2e — covers TestPopupsOpenWhereTheyFit (partially covered)
106. `test_enter_window_shortcut` — e2e — covers TestEnterWithWindowShortcut
107. `test_combobox_rebuild` — e2e — covers TestComboboxChosenRebuildsDependentUI
108. `test_combobox` — e2e — covers TestCombobox
109. `test_combobox_a11y` — e2e — covers TestComboboxAccessibility (partially covered)
110. `test_autocomplete` — e2e — covers TestAutocomplete
111. `test_combobox_scroll_highlight` — e2e — covers TestComboboxScrollsPastHighlight
112. `test_select_scroll_highlight` — e2e — covers TestSelectBaseScrollsToHighlight
113. `test_list_reorder` — e2e — covers TestListReorder
114. `test_grid_reorder` — e2e — covers TestGridReorder
115. `test_editor_client_between_frames` — e2e — covers TestWidgetInputUsesClientBetweenFrames
116. `test_editor_composition_undo` — e2e — covers TestWidgetCompositionHasOneUndoTransaction
117. `test_editor_privacy_readonly` — e2e — covers TestWidgetInputPrivacyAndReadonly
118. `test_editor_bidi_selection` — e2e — covers TestWidgetBidiSelectionCopyReplaceAndUndo
119. `test_editor_query_no_retain` — e2e — covers TestWidgetNativeQueryDoesNotRetainOldDocument
120. `test_editor_layout_release` — e2e — covers TestWidgetSingleLineLayoutReleasesOldDocument
121. `test_editor_malformed_utf8` — e2e — covers TestWidgetNativeQueryMalformedUTF8
122. `test_checkbox_group` — e2e — covers TestCheckboxGroup (partially covered)
123. `test_handles_detach_close` — e2e — covers TestValueHandlesDetachClosedWindow
124. `test_changed_commits` — e2e — covers TestChangedCommitsLocalValueBeforeReturning (partially covered)
125. `test_close_while_building` — e2e — covers TestCloseWhileBuilding
126. `test_gridview` — e2e — covers TestGridView
127. `test_gridview_multi` — e2e — covers TestGridViewChoosesSeveral
128. `test_gridview_resizes` — e2e — covers TestGridViewResizes
129. `test_spinner_behavior` — e2e — covers TestSpinner (partially covered)
130. `test_step_slider` — e2e — covers TestStepSlider (partially covered)
131. `test_range_slider` — e2e — covers TestRangeSlider
132. `test_inline_link` — e2e — covers TestInlineLink
133. `test_inline_styles` — e2e — covers TestInlineStyles
134. `test_inline_interaction` — e2e — covers TestInlineInteraction
135. `test_optional_element_input` — e2e — covers TestOptionalElementInput
136. `test_list_state_focus` — e2e — covers TestListStateFocusAndShortcutsFollowCurrentBuild
137. `test_list_focus_during_build` — e2e — covers TestListStateFocusDuringRowBuild
138. `test_list_state_context` — e2e — covers TestListStateInputRequiresItsActiveContext
139. `test_list_row_width` — e2e — covers TestListRowWidth
140. `test_list_row_width_fits` — e2e — covers TestListRowWidthFits
141. `test_list_variable_heights` — e2e — covers TestListVariableHeights
142. `test_list_fills_first_frame` — e2e — covers TestListFillsTheFirstFrame
143. `test_list_huge_scrolls` — e2e — covers TestListHugeScrollsByFractions
144. `test_list_scroll_to` — e2e — covers TestListScrollTo
145. `test_list_keeps_place` — e2e — covers TestListKeepsPlaceAsRowsAboveChange
146. `test_list_keys` — e2e — covers TestListKeys
147. `test_list_follow_end` — e2e — covers TestListFollowEnd
148. `test_list_follow_end_start` — e2e — covers TestListFollowEndStartsAtTheEnd
149. `test_list_justify_end` — e2e — covers TestListJustifyEnd
150. `test_list_gap_padding` — e2e — covers TestListGapAndPadding
151. `test_list_rows_go_away` — e2e — covers TestListRowsGoAway
152. `test_list_selection` — e2e — covers TestListSelection
153. `test_list_keys_keep_choice` — e2e — covers TestListKeysKeepTheChoice
154. `test_list_keeps_focused` — e2e — covers TestListKeepsTheFocusedRow
155. `test_list_sticky_headers` — e2e — covers TestListStickyHeaders
156. `test_list_rows_below_pinned` — e2e — covers TestListRowsShowBelowThePinnedHeader
157. `test_list_sticky_skip_choice` — e2e — covers TestListStickyHeadersSkipTheChoice
158. `test_list_scrollbar_end` — e2e — covers TestListScrollBarDragReachesTheEnd
159. `test_list_scrollbar_estimates` — e2e — covers TestListScrollBarDragFollowsThePointerAsEstimatesChange
160. `test_list_two_states_panic` — e2e — covers TestListStateOfTwoListsPanics
161. `test_list_tab_reveals` — e2e — covers TestListTabRevealsRows
162. `test_list_view_position` — e2e — covers TestListViewSeesWhereItIs
163. `test_list_keeps_place_resize` — e2e — covers TestListKeepsPlaceAcrossResizes
164. `test_list_keeps_place_rebuild` — e2e — covers TestListKeepsPlaceWhenBuiltAnew
165. `test_list_new_state_start` — e2e — covers TestListNewStateStartsAtTheStart
166. `test_list_heights` — e2e — covers TestListHeights
167. `test_list_pinned_click_once` — e2e — covers TestListPinnedHeaderHandlesAClickOnce
168. `test_list_scroll_rows_one_frame` — e2e — covers TestListScrollAndRowsAboveInOneFrame
169. `test_list_end` — e2e — covers TestListEndShowsTheEnd
170. `test_list_step_unmeasured` — e2e — covers TestListScrollsByTheStepIntoRowsNotMeasured
171. `test_list_track_prefirst` — e2e — covers TestListTrackScrollBeforeTheFirstFrame
172. `test_list_many_states` — e2e — covers TestListOfManyStates
173. `test_list_reveal_far` — e2e — covers TestListRevealsAFarRowWithoutAGap
174. `test_list_sized_by_rows` — e2e — covers TestListSizedByItsRows
175. `test_list_empty` — e2e — covers TestListEmpty
176. `test_list_choice_ends` — e2e — covers TestListChoiceAtTheEnds
177. `test_removed_releases` — e2e — covers TestRemovedContentReleasesResources (partially covered)
178. `test_element_arena_size` — e2e — covers TestElementArenaFollowsViewSize
179. `test_editor_undo_release` — e2e — covers TestEditorUndoReleasesOldDocument
180. `test_editor_redo_release` — e2e — covers TestEditorDiscardedRedoReleasesDocument
181. `test_editor_index_release` — e2e — covers TestEditorSmallDocumentReleasesIndexes
182. `test_editor_paragraph_release` — e2e — covers TestEditorParagraphLayoutReleasesOldDocument
183. `test_context_menu` — e2e — covers TestContextMenu
184. `test_innermost_menu` — e2e — covers TestInnermostContextMenu
185. `test_menu_keyboard` — e2e — covers TestContextMenuFromTheKeyboard
186. `test_input_context_menu` — e2e — covers TestTextInputContextMenu
187. `test_menu_button` — e2e — covers TestMenuButton
188. `test_menu_button_a11y` — e2e — covers TestMenuButtonAccessibility (partially covered)
189. `test_menu_and_context` — e2e — covers TestMenuAndContextMenuOfOneElement
190. `test_modifiers_held` — e2e — covers TestModifiersHeld
191. `test_outline` — e2e — covers TestOutline
192. `test_outline_lazy` — e2e — covers TestOutlineBuildsWhatShows
193. `test_outline_a11y` — e2e — covers TestOutlineExpandsForAssistiveTechnology
194. `test_animated_path` — lui_paint — covers TestAnimatedPathShowsInEveryFrame
195. `test_opaque_under` — lui_gl — covers TestOpaqueUnderElements
196. `test_repaint_frames` — e2e — covers TestRepaintFrames (partially covered)
197. `test_repaint_in_view` — e2e — covers TestRepaintOnlyInView
198. `test_painter_after` — e2e — covers TestPainterAfter
199. `test_indicators_repaint` — e2e — covers TestIndicatorsRepaint
200. `test_held_occluded` — e2e — covers TestHeldWhileOccluded
201. `test_on_paste` — e2e — covers TestOnPaste
202. `test_access_own_states` — e2e — covers TestAccessStatesOfYourOwn
203. `test_readonly_input` — e2e — covers TestReadOnlyInput
204. `test_composing` — e2e — covers TestComposing
205. `test_popover_light_dismiss` — e2e — covers TestPopoverLightDismiss
206. `test_modal_overlay` — e2e — covers TestModalOverlayOfYourOwn
207. `test_slider_settings` — e2e — covers TestSliderBaseSettings (partially covered)
208. `test_select_highlight` — e2e — covers TestSelectHighlight
209. `test_snap_decimals` — e2e — covers TestSnapToTheStepsDecimals
210. `test_stroke_widths` — lui_paint — covers TestStrokesAreAsWideAsAsked (partially covered)
211. `test_popover_scroll_anchor` — e2e — covers TestPopoverScrollsWithItsAnchor
212. `test_escape_inner_popover` — e2e — covers TestEscapeClosesTheInnerPopover
213. `test_range_steps` — e2e — covers TestRangeSteps
214. `test_paste_during_frame` — e2e — covers TestPasteDuringFrame
215. `test_rich_text` — lui_text — covers TestRichText
216. `test_measure_text_cache` — lui_text — covers TestMeasureTextAgain
217. `test_dialog_focus_trap` — e2e — covers TestDialogKeepsTheFocus
218. `test_escape_top_overlay` — e2e — covers TestEscapeClosesTheOverlayOnTop
219. `test_overlay_focus_back` — e2e — covers TestOverlayGivesTheFocusBack
220. `test_shortcuts_behind_dialog` — e2e — covers TestShortcutsWaitBehindADialog
221. `test_popover_follow_anchor` — e2e — covers TestPopoverFollowsItsAnchor
222. `test_dialog_hides_a11y` — e2e — covers TestBehindADialogIsHidden (partially covered)
223. `test_escape_focused_first` — e2e — covers TestEscapeGoesToTheFocusedElementFirst
224. `test_track_scroll` — e2e — covers TestTrackScroll (partially covered)
225. `test_track_scroll_settles` — e2e — covers TestTrackScrollSettles
226. `test_track_scroll_end` — e2e — covers TestTrackScrollFollowsTheEnd
227. `test_track_scroll_page` — e2e — covers TestTrackScrollPerPage
228. `test_track_scroll_list` — e2e — covers TestTrackScrollList
229. `test_scroll_into_view` — e2e — covers TestScrollIntoView
230. `test_scroll_into_view_nested` — e2e — covers TestScrollIntoViewNested
231. `test_tab_scrolls_focus` — e2e — covers TestTabScrollsTheFocusIntoView
232. `test_selectable_text` — e2e — covers TestSelectableText
233. `test_pressed_rebuilds` — e2e — covers TestPressedSelectionRebuildsBeforePaint (partially covered)
234. `test_click_waits_release` — e2e — covers TestButtonClickStillWaitsForRelease
235. `test_click_modifiers` — e2e — covers TestClickModifiers
236. `test_list_multi_select` — e2e — covers TestListChoosesSeveral
237. `test_list_extend_keys` — e2e — covers TestListExtendsTheChoiceWithTheKeys
238. `test_list_move_no_choose` — e2e — covers TestListMovesWithoutChoosing
239. `test_list_choice_follows` — e2e — covers TestListChoiceOfSeveralFollowsItsItems
240. `test_list_type_choose` — e2e — covers TestListTypeToChoose
241. `test_type_choose_shortcuts` — e2e — covers TestListTypeToChooseLeavesShortcuts
242. `test_list_page_keys` — e2e — covers TestListPageKeys
243. `test_a11y_list_multi` — e2e — covers TestAccessibilityOfListsChoosingSeveral (partially covered)
244. `test_table_multi_select` — e2e — covers TestTableChoosesSeveral
245. `test_selection_wrong_key` — e2e — covers TestSelectionOfAnotherKeyPanics
246. `test_type_after_click` — e2e — covers TestListTypeRightAfterAClick
247. `test_text_decorations` — lui_paint — covers TestTextDecorations
248. `test_text_options` — lui_paint — covers TestTextOptions
249. `test_button_intrinsic_width` — e2e — covers TestButtonLabelsAtIntrinsicWidth
250. `test_scroll_both` — e2e — covers TestScrollBoth
251. `test_scrollbar_insets` — e2e — covers TestScrollbarInsets (partially covered)
252. `test_scroll_content_shrinks` — e2e — covers TestScrollContentShrinks
253. `test_icon_text_color` — lui_svg (new) — covers TestIconTakesTheTextColorAndSize
254. `test_icon_draws_once` — lui_svg (new) — covers TestIconDrawsItsShapeOnce
255. `test_image_of_svg` — lui_svg (new) — covers TestImageOfAnSVG
256. `test_svg_picture_color` — lui_svg (new) — covers TestPictureFollowsTheTextColor
257. `test_svg_icons_a11y` — lui_svg (new) — covers TestIconsInAccessibility
258. `test_painter_svg` — lui_svg (new) — covers TestPainterDrawsSVGs
259. `test_svg_parse_errors` — lui_svg (new) — covers TestParseSVGErrors
260. `test_text_buffer_edits` — lui_text — covers TestTextBufferRandomEditsAndSnapshots
261. `test_text_buffer_ranges` — lui_text — covers TestTextBufferNativeRangesMalformedAndZero
262. `test_text_buffer_chunks` — lui_text — covers TestTextBufferOwnsBoundedChunks
263. `test_text_buffer_concurrent` — lui_text — covers TestTextBufferConcurrentSnapshots
264. `test_tic_composition` — e2e — covers TestTextInputClientCompositionAndReplacement
265. `test_tic_end_before_commit` — e2e — covers TestTextInputClientNativeEndBeforeCommit
266. `test_tic_geometry_lifetime` — e2e — covers TestTextInputClientQueriesGeometryAndLifetime
267. `test_tic_swapping` — e2e — covers TestTextInputClientSwappingAndTypedNil
268. `test_tic_surrounding` — e2e — covers TestTextInputSurroundingUnicodeAndReversedSelection
269. `test_tic_utf16_ranges` — lui_text — covers TestTextLayoutUTF16GraphemesAndBidiRanges
270. `test_tic_visual_caret_utf16` — lui_text — covers TestTextLayoutVisualCaretUTF16
271. `test_textarea_buffer_edits` — e2e — covers TestBufferEdits
272. `test_textarea_set_utf8` — e2e — covers TestBufferSetUTF8
273. `test_textarea_words` — e2e — covers TestBufferWords
274. `test_textarea_graphemes` — e2e — covers TestBufferGraphemes
275. `test_textarea_heights` — e2e — covers TestHeights
276. `test_textarea_layout_whole` — e2e — covers TestTextAreaLaysOutAsWholeText
277. `test_textarea_undo` — e2e — covers TestTextAreaUndo
278. `test_textarea_scrolls` — e2e — covers TestTextAreaScrolls
279. `test_textarea_select_whole` — e2e — covers TestTextAreaSelectsAsWholeText
280. `test_textarea_undo_app` — e2e — covers TestTextAreaUndoAppChanges
281. `test_textarea_undo_log` — e2e — covers TestTextAreaUndoAppLog
282. `test_textarea_shares_value` — e2e — covers TestTextAreaSharesValue
283. `test_textarea_reveals_wrapped` — e2e — covers TestTextAreaRevealsWrapped
284. `test_textarea_keeps_view` — e2e — covers TestTextAreaKeepsViewOnAppText
285. `test_textarea_lines_wrap` — e2e — covers TestTextAreaLinesFollowWrappedText
286. `test_textarea_selection` — e2e — covers TestTextSelection
287. `test_text_ranges` — e2e — covers TestTextRanges
288. `test_text_ranges_composing` — e2e — covers TestTextRangesWhileComposing
289. `test_buffer_input_undo` — e2e — covers TestBufferInputsEditComposeAndUndo
290. `test_buffer_area_queries` — e2e — covers TestBufferAreaNativeQueriesAndLineEditing
291. `test_buffer_input_bidi` — e2e — covers TestBufferInputBidiReplacementAndExternalChange
292. `test_buffer_input_swap` — e2e — covers TestBufferInputBindingSwapAndStringCompatibility
293. `test_text_lines` — lui_text — covers TestTextLines (partially covered)
294. `test_text_lines_before_layout` — lui_text — covers TestTextLinesBeforeLayout
295. `test_sel_multi_click` — e2e — covers TestSelectableContainerMultiClick
296. `test_sel_order_overlap` — e2e — covers TestSelectableContainerOrderAndOverlap
297. `test_sel_scroll` — e2e — covers TestSelectableContainerScroll
298. `test_sel_inline_rebuild` — e2e — covers TestSelectableInlineParagraphRebuild
299. `test_sel_container` — e2e — covers TestSelectableContainer
300. `test_sel_keyboard` — e2e — covers TestSelectableContainerKeyboard
301. `test_sel_scopes` — e2e — covers TestSelectableContainerScopesAndControls
302. `test_sel_inline` — e2e — covers TestSelectableContainerInlineAndRebuild
303. `test_sel_other_text` — e2e — covers TestSelectableContainerChangingOtherText
304. `test_sel_focus_disable` — e2e — covers TestSelectableContainerFocusAndDisable
305. `test_sel_context_menu` — e2e — covers TestSelectableTextContextMenu
306. `test_sel_edit_items` — e2e — covers TestTextInputContextMenuEditItems
307. `test_sel_color` — e2e — covers TestSelectionColor
308. `test_letter_spacing_features` — lui_text — covers TestLetterSpacingAndFeatures
309. `test_focus_group_tab` — e2e — covers TestFocusGroupIsOneTabStop
310. `test_focus_group_keys` — e2e — covers TestFocusGroupLeavesKeysToWhatTakesThem
311. `test_radio_arrows` — e2e — covers TestRadioGroupArrowsChoose (partially covered)
312. `test_toggle_behavior` — e2e — covers TestToggle (partially covered)
313. `test_tabs_tab_stop` — e2e — covers TestTabsAreOneTabStop
314. `test_toolbar_a11y` — e2e — covers TestToolbarAccessibility (partially covered)
315. `test_demo_renders` — e2e — covers TestDemoRenders (partially covered)
316. `test_input_follows_focus` — e2e — covers TestTextInputFollowsTheFocusAtOnce
317. `test_key_on_widget` — e2e — covers TestKeyOnAWidget
318. `test_emacs_keys` — e2e — covers TestEmacsKeys
319. `test_list_scroll_select` — e2e — covers TestListScrollsAndSelects
320. `test_tab_focus` — e2e — covers TestTabFocus
321. `test_auto_focus` — e2e — covers TestAutoFocus
322. `test_keyboard_scrolling` — e2e — covers TestKeyboardScrolling
323. `test_hover_while_pressed` — e2e — covers TestHoverWhilePressed
324. `test_popover_last_press` — e2e — covers TestPopoverLastPressDecides
325. `test_oklch_srgb` — lui_paint — covers TestOklchInsideSRGBHasNoWideColor
326. `test_wide_color_value` — lui_paint — covers TestOklchOutsideSRGBKeepsWideColor (partially covered)
327. `test_oklch_odd_input` — lui_paint — covers TestOklchOddInput
328. `test_mix_wide` — lui_paint — covers TestMixWide
329. `test_wide_draws_nearest` — lui_paint — covers TestBackgroundDrawsNearestSRGB
330. `test_wide_paint_paths` — lui_paint — covers TestWideShadowStripesGradientAndText (partially covered)
331. `test_wide_only_where_shows` — lui_paint — covers TestWideOnlyWhereItShows
332. `test_wide_decorations` — lui_paint — covers TestWideDecorationsDividersAndTextBackground
333. `test_effect_color` — lui_gpu — covers TestEffectColor (partially covered)
334. `test_tabs` — e2e — covers TestTabs

### P2 — platform edges and polish

335. `test_accel_parse` — e2e — covers TestParse
336. `test_accel_parse_errors` — e2e — covers TestParseErrors
337. `test_accel_to_string` — e2e — covers TestString
338. `test_accel_xdg_trigger` — e2e — covers TestXDGTrigger
339. `test_resize_below_minimum` — e2e — covers TestResizeBelowMinimum (partially covered)
340. `test_global_shortcut` — e2e — covers TestGlobalShortcut
341. `test_global_shortcut_portal` — e2e — covers TestGlobalShortcutPortal
342. `test_close_events` — e2e — covers TestCloseEvents
343. `test_calls_end_on_close` — e2e — covers TestCallsEndWithTheWindow
344. `test_reorder_by_drag` — e2e — covers TestReorderByDragging
345. `test_resize_first_frame` — e2e — covers TestContentWindowResizeFromFirstFrame (partially covered)
346. `test_shader_source_sum` — lui_gpu — covers TestSourceSum (partially covered)
347. `test_gl_resize_settles` — lui_gl — covers d3d11/TestResizeSettles
348. `test_gl_resources_on_demand` — lui_gl — covers metal/TestDrawingResourcesOnDemand
349. `test_shader_source_sum` — lui_gpu — covers metal/TestShaderLibrary (partially covered)
350. `test_atlas_put_clears_padding` — lui_scene — covers TestAtlasPutClearsPadding
351. `test_glyph_shades` — lui_text — covers TestShadeOf
352. `test_glyph_shades` — lui_text — covers TestGlyphShades
353. `test_glyph_thick` — lui_text — covers TestThick
354. `test_glyph_flat` — lui_text — covers TestFlat
355. `test_mask_lasts_drawn` — lui_scene — covers TestMaskLastsOnceDrawnAgain
356. `test_register_font` — lui_text — covers TestRegisterFont
357. `test_ui_family` — lui_text — covers TestUIFamily
358. `test_fonts_many_sizes` — lui_text — covers TestFontsOfManySizes
359. `test_bitmap_downscale` — lui_image — covers TestBitmapShowsSmallerSmoothly
360. `test_bitmap_halve` — lui_image — covers TestHalve
361. `test_bitmap_exif` — lui_image — covers TestDecodeBitmapTurnsPhotosUpright
362. `test_decode_webp` — lui_image — covers TestDecodeBitmapOfWebPAndBMP (partially covered)
363. `test_bitmap_update` — lui_image — covers TestBitmapUpdate (partially covered)
364. `test_collapsible` — e2e — covers TestCollapsible
365. `test_collapsible_animates` — e2e — covers TestCollapsibleAnimates
366. `test_accordion` — e2e — covers TestAccordion
367. `test_search_field` — e2e — covers TestSearchField
368. `test_token_field` — e2e — covers TestTokenField
369. `test_data_drop_negotiate` — e2e — covers TestNativeDataDropNegotiatesAndReadsOnDrop
370. `test_data_drop_typed` — e2e — covers TestNativeTypedDropKeepsGoValue
371. `test_drag_cancel_cleanup` — e2e — covers TestNativeDragCancellationAndSourceRemoval
372. `test_drag_close_releases_ime` — e2e — covers TestNativeDragCloseReleasesTextInputClient
373. `test_drag_rejects` — e2e — covers TestNativeDestinationRejectsMismatchDisabledAndFailedData
374. `test_drag_and_drop` — e2e — covers TestDragAndDrop
375. `test_file_drops` — e2e — covers TestFileDrops
376. `test_calendar` — e2e — covers TestCalendar
377. `test_time_input` — e2e — covers TestTimeInput
378. `test_color_picker` — e2e — covers TestColorPicker
379. `test_color_well` — e2e — covers TestColorWell
380. `test_toast_action` — e2e — covers TestToastAction
381. `test_breadcrumbs` — e2e — covers TestBreadcrumbs
382. `test_alert_dialog` — e2e — covers TestAlertDialog
383. `test_alert_dialog_escape` — e2e — covers TestAlertDialogEscape
384. `test_alert_dialog_keep_open` — e2e — covers TestAlertDialogKeepOpen
385. `test_find_bar` — e2e — covers TestFindBar
386. `test_field` — e2e — covers TestField
387. `test_field_disabled` — e2e — covers TestFieldDisabled
388. `test_form_layout` — e2e — covers TestFormLayout
389. `test_value_handle_expiry` — e2e — covers TestValueHandleExpiresBeforeStorageReuse
390. `test_captured_context_parent` — e2e — covers TestCapturedContextUsesCurrentParent
391. `test_actions_after_build` — e2e — covers TestActionsRunAfterBuildOnce
392. `test_deferred_control` — e2e — covers TestDeferredControlIdentityAndConfiguration
393. `test_refocus_waits` — e2e — covers TestReferenceFocusWaitsForControl
394. `test_deferred_input_options` — e2e — covers TestDeferredInputOptions
395. `test_custom_parts` — e2e — covers TestCustomPartsUseCheckedValuesAndKeys
396. `test_row_scope_keyboard` — e2e — covers TestPublicRowScopeAndKeyboardActions
397. `test_services_outlive_build` — e2e — covers TestWindowServicesOutliveBuild
398. `test_handle_diagnostics` — e2e — covers TestExpiredHandleDiagnosticsAndSlotReuse
399. `test_handle_queries` — e2e — covers TestHandleQueriesBeforeBindingAndAcrossWindows
400. `test_shortcut_hidden_control` — e2e — covers TestHandleShortcutBeforeBindingDropsHiddenControl
401. `test_focus_binding` — e2e — covers TestFocusBindingDistinguishesRequestedAndActual
402. `test_bound_input_timing` — e2e — covers TestBoundInputRunsAfterAllConfiguration
403. `test_response_commit_text` — e2e — covers TestResponseQueriesCommitLocalText
404. `test_response_later_controls` — e2e — covers TestResponseQueriesProcessLaterControls
405. `test_changed_composite` — e2e — covers TestChangedCommitsLocalCompositeValues
406. `test_changed_slider_options` — e2e — covers TestChangedAppliesSliderOptionsBeforeInput (partially covered)
407. `test_changed_derived` — e2e — covers TestChangeActionsCommitDerivedValuesBeforeRebuild
408. `test_notice_derived_text` — e2e — covers TestNoticeActionsCommitDerivedText
409. `test_generation_wrap` — e2e — covers TestGenerationWrapRetiresOwner (partially covered)
410. `test_handle_bounds` — e2e — covers TestHandleBoundsBetweenBuilds
411. `test_framestats_setting` — e2e — covers TestFrameStatsSetting
412. `test_framestats` — e2e — covers TestFrameStats
413. `test_gpu_comes_back` — lui_gl — covers TestGPUComesBack
414. `test_software_fallback` — lui_gl — covers TestSoftwareUntilTheGPUIsBack
415. `test_no_gpu_start` — lui_gl — covers TestNoGPUFromTheStart
416. `test_every_frame_gpu` — lui_gl — covers TestEveryFrameOnTheGPU
417. `test_meter` — e2e — covers TestMeter
418. `test_rating` — e2e — covers TestRating
419. `test_stepper` — e2e — covers TestStepper
420. `test_avatar` — e2e — covers TestAvatar
421. `test_initials` — e2e — covers TestInitials
422. `test_inline_only_text_panics` — e2e — covers TestInlineOnlyText
423. `test_menu_accelerator_string` — e2e — covers TestAccelerator
424. `test_outline_table` — e2e — covers TestOutlineTable
425. `test_theme_accent` — e2e — covers TestThemeFollowsTheAccent
426. `test_theme_contrast_size` — e2e — covers TestThemeFollowsContrastAndTextSize
427. `test_animate_no_motion` — e2e — covers TestAnimateWithoutMotion
428. `test_own_theme_prefs` — e2e — covers TestOwnThemeIgnoresPreferences
429. `test_open_url` — e2e — covers TestOpenURLOutcome
430. `test_attach_to` — e2e — covers TestAttachTo
431. `test_disabled_stepper` — e2e — covers TestDisabledStepper
432. `test_drawer` — e2e — covers TestDrawer
433. `test_attach_inline_text` — e2e — covers TestAttachToInlineText
434. `test_sidebar` — e2e — covers TestSidebar
435. `test_easings` — e2e — covers TestEasingAndLoop
436. `test_icon_rotates` — lui_paint — covers TestIconRotates
437. `test_image_gray` — lui_image — covers TestImageFitsAndGray (partially covered)
438. `test_debug_cursors` — e2e — covers TestDebugAndCursors
439. `test_cursor_clickable` — e2e — covers TestCursorStopsAtClickable
440. `test_theme_units` — lui_paint — covers TestThemeUnits
441. `test_table_sort` — e2e — covers TestTableSort
442. `test_table_resize` — e2e — covers TestTableResize
443. `test_table_reorder` — e2e — covers TestTableReorder
444. `test_table_reorder_far` — e2e — covers TestTableReorderFar
445. `test_table_scroll_sideways` — e2e — covers TestTableScrollsSideways
446. `test_table_editable` — e2e — covers TestEditableTextInTable
447. `test_editable_text` — e2e — covers TestEditableText
448. `test_table_round_rows` — e2e — covers TestTableRoundRows
449. `test_textarea_padding` — e2e — covers TestTextAreaShowsThroughPadding
450. `test_textarea_password` — e2e — covers TestTextAreaPassword
451. `test_textarea_in_form` — e2e — covers TestTextAreaInForm
452. `test_textarea_placeholder_height` — e2e — covers TestPlaceholderWithFixedLineHeight
453. `test_input_text_align` — e2e — covers TestInputTextAlign
454. `test_input_password_toggle` — e2e — covers TestInputPasswordToggles
455. `test_input_placeholder_line` — e2e — covers TestInputPlaceholderStaysOnItsLine
456. `test_input_start_unfocused` — e2e — covers TestInputShowsItsStartUnfocused
457. `test_theme_spacing` — e2e — covers TestSpacingScalesWidgets
458. `test_theme_inverse` — lui_paint — covers TestInverseColors
459. `test_inverse_fills` — e2e — covers TestInverseFillsTooltipsAndToasts
460. `test_toast_viewport` — e2e — covers TestToastViewportBase
461. `test_toast_manager` — e2e — covers TestToastManager
462. `test_toast_description` — e2e — covers TestToastDescription
463. `test_toast_exits` — e2e — covers TestToastExits
464. `test_segmented` — e2e — covers TestSegmented
465. `test_toolbar_overflow` — e2e — covers TestToolbarOverflows
466. `test_toolbar_enter_first` — e2e — covers TestToolbarEntersAtItsFirst
467. `test_tooltip_base` — e2e — covers TestTooltipBase
468. `test_tooltip_focus` — e2e — covers TestTooltipFocus
469. `test_tooltip_anchored` — e2e — covers TestTooltipAnchored
470. `test_tooltip_innermost` — e2e — covers TestTooltipInnermost
471. `test_transition_moves` — e2e — covers TestTransitionMovesElements
472. `test_transition_resizes` — e2e — covers TestTransitionResizesAndLaysOutContent
473. `test_transition_enter_exit` — e2e — covers TestTransitionEntersAndExits
474. `test_transition_fades` — e2e — covers TestTransitionFadesColors
475. `test_transition_no_motion` — e2e — covers TestTransitionWithoutMotion
476. `test_transition_dup_keys` — e2e — covers TestDuplicateKeys
477. `test_transition_dividers` — e2e — covers TestDividers
478. `test_transition_list_dividers` — e2e — covers TestListDividers
479. `test_transition_attach` — e2e — covers TestAttach
480. `test_transition_list_resize` — e2e — covers TestTransitionResizesAList
481. `test_recycled_state` — e2e — covers TestRecycledStateIsFresh
482. `test_theme_accent_oklch` — lui_paint — covers TestThemeAccentTakesOklch
483. `test_picture_wide` — lui_svg (new) — covers TestPictureOfAWideColor
484. `test_wide_frames_gpu` — lui_gpu — covers TestWideFramesOnGPU (partially covered)
485. `test_split` — e2e — covers TestSplit
486. `test_split_vertical` — e2e — covers TestSplitVertical
487. `test_number_input` — e2e — covers TestNumberInput
488. `test_toast` — e2e — covers TestToast
489. `test_table` — e2e — covers TestTable
490. `test_table_rows` — e2e — covers TestTableRows
491. `test_tree` — e2e — covers TestTree
492. `test_date_input` — e2e — covers TestDateInput
493. `test_date_input_wide` — e2e — covers TestDateInputWide
494. `test_progress_reverse` — lui_paint — covers TestProgressReverse (partially covered)
495. `test_tooltip_hides_press` — e2e — covers TestTooltipHidesOnPress
