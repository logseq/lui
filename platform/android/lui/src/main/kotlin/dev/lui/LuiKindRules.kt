package dev.lui

/** Kind-predicate helpers and the set-prop admissibility matrix, ported from
 * the Flutter backend's `_supports` so all backends accept/reject the same
 * wire. */
internal object LuiKindRules {

    val modalSurfaceKinds = setOf(LuiNodeKind.dialog, LuiNodeKind.sheet)

    val overlaySurfaceKinds = setOf(
        LuiNodeKind.panel,
        LuiNodeKind.card,
        LuiNodeKind.alert,
        LuiNodeKind.bubble,
        LuiNodeKind.resizable,
    )

    fun isModalSurface(kind: LuiNodeKind): Boolean = kind in modalSurfaceKinds

    // Kinds carrying typography/selectability — mirrors the
    // `FontSize | … | UserSelect` arm of `Lui_protocol.property_supported`:
    // the foreground set minus purely graphical kinds (icon, spinner,
    // file-image) whose `size` prop governs their metrics.
    fun isTextAppearanceKind(kind: LuiNodeKind): Boolean =
        kind == LuiNodeKind.edgeInset ||
            kind == LuiNodeKind.overlay ||
            kind == LuiNodeKind.viewThatFits ||
            kind == LuiNodeKind.text ||
            kind == LuiNodeKind.heading ||
            kind == LuiNodeKind.paragraph ||
            kind == LuiNodeKind.label ||
            kind == LuiNodeKind.row ||
            kind == LuiNodeKind.column ||
            kind == LuiNodeKind.grid ||
            kind == LuiNodeKind.box ||
            kind == LuiNodeKind.panel ||
            kind == LuiNodeKind.card ||
            kind == LuiNodeKind.stack ||
            kind == LuiNodeKind.scroll ||
            kind == LuiNodeKind.avatar ||
            kind == LuiNodeKind.popover ||
            isButtonKind(kind) ||
            isTextControl(kind) ||
            kind == LuiNodeKind.checkbox ||
            kind == LuiNodeKind.toggle ||
            kind == LuiNodeKind.radio ||
            kind == LuiNodeKind.slider ||
            kind == LuiNodeKind.numberStepper ||
            kind == LuiNodeKind.select ||
            kind == LuiNodeKind.dropdownMenu ||
            kind == LuiNodeKind.menuItem ||
            kind == LuiNodeKind.listItem ||
            kind == LuiNodeKind.tableCell ||
            kind == LuiNodeKind.resizable ||
            kind == LuiNodeKind.split ||
            kind == LuiNodeKind.alert ||
            kind == LuiNodeKind.bubble ||
            kind == LuiNodeKind.statusBar ||
            kind == LuiNodeKind.link

    fun isTextFlowKind(kind: LuiNodeKind): Boolean =
        kind == LuiNodeKind.text ||
            kind == LuiNodeKind.heading ||
            kind == LuiNodeKind.paragraph ||
            kind == LuiNodeKind.label ||
            kind == LuiNodeKind.button ||
            kind == LuiNodeKind.toggleButton ||
            kind == LuiNodeKind.menuItem ||
            kind == LuiNodeKind.listItem ||
            kind == LuiNodeKind.tableCell ||
            kind == LuiNodeKind.alert ||
            kind == LuiNodeKind.bubble ||
            kind == LuiNodeKind.statusBar ||
            kind == LuiNodeKind.link

    fun isPositionedKind(kind: LuiNodeKind): Boolean =
        kind != LuiNodeKind.root && kind != LuiNodeKind.tooltip && !isModalSurface(kind)

    fun isOverlaySurface(kind: LuiNodeKind): Boolean = kind in overlaySurfaceKinds

    fun isButtonKind(kind: LuiNodeKind): Boolean =
        kind == LuiNodeKind.button || kind == LuiNodeKind.toggleButton

    fun isHorizontalGroupKind(kind: LuiNodeKind): Boolean =
        kind == LuiNodeKind.tabs ||
            kind == LuiNodeKind.buttonGroup ||
            kind == LuiNodeKind.toggleGroup ||
            kind == LuiNodeKind.breadcrumb ||
            kind == LuiNodeKind.pagination

    fun horizontalGroupDefaultGap(kind: LuiNodeKind): Int =
        if (kind == LuiNodeKind.pagination) 2 else 4

    fun isMainCrossKind(kind: LuiNodeKind): Boolean =
        kind == LuiNodeKind.row ||
            kind == LuiNodeKind.column ||
            kind == LuiNodeKind.list ||
            kind == LuiNodeKind.virtualList ||
            kind == LuiNodeKind.card ||
            kind == LuiNodeKind.panel ||
            kind == LuiNodeKind.box ||
            kind == LuiNodeKind.button ||
            kind == LuiNodeKind.menuItem ||
            kind == LuiNodeKind.listItem ||
            kind == LuiNodeKind.popover ||
            kind == LuiNodeKind.link ||
            isHorizontalGroupKind(kind)

    fun isTreeRowKind(kind: LuiNodeKind): Boolean =
        kind == LuiNodeKind.row ||
            kind == LuiNodeKind.column ||
            kind == LuiNodeKind.panel ||
            kind == LuiNodeKind.card ||
            kind == LuiNodeKind.box ||
            kind == LuiNodeKind.listItem

    fun isTextControl(kind: LuiNodeKind): Boolean =
        kind == LuiNodeKind.textField ||
            kind == LuiNodeKind.secureField ||
            kind == LuiNodeKind.input ||
            kind == LuiNodeKind.searchField ||
            kind == LuiNodeKind.textarea ||
            kind == LuiNodeKind.combobox

    private val contextMenuLeafHosts = setOf(
        LuiNodeKind.button,
        LuiNodeKind.toggleButton,
        LuiNodeKind.toggle,
        LuiNodeKind.radio,
        LuiNodeKind.slider,
        LuiNodeKind.numberStepper,
        LuiNodeKind.textField,
        LuiNodeKind.secureField,
        LuiNodeKind.input,
        LuiNodeKind.searchField,
        LuiNodeKind.textarea,
        LuiNodeKind.checkbox,
        LuiNodeKind.switchControl,
        LuiNodeKind.select,
        LuiNodeKind.combobox,
        LuiNodeKind.menuItem,
        LuiNodeKind.text,
        LuiNodeKind.tableCell,
    )

    fun isContextMenuLeafHost(kind: LuiNodeKind): Boolean = kind in contextMenuLeafHosts

    fun isToolbarChild(kind: LuiNodeKind): Boolean =
        isButtonKind(kind) ||
            kind == LuiNodeKind.buttonGroup ||
            kind == LuiNodeKind.toggleGroup ||
            kind == LuiNodeKind.checkbox ||
            kind == LuiNodeKind.switchControl ||
            kind == LuiNodeKind.toggle ||
            kind == LuiNodeKind.radioGroup ||
            kind == LuiNodeKind.select ||
            kind == LuiNodeKind.combobox ||
            kind == LuiNodeKind.textField ||
            kind == LuiNodeKind.secureField ||
            kind == LuiNodeKind.input ||
            kind == LuiNodeKind.searchField ||
            kind == LuiNodeKind.menuItem ||
            kind == LuiNodeKind.menuTrigger ||
            kind == LuiNodeKind.spacer ||
            kind == LuiNodeKind.divider ||
            kind == LuiNodeKind.text

    fun canContainChildren(kind: LuiNodeKind): Boolean =
        kind == LuiNodeKind.root ||
            kind == LuiNodeKind.row ||
            kind == LuiNodeKind.column ||
            kind == LuiNodeKind.grid ||
            kind == LuiNodeKind.stack ||
            kind == LuiNodeKind.panel ||
            kind == LuiNodeKind.card ||
            kind == LuiNodeKind.box ||
            kind == LuiNodeKind.scroll ||
            kind == LuiNodeKind.list ||
            kind == LuiNodeKind.virtualList ||
            isHorizontalGroupKind(kind) ||
            kind == LuiNodeKind.radioGroup ||
            kind == LuiNodeKind.dropdownMenu ||
            kind == LuiNodeKind.contextMenu ||
            kind == LuiNodeKind.listItem ||
            kind == LuiNodeKind.accordion ||
            kind == LuiNodeKind.table ||
            kind == LuiNodeKind.tableRow ||
            kind == LuiNodeKind.tree ||
            kind == LuiNodeKind.resizable ||
            kind == LuiNodeKind.split ||
            kind == LuiNodeKind.drawer ||
            kind == LuiNodeKind.alert ||
            kind == LuiNodeKind.bubble ||
            kind == LuiNodeKind.stepper ||
            kind == LuiNodeKind.timeline ||
            kind == LuiNodeKind.inputGroup ||
            kind == LuiNodeKind.menuTrigger ||
            kind == LuiNodeKind.inputGroupActions ||
            kind == LuiNodeKind.toast ||
            kind == LuiNodeKind.toolbar ||
            kind == LuiNodeKind.bottomTabs ||
            kind == LuiNodeKind.bottomTab ||
            kind == LuiNodeKind.filePicker ||
            kind == LuiNodeKind.link ||
            isContextMenuLeafHost(kind) ||
            kind == LuiNodeKind.listSection ||
            kind == LuiNodeKind.listSectionHeader ||
            kind == LuiNodeKind.listSectionFooter ||
            kind == LuiNodeKind.swipeActions ||
            kind == LuiNodeKind.popover ||
            kind == LuiNodeKind.edgeInset ||
            kind == LuiNodeKind.overlay ||
            kind == LuiNodeKind.viewThatFits ||
            isModalSurface(kind)

    fun acceptsExtensionChildren(kind: LuiNodeKind): Boolean =
        kind == LuiNodeKind.root ||
            kind == LuiNodeKind.row ||
            kind == LuiNodeKind.column ||
            kind == LuiNodeKind.grid ||
            kind == LuiNodeKind.stack ||
            kind == LuiNodeKind.edgeInset ||
            kind == LuiNodeKind.overlay ||
            kind == LuiNodeKind.viewThatFits ||
            kind == LuiNodeKind.panel ||
            kind == LuiNodeKind.card ||
            kind == LuiNodeKind.box ||
            kind == LuiNodeKind.scroll ||
            kind == LuiNodeKind.list ||
            kind == LuiNodeKind.virtualList ||
            kind == LuiNodeKind.listItem ||
            kind == LuiNodeKind.dialog ||
            kind == LuiNodeKind.sheet ||
            kind == LuiNodeKind.accordion ||
            kind == LuiNodeKind.resizable ||
            kind == LuiNodeKind.split ||
            kind == LuiNodeKind.drawer ||
            kind == LuiNodeKind.alert ||
            kind == LuiNodeKind.bubble ||
            kind == LuiNodeKind.toast ||
            kind == LuiNodeKind.toolbar ||
            kind == LuiNodeKind.bottomTab ||
            kind == LuiNodeKind.listSection ||
            kind == LuiNodeKind.listSectionHeader ||
            kind == LuiNodeKind.listSectionFooter

    private val mainAlignments = setOf("start", "center", "end", "space_between")
    private val crossAlignments = setOf("stretch", "start", "center", "end")
    private val controlSizes = setOf("default", "sm", "lg", "icon")
    private val textSizes = setOf("heading", "display")
    private val textAlignments = setOf("start", "center", "end")
    private val themeModes = setOf("system", "light", "dark")
    private val wireProperties: Map<String, LuiProperty> =
        LuiProperty.entries.associateBy { it.wireName }
    private val containerRelativeFrames = setOf(
        "horizontal", "vertical", "both",
        "min-horizontal", "min-vertical", "min-both",
    )
    private val toolbarPlacements = setOf(
        "automatic", "bottom", "navigation", "principal",
        "primary-action", "secondary-action", "status",
        "confirmation-action", "cancellation-action",
        "destructive-action", "top-bar-leading", "top-bar-trailing",
    )
    private val buttonVariants =
        setOf("default", "primary", "secondary", "outline", "ghost", "destructive")
    private val overlayAlignments = setOf(
        "top-leading", "top", "top-trailing",
        "leading", "center", "trailing",
        "bottom-leading", "bottom", "bottom-trailing",
    )
    private val iconNames = setOf(
        "alert", "archive", "arrow-down", "arrow-right", "arrow-up",
        "check", "check-circle", "chevron-down", "chevron-left", "chevron-right",
        "chevron-up", "circle-dot", "clock", "copy", "download", "edit",
        "ellipsis", "external-link", "eye", "file-text", "folder", "folder-open",
        "git-branch", "git-merge", "git-pull-request", "info", "menu", "mic",
        "moon", "music", "panel-left", "panel-right", "pause", "play", "plus",
        "refresh-cw", "repeat", "save", "search", "send", "settings", "shuffle",
        "skip-back", "skip-forward", "sun", "terminal", "trash", "volume",
        "wrench", "x", "x-circle",
    )

    fun isIconName(value: String): Boolean =
        iconNames.contains(value) || isAppIconName(value)

    fun isAppIconName(value: String): Boolean {
        if (!value.startsWith("app:")) return false
        val name = value.substring(4)
        val segments = name.split('-')
        return segments.isNotEmpty() && segments.all { segment ->
            segment.isNotEmpty() && segment.all { it in 'a'..'z' || it in '0'..'9' }
        }
    }

    /** Ported from the Flutter backend's `_supports`: whether a `set-prop`
     * op is admissible for the node's kind. */
    fun supports(kind: LuiNodeKind, property: String, value: LuiWireValue): Boolean {
        // This host uses eager virtual_rows until it implements window feedback.
        when (property) {
            "virtual-total-count", "virtual-generation", "virtual-indices", "virtual-scroll-index" -> return false
            else -> Unit
        }
        if (property == "accessibility-identifier") return value is LuiWireValue.Str
        if (kind == LuiNodeKind.root) {
            return (property == "theme" && value is LuiWireValue.Str) ||
                (property == "theme-mode" && value.stringValue in themeModes)
        }
        if (kind == LuiNodeKind.contextMenu) return false
        // The pointer-detail family is opt-in via `pointer-enabled`, honored
        // on every kind that renders.
        if (property == "pointer-enabled") {
            return value is LuiWireValue.Bool &&
                kind != LuiNodeKind.root &&
                kind != LuiNodeKind.swipeActions
        }
        // Position hint honored on overlay children and the overlay itself.
        if (property == "alignment") {
            return kind != LuiNodeKind.root && value.stringValue in overlayAlignments
        }
        // Restrictive per-kind allow-lists come from schema/components.json
        // via LuiSchemaMatrix — the same source the Swift host consults.
        // Kinds absent from the table fall back to the shared structural
        // rules below.
        LuiSchemaMatrix.restrictive[kind]?.let { allowed ->
            val prop = wireProperties[property] ?: return false
            return prop in allowed && schemaValueSupported(property, value)
        }
        // Additive extras widen an otherwise schema-driven kind.
        if (LuiSchemaMatrix.extra[kind]?.contains(wireProperties[property]) == true) {
            return schemaValueSupported(property, value)
        }
        // Theme props are admitted on every non-restrictive container kind.
        if (property == "theme") {
            return value is LuiWireValue.Str && canContainChildren(kind)
        }
        if (property == "theme-mode") {
            return value.stringValue in themeModes && canContainChildren(kind)
        }
        return when (property) {
            "read-only" -> value is LuiWireValue.Bool && isTextControl(kind)
            "overscan" -> kind == LuiNodeKind.virtualList && value.intValue?.let { it >= 0 } == true
            "item-extent" -> kind == LuiNodeKind.virtualList && value.numberValue?.let { it.isFinite() && it > 0 } == true

            "main" ->
                value.stringValue in mainAlignments && isMainCrossKind(kind)
            "cross" ->
                value.stringValue in crossAlignments && isMainCrossKind(kind)
            "grow" ->
                value.numberValue?.let { it.isFinite() && it >= 0 } == true &&
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
            "columns" -> value.intValue?.let { it >= 0 } == true && kind == LuiNodeKind.grid
            "text" ->
                value is LuiWireValue.Str &&
                    (kind == LuiNodeKind.text ||
                        kind == LuiNodeKind.heading ||
                        kind == LuiNodeKind.paragraph ||
                        kind == LuiNodeKind.label ||
                        isButtonKind(kind) ||
                        isTextControl(kind) ||
                        kind == LuiNodeKind.checkbox ||
                        kind == LuiNodeKind.switchControl ||
                        kind == LuiNodeKind.toggle ||
                        kind == LuiNodeKind.radio ||
                        kind == LuiNodeKind.numberStepper ||
                        kind == LuiNodeKind.select ||
                        kind == LuiNodeKind.menuItem ||
                        kind == LuiNodeKind.menuTrigger ||
                        kind == LuiNodeKind.listItem ||
                        kind == LuiNodeKind.tableCell ||
                        kind == LuiNodeKind.avatar ||
                        kind == LuiNodeKind.tooltip ||
                        kind == LuiNodeKind.alert ||
                        kind == LuiNodeKind.bubble ||
                        kind == LuiNodeKind.statusBar ||
                        kind == LuiNodeKind.drawer ||
                        kind == LuiNodeKind.link ||
                        isModalSurface(kind))
            "enabled" ->
                value is LuiWireValue.Bool &&
                    (isButtonKind(kind) ||
                        isTextControl(kind) ||
                        kind == LuiNodeKind.checkbox ||
                        kind == LuiNodeKind.switchControl ||
                        kind == LuiNodeKind.toggle ||
                        kind == LuiNodeKind.radio ||
                        kind == LuiNodeKind.slider ||
                        kind == LuiNodeKind.numberStepper ||
                        kind == LuiNodeKind.select ||
                        kind == LuiNodeKind.menuItem ||
                        kind == LuiNodeKind.listItem ||
                        kind == LuiNodeKind.drawer ||
                        kind == LuiNodeKind.link)
            "value" ->
                value is LuiWireValue.DoubleValue &&
                    value.doubleValue?.isFinite() == true &&
                    (kind == LuiNodeKind.progress ||
                        kind == LuiNodeKind.slider ||
                        kind == LuiNodeKind.numberStepper ||
                        kind == LuiNodeKind.split)
            "min", "max" ->
                value.numberValue?.isFinite() == true && kind == LuiNodeKind.numberStepper
            "step" ->
                value.numberValue?.let { it.isFinite() && it > 0 } == true &&
                    kind == LuiNodeKind.numberStepper
            "detents" -> value is LuiWireValue.Str && kind == LuiNodeKind.sheet
            "sizing" ->
                value.stringValue in setOf("form", "fitted", "page") &&
                    kind == LuiNodeKind.sheet
            "resize-duration" ->
                value.intValue?.let { it >= 0 } == true && kind == LuiNodeKind.split
            "resize-easing" ->
                value.stringValue in setOf("linear", "standard", "emphasized", "spring") &&
                    kind == LuiNodeKind.split
            "resize-origin" ->
                value is LuiWireValue.DoubleValue &&
                    value.doubleValue?.isFinite() == true &&
                    kind == LuiNodeKind.split
            "orientation" ->
                (value.stringValue == "horizontal" || value.stringValue == "vertical") &&
                    (kind == LuiNodeKind.divider ||
                        kind == LuiNodeKind.tabs ||
                        kind == LuiNodeKind.scroll ||
                        kind == LuiNodeKind.viewThatFits)
            "size" ->
                (value.stringValue in controlSizes ||
                    (kind == LuiNodeKind.tableCell && value.stringValue in textSizes)) &&
                    (isButtonKind(kind) ||
                        kind == LuiNodeKind.spinner ||
                        kind == LuiNodeKind.icon ||
                        kind == LuiNodeKind.tableCell ||
                        kind == LuiNodeKind.menuItem)
            "name" ->
                value.stringValue?.let { isIconName(it) } == true && kind == LuiNodeKind.icon
            "variant" ->
                value.stringValue in buttonVariants &&
                    (isButtonKind(kind) ||
                        kind == LuiNodeKind.alert ||
                        kind == LuiNodeKind.bubble ||
                        kind == LuiNodeKind.menuItem)
            "icon" ->
                value.stringValue?.let { isIconName(it) } == true &&
                    (isButtonKind(kind) ||
                        kind == LuiNodeKind.menuItem ||
                        kind == LuiNodeKind.menuTrigger ||
                        kind == LuiNodeKind.listItem ||
                        kind == LuiNodeKind.link)
            "icon-placement" ->
                (value.stringValue == "leading" || value.stringValue == "trailing" ||
                    value.stringValue == "top") &&
                    (isButtonKind(kind) || kind == LuiNodeKind.link)
            "selected" ->
                value is LuiWireValue.Bool &&
                    (isButtonKind(kind) ||
                        kind == LuiNodeKind.menuItem ||
                        kind == LuiNodeKind.listItem ||
                        kind == LuiNodeKind.tableRow ||
                        kind == LuiNodeKind.virtualList ||
                        kind == LuiNodeKind.drawer ||
                        isTreeRowKind(kind))
            "long-press-enabled" ->
                value is LuiWireValue.Bool &&
                    (isButtonKind(kind) || kind == LuiNodeKind.listItem)
            "autofocus" ->
                value is LuiWireValue.Bool && (isButtonKind(kind) || isTextControl(kind))
            "submit-on-enter" -> value is LuiWireValue.Bool && kind == LuiNodeKind.textarea
            "change-enabled" ->
                value is LuiWireValue.Bool &&
                    (kind == LuiNodeKind.radio || isTextControl(kind) ||
                        kind == LuiNodeKind.slider || kind == LuiNodeKind.numberStepper ||
                        kind == LuiNodeKind.split || isTreeRowKind(kind))
            "toggle-enabled" ->
                value is LuiWireValue.Bool &&
                    (kind == LuiNodeKind.toggleButton || kind == LuiNodeKind.checkbox ||
                        kind == LuiNodeKind.switchControl || kind == LuiNodeKind.toggle ||
                        kind == LuiNodeKind.radio || kind == LuiNodeKind.accordion ||
                        kind == LuiNodeKind.drawer || isTreeRowKind(kind))
            "press-enabled" ->
                value is LuiWireValue.Bool &&
                    (kind == LuiNodeKind.button ||
                        kind == LuiNodeKind.toggleButton ||
                        kind == LuiNodeKind.text ||
                        kind == LuiNodeKind.row ||
                        kind == LuiNodeKind.column ||
                        kind == LuiNodeKind.box ||
                        kind == LuiNodeKind.radio ||
                        kind == LuiNodeKind.select ||
                        kind == LuiNodeKind.combobox ||
                        kind == LuiNodeKind.menuItem ||
                        kind == LuiNodeKind.listItem ||
                        kind == LuiNodeKind.tableCell ||
                        kind == LuiNodeKind.bottomTab ||
                        kind == LuiNodeKind.fileImage ||
                        isTreeRowKind(kind))
            "submit-enabled" ->
                value is LuiWireValue.Bool &&
                    (isTextControl(kind) || kind == LuiNodeKind.listItem)
            "double-press-enabled" ->
                value is LuiWireValue.Bool && kind == LuiNodeKind.listItem
            "appear-enabled" -> value is LuiWireValue.Bool
            "image" ->
                value.intValue?.let { it >= 0 } == true &&
                    (kind == LuiNodeKind.avatar || kind == LuiNodeKind.image)
            "surface" ->
                value.intValue?.let { it >= 0 } == true && kind == LuiNodeKind.mediaSurface
            "source-x", "source-y", "source-width", "source-height" ->
                value.numberValue?.isFinite() == true &&
                    (kind == LuiNodeKind.avatar || kind == LuiNodeKind.image)
            "path" -> value is LuiWireValue.Str && kind == LuiNodeKind.fileImage
            "url" ->
                value is LuiWireValue.Str &&
                    (kind == LuiNodeKind.link || kind == LuiNodeKind.image)
            "target" ->
                value.stringValue in setOf("_self", "_blank") && kind == LuiNodeKind.link
            "opacity" ->
                value.numberValue?.let { it >= 0 && it <= 1 } == true &&
                    canContainChildren(kind)
            "display" ->
                value.stringValue in setOf(
                    "contents", "none", "inline-flex", "block", "inline",
                    "inline-block",
                ) &&
                    (kind == LuiNodeKind.box ||
                        kind == LuiNodeKind.column ||
                        kind == LuiNodeKind.row)
            "flex-wrap" ->
                value.stringValue in setOf("nowrap", "wrap") &&
                    (kind == LuiNodeKind.box ||
                        kind == LuiNodeKind.column ||
                        kind == LuiNodeKind.row)
            "list-style" ->
                value.stringValue in setOf("none", "disc", "decimal") &&
                    (kind == LuiNodeKind.list ||
                        kind == LuiNodeKind.virtualList ||
                        kind == LuiNodeKind.listItem)
            "tooltip", "tooltip-keys" ->
                value is LuiWireValue.Str &&
                    (kind == LuiNodeKind.button ||
                        kind == LuiNodeKind.icon ||
                        kind == LuiNodeKind.menuItem)
            "input-type" ->
                (value.stringValue == "text" || value.stringValue == "color") &&
                    kind == LuiNodeKind.input
            "alt" -> value is LuiWireValue.Str && kind == LuiNodeKind.image
            "loading" ->
                value.stringValue in setOf("eager", "lazy") && kind == LuiNodeKind.image
            "referrer-policy" ->
                value.stringValue in setOf(
                    "no-referrer", "origin",
                    "strict-origin-when-cross-origin", "unsafe-url",
                ) && kind == LuiNodeKind.image
            "image-fit" ->
                (value.stringValue == "fit" || value.stringValue == "fill") &&
                    kind == LuiNodeKind.fileImage
            "max-pixel-size" ->
                value.intValue?.let { it > 0 } == true && kind == LuiNodeKind.fileImage
            "anchor" ->
                value.stringValue in setOf("above", "below", "left", "right") &&
                    (kind == LuiNodeKind.dropdownMenu ||
                        kind == LuiNodeKind.tooltip ||
                        kind == LuiNodeKind.popover)
            "anchor-alignment" ->
                value.stringValue in setOf("start", "end", "stretch") &&
                    (kind == LuiNodeKind.dropdownMenu ||
                        kind == LuiNodeKind.tooltip ||
                        kind == LuiNodeKind.popover)
            "anchor-offset" ->
                value.numberValue?.isFinite() == true &&
                    (kind == LuiNodeKind.dropdownMenu ||
                        kind == LuiNodeKind.tooltip ||
                        kind == LuiNodeKind.popover)
            "x", "y" ->
                value.numberValue?.isFinite() == true &&
                    (kind == LuiNodeKind.popover || kind == LuiNodeKind.dropdownMenu)
            "available-height" ->
                value.numberValue?.let { it.isFinite() && it >= 0 } == true &&
                    kind == LuiNodeKind.popover
            "edge" ->
                (value.stringValue in setOf("top", "bottom", "leading", "trailing") &&
                    kind == LuiNodeKind.edgeInset) ||
                    ((value.stringValue == "leading" || value.stringValue == "trailing") &&
                        kind == LuiNodeKind.swipeAction)
            "visible" -> value is LuiWireValue.Bool && kind == LuiNodeKind.edgeInset
            "alignment" -> value.stringValue in overlayAlignments
            "tooltip-delay" ->
                value.intValue?.let { it >= 0 } == true && kind == LuiNodeKind.tooltip
            "gap" ->
                value.intValue?.let { it >= 0 } == true &&
                    (kind == LuiNodeKind.row ||
                        kind == LuiNodeKind.column ||
                        kind == LuiNodeKind.grid ||
                        kind == LuiNodeKind.list ||
                        kind == LuiNodeKind.virtualList ||
                        kind == LuiNodeKind.dropdownMenu ||
                        kind == LuiNodeKind.popover ||
                        kind == LuiNodeKind.tableRow ||
                        kind == LuiNodeKind.tree ||
                        kind == LuiNodeKind.scroll ||
                        kind == LuiNodeKind.card ||
                        kind == LuiNodeKind.panel ||
                        kind == LuiNodeKind.box ||
                        kind == LuiNodeKind.split ||
                        kind == LuiNodeKind.edgeInset ||
                        isHorizontalGroupKind(kind))
            "padding" ->
                value is LuiWireValue.IntValue &&
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip
            // margins may be negative — collapsing adjacent space is legitimate
            "margin", "margin-horizontal", "margin-vertical",
            "margin-top", "margin-right", "margin-bottom", "margin-left" ->
                value.intValue != null &&
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip
            "padding-horizontal", "padding-vertical",
            "padding-top", "padding-right", "padding-bottom", "padding-left" ->
                value.intValue?.let { it >= 0 } == true &&
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip
            "background" ->
                value is LuiWireValue.Str &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
            "foreground" ->
                value is LuiWireValue.Str &&
                    (kind == LuiNodeKind.row ||
                        kind == LuiNodeKind.column ||
                        kind == LuiNodeKind.grid ||
                        kind == LuiNodeKind.box ||
                        kind == LuiNodeKind.panel ||
                        kind == LuiNodeKind.card ||
                        kind == LuiNodeKind.stack ||
                        kind == LuiNodeKind.scroll ||
                        kind == LuiNodeKind.avatar ||
                        kind == LuiNodeKind.edgeInset ||
                        kind == LuiNodeKind.overlay ||
                        kind == LuiNodeKind.viewThatFits ||
                        kind == LuiNodeKind.text ||
                        kind == LuiNodeKind.heading ||
                        kind == LuiNodeKind.paragraph ||
                        kind == LuiNodeKind.label ||
                        isButtonKind(kind) ||
                        isTextControl(kind) ||
                        kind == LuiNodeKind.checkbox ||
                        kind == LuiNodeKind.toggle ||
                        kind == LuiNodeKind.radio ||
                        kind == LuiNodeKind.slider ||
                        kind == LuiNodeKind.numberStepper ||
                        kind == LuiNodeKind.spinner ||
                        kind == LuiNodeKind.icon ||
                        kind == LuiNodeKind.select ||
                        kind == LuiNodeKind.dropdownMenu ||
                        kind == LuiNodeKind.menuItem ||
                        kind == LuiNodeKind.popover ||
                        kind == LuiNodeKind.menuTrigger ||
                        kind == LuiNodeKind.listItem ||
                        kind == LuiNodeKind.tableCell ||
                        kind == LuiNodeKind.resizable ||
                        kind == LuiNodeKind.split ||
                        kind == LuiNodeKind.alert ||
                        kind == LuiNodeKind.bubble ||
                        kind == LuiNodeKind.statusBar ||
                        kind == LuiNodeKind.link ||
                        kind == LuiNodeKind.fileImage)
            "border-color" ->
                value is LuiWireValue.Str &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
            "border-width" ->
                value.intValue?.let { it >= 0 } == true &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
            "corner-radius" ->
                value.intValue?.let { it >= 0 } == true &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
            "width", "height" ->
                value.intValue?.let { it >= 0 } == true &&
                    kind != LuiNodeKind.tooltip
            "min-width", "max-width", "min-height", "max-height" ->
                value.intValue?.let { it >= 0 } == true &&
                    (kind == LuiNodeKind.dialog ||
                        (!isModalSurface(kind) && kind != LuiNodeKind.tooltip))
            "style-class" ->
                value is LuiWireValue.Str &&
                    kind != LuiNodeKind.tooltip
            "data-attrs" ->
                value.stringValue?.let { dataAttrsValueOk(it) } == true &&
                    kind != LuiNodeKind.tooltip
            "as" ->
                value.stringValue?.let { elementTagSupported(kind, it) } == true
            "container-relative-frame" ->
                value.stringValue in containerRelativeFrames &&
                    kind != LuiNodeKind.root && !isModalSurface(kind)
            "container-relative-frame-inset" ->
                value.intValue?.let { it >= 0 } == true &&
                    kind != LuiNodeKind.root && !isModalSurface(kind)
            "checked" ->
                value is LuiWireValue.Bool &&
                    (kind == LuiNodeKind.checkbox ||
                        kind == LuiNodeKind.switchControl ||
                        kind == LuiNodeKind.toggle ||
                        kind == LuiNodeKind.radio)
            "heading-level" ->
                value.intValue?.let { it in 1..6 } == true && kind == LuiNodeKind.heading
            "placeholder" ->
                value is LuiWireValue.Str &&
                    (isTextControl(kind) || kind == LuiNodeKind.select)
            "accessibility-label" ->
                value is LuiWireValue.Str &&
                    (isButtonKind(kind) ||
                        isTextControl(kind) ||
                        kind == LuiNodeKind.checkbox ||
                        kind == LuiNodeKind.switchControl ||
                        kind == LuiNodeKind.toggle ||
                        kind == LuiNodeKind.radioGroup ||
                        kind == LuiNodeKind.tabs ||
                        kind == LuiNodeKind.buttonGroup ||
                        kind == LuiNodeKind.toggleGroup ||
                        kind == LuiNodeKind.breadcrumb ||
                        kind == LuiNodeKind.pagination ||
                        kind == LuiNodeKind.radio ||
                        kind == LuiNodeKind.slider ||
                        kind == LuiNodeKind.numberStepper ||
                        kind == LuiNodeKind.avatar ||
                        kind == LuiNodeKind.image ||
                        kind == LuiNodeKind.mediaSurface ||
                        kind == LuiNodeKind.tree ||
                        kind == LuiNodeKind.resizable ||
                        kind == LuiNodeKind.split ||
                        kind == LuiNodeKind.drawer ||
                        kind == LuiNodeKind.alert ||
                        kind == LuiNodeKind.bubble ||
                        kind == LuiNodeKind.select ||
                        kind == LuiNodeKind.menuTrigger ||
                        kind == LuiNodeKind.link ||
                        kind == LuiNodeKind.fileImage ||
                        isTreeRowKind(kind))
            "text-alignment" ->
                value.stringValue in textAlignments &&
                    (isButtonKind(kind) ||
                        kind == LuiNodeKind.text ||
                        kind == LuiNodeKind.tableCell ||
                        kind == LuiNodeKind.bubble ||
                        kind == LuiNodeKind.statusBar)
            "role" ->
                (value.stringValue == "treeitem" && isTreeRowKind(kind)) ||
                    (value.stringValue == "menu" && kind == LuiNodeKind.popover)
            "tree-level" ->
                value.intValue?.let { it > 0 } == true && isTreeRowKind(kind)
            "expanded" -> value is LuiWireValue.Bool && isTreeRowKind(kind)
            "key" ->
                value is LuiWireValue.Str &&
                    (kind == LuiNodeKind.listItem || kind == LuiNodeKind.listSection)
            "separator" ->
                (value.stringValue == "visible" || value.stringValue == "hidden") &&
                    (kind == LuiNodeKind.listItem || kind == LuiNodeKind.listSection)
            "style" ->
                value.stringValue in setOf("plain", "inset", "inset-grouped") &&
                    kind == LuiNodeKind.list
            "scroll-target" -> value is LuiWireValue.Str && kind == LuiNodeKind.list
            "scroll-anchor" ->
                value.stringValue in setOf("top", "center", "bottom") &&
                    kind == LuiNodeKind.list
            "scroll-token" ->
                value.intValue?.let { it >= 0 } == true && kind == LuiNodeKind.list
            "scroll-animated", "track-visible-range" ->
                value is LuiWireValue.Bool && kind == LuiNodeKind.list
            "font-size", "line-height", "font-family" ->
                value is LuiWireValue.Str &&
                    value.stringValue?.isNotBlank() == true &&
                    isTextAppearanceKind(kind)
            "text-decoration" ->
                value is LuiWireValue.Str &&
                    textDecorationSupported(value.stringValue) &&
                    isTextAppearanceKind(kind)
            "font-weight" ->
                value.intValue?.let { it in 1..1000 } == true &&
                    isTextAppearanceKind(kind)
            "letter-spacing" ->
                value.numberValue?.isFinite() == true && isTextAppearanceKind(kind)
            "font-style" ->
                value.stringValue in setOf("normal", "italic", "oblique") &&
                    isTextAppearanceKind(kind)
            "user-select" ->
                value.stringValue in setOf("none", "text") && isTextAppearanceKind(kind)
            "white-space" ->
                value.stringValue in setOf("normal", "nowrap") && isTextFlowKind(kind)
            "text-overflow" ->
                value.stringValue in setOf("clip", "ellipsis") && isTextFlowKind(kind)
            "overflow" ->
                value.stringValue in setOf("visible", "hidden", "auto") &&
                    canContainChildren(kind) &&
                    kind != LuiNodeKind.scroll &&
                    kind != LuiNodeKind.list &&
                    kind != LuiNodeKind.virtualList &&
                    kind != LuiNodeKind.tooltip
            "position" ->
                value.stringValue in setOf(
                    "static", "relative", "absolute", "fixed", "sticky",
                ) &&
                    isPositionedKind(kind)
            "inset", "inset-top", "inset-right", "inset-bottom", "inset-left" ->
                value.numberValue?.isFinite() == true && isPositionedKind(kind)
            "z-index" -> value is LuiWireValue.IntValue && isPositionedKind(kind)
            "cursor" ->
                value.stringValue in setOf("default", "pointer", "text") &&
                    kind != LuiNodeKind.root
            "shadow" ->
                value is LuiWireValue.Str &&
                    value.stringValue?.isNotBlank() == true &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
            "hover-background", "pressed-background", "selected-background",
            "hover-foreground", "hover-border",
            "hover-shadow", "pressed-shadow", "focus-shadow", "selected-shadow",
            "selected-hover-shadow" ->
                value is LuiWireValue.Str &&
                    value.stringValue?.isNotBlank() == true &&
                    isPositionedKind(kind)
            "hover-opacity", "pressed-opacity", "disabled-opacity" ->
                value.numberValue?.let { it.isFinite() && it >= 0 && it <= 1 } == true &&
                    isPositionedKind(kind)
            "transition" ->
                value is LuiWireValue.Str &&
                    transitionSupported(value.stringValue) &&
                    isPositionedKind(kind)
            "width-viewport", "height-viewport", "min-width-viewport",
            "max-width-viewport", "min-height-viewport", "max-height-viewport" ->
                value.numberValue?.let { it.isFinite() && it > 0 && it <= 1 } == true &&
                    kind != LuiNodeKind.tooltip
            else -> false
        }
    }

    // `transition` accepts a comma-separated list of
    // "<property> <duration> [<easing>] [<delay>]" segments — literally the
    // CSS shorthand, which the web backend emits verbatim; this host
    // applies state changes instantly, so the value is admission-checked
    // but never rendered. Commas inside easing parens do not split
    // segments. Mirrors `Lui_protocol.transition_supported`.
    private fun transitionSupported(value: String?): Boolean {
        if (value.isNullOrBlank()) return false
        var depth = 0
        val segments = mutableListOf<String>()
        var current = StringBuilder()
        for (c in value) {
            if (c == '(') depth += 1 else if (c == ')') depth = (depth - 1).coerceAtLeast(0)
            if (c == ',' && depth == 0) {
                segments.add(current.toString())
                current = StringBuilder()
            } else {
                current.append(c)
            }
        }
        segments.add(current.toString())
        return segments.all { segment ->
            val tokens = cssTokens(segment)
            val property = tokens.firstOrNull()
            if (property == null || tokens.size < 2 || !cssIdentSupported(property)) {
                false
            } else {
                val rest = tokens.drop(1)
                val times = rest.count { cssTimeSupported(it) }
                times in 1..2 &&
                    rest.all { token ->
                        cssTimeSupported(token) || run {
                            val open = token.indexOf('(')
                            if (open > 0 && token.length > open + 2 && token.endsWith(')')) {
                                cssIdentSupported(token.substring(0, open)) &&
                                    token.substring(open + 1, token.length - 1).isNotEmpty()
                            } else {
                                cssIdentSupported(token)
                            }
                        }
                    }
            }
        }
    }

    // CSS <ident>: `[-_a-zA-Z][-_a-zA-Z0-9]*` — a leading `-` needs a
    // letter, `_` or `-` next.
    private fun cssIdentSupported(value: String): Boolean {
        if (value.isEmpty()) return false
        val alpha = { c: Char -> c in 'a'..'z' || c in 'A'..'Z' || c == '_' }
        val headOk =
            alpha(value[0]) ||
                (value[0] == '-' && value.length > 1 && (alpha(value[1]) || value[1] == '-'))
        return headOk && value.drop(1).all { alpha(it) || it.isDigit() || it == '-' }
    }

    // CSS <time>: a non-negative number with an `s`/`ms` unit; a bare `0`
    // is also valid.
    private fun cssTimeSupported(token: String): Boolean {
        if (token == "0") return true
        val cut =
            when {
                token.length > 2 && token.endsWith("ms") -> 2
                token.length > 1 && token.endsWith("s") -> 1
                else -> return false
            }
        val number = token.dropLast(cut).toDoubleOrNull() ?: return false
        return number >= 0 && number.isFinite()
    }

    // Whitespace-separated tokens of a transition segment; parentheses
    // keep functional easing argument lists inside a single token.
    private fun cssTokens(value: String): List<String> {
        val tokens = mutableListOf<String>()
        var depth = 0
        var current = StringBuilder()
        for (c in value) {
            if ((c == ' ' || c == '\t' || c == '\n' || c == '\r') && depth == 0) {
                if (current.isNotEmpty()) {
                    tokens.add(current.toString())
                    current = StringBuilder()
                }
                continue
            }
            if (c == '(') depth += 1 else if (c == ')' && depth > 0) depth -= 1
            current.append(c)
        }
        if (current.isNotEmpty()) tokens.add(current.toString())
        return tokens
    }

    // `text-decoration` accepts "none" alone, or a space-separated
    // combination of underline/overline/line-through (mirrors the OCaml
    // `text_decoration_supported`).
    private fun textDecorationSupported(value: String?): Boolean {
        val tokens = value?.split(' ')?.filter { it.isNotBlank() } ?: return false
        if (tokens == listOf("none")) return true
        return tokens.isNotEmpty() &&
            "none" !in tokens &&
            tokens.all { it in setOf("underline", "line-through", "overline") }
    }

    // Value vocabulary for props admitted through the generated schema
    // matrix (restrictive kinds and additive extras), mirroring
    // `Lui_protocol.property_value_supported`.
    private fun schemaValueSupported(property: String, value: LuiWireValue): Boolean =
        when (property) {
            "virtual-total-count", "virtual-generation", "virtual-indices", "virtual-scroll-index" -> false
            "overscan" -> value.intValue?.let { it >= 0 } == true
            "item-extent" -> value.numberValue?.let { it.isFinite() && it > 0 } == true
            "text", "title", "description", "meta", "indicator", "key",
            "path", "style-class", "accessibility-label", "background",
            "foreground", "border-color", "types", "accept", "shadow",
            "hover-background", "hover-shadow", "pressed-background",
            "pressed-shadow", "focus-shadow", "selected-background",
            "selected-shadow", "selected-hover-shadow" -> value is LuiWireValue.Str
            "font-size", "line-height", "font-family" ->
                value.stringValue?.isNotBlank() == true
            "font-style" -> value.stringValue in setOf("normal", "italic", "oblique")
            "font-weight" -> value.intValue?.let { it in 1..1000 } == true
            "letter-spacing" -> value.numberValue?.isFinite() == true
            "text-decoration" -> textDecorationSupported(value.stringValue)
            "white-space" -> value.stringValue in setOf("normal", "nowrap", "pre-wrap")
            "text-overflow" -> value.stringValue in setOf("clip", "ellipsis")
            "text-alignment" -> value.stringValue in textAlignments
            "user-select" -> value.stringValue in setOf("none", "text")
            "cursor" -> value.stringValue in setOf("default", "pointer", "text")
            "data-attrs" -> value.stringValue?.let { dataAttrsValueOk(it) } == true
            "selected", "toggle-enabled", "enabled", "press-enabled",
            "connector", "multiple", "appear-enabled", "directory",
            "pointer-enabled", "read-only" -> value is LuiWireValue.Bool
            "height", "width", "min-width", "max-width", "min-height",
            "max-height", "active", "gap", "border-width", "corner-radius",
            "padding-horizontal", "padding-vertical",
            "padding-top", "padding-right", "padding-bottom", "padding-left", "duration" ->
                value.intValue?.let { it >= 0 } == true
            "padding" -> value is LuiWireValue.IntValue
            "margin", "margin-horizontal", "margin-vertical", "margin-top",
            "margin-right", "margin-bottom", "margin-left" -> value.intValue != null
            "grow" -> value.numberValue?.let { it.isFinite() && it >= 0 } == true
            "opacity", "hover-opacity", "pressed-opacity", "disabled-opacity" ->
                value.numberValue?.let { it >= 0 && it <= 1 } == true
            "icon" -> value.stringValue?.let { isIconName(it) } == true
            "variant" -> value.stringValue in buttonVariants
            "orientation" -> value.stringValue in setOf("horizontal", "vertical")
            "placement" -> value.stringValue in toolbarPlacements
            "separator" -> value.stringValue in setOf("visible", "hidden")
            "edge" -> value.stringValue in setOf("top", "bottom", "leading", "trailing")
            "request", "completion" ->
                value is LuiWireValue.Str || value is LuiWireValue.IntValue
            "source" -> value.stringValue in setOf("files", "photos", "camera")
            "transition" -> transitionSupported(value.stringValue)
            else -> false
        }

    // `data-attrs` payload: \u001e-separated `name\u001fvalue` records; each
    // name must be an aria-/data- attribute or one of the enumerated plain
    // names (mirrors `Lui_protocol.data_attrs_value_ok`).
    private fun dataAttrsValueOk(payload: String): Boolean {
        if (payload.isEmpty()) return true
        return payload.split('\u001e').all { record ->
            val parts = record.split('\u001f')
            parts.size == 2 && dataAttrNameOk(parts[0])
        }
    }

    private fun dataAttrNameOk(name: String): Boolean =
        name == "role" || name == "tabindex" || name == "draggable" ||
            name == "style" ||
            (name.length > 5 && (name.startsWith("data-") || name.startsWith("aria-")))

    // `as` retags a text-flow element; admissible tags are the ones
    // `Lui_protocol.element_tag_supported` lists per kind.
    private fun elementTagSupported(kind: LuiNodeKind, tag: String): Boolean =
        when (kind) {
            LuiNodeKind.text -> tag in setOf(
                "span", "em", "strong", "b", "i", "u", "s", "del", "mark",
                "small", "code", "kbd", "sub", "sup", "pre",
            )
            LuiNodeKind.heading -> tag in setOf("h1", "h2", "h3", "h4", "h5", "h6")
            LuiNodeKind.paragraph -> tag in setOf("p", "span", "div", "pre")
            LuiNodeKind.label -> tag in setOf("label", "span", "div")
            else -> false
        }
}
