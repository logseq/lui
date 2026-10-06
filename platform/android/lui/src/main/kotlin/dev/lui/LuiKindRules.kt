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

    fun isContextMenuLeafHost(kind: LuiNodeKind): Boolean = kind in setOf(
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
        if (kind == LuiNodeKind.filePreview) {
            return property == "path" && value is LuiWireValue.Str
        }
        if (kind == LuiNodeKind.accordion) {
            return when (property) {
                "text" -> value is LuiWireValue.Str
                "selected", "toggle-enabled" -> value is LuiWireValue.Bool
                "height" -> value.intValue?.let { it >= 0 } == true
                else -> false
            }
        }
        if (kind == LuiNodeKind.stepper) {
            return when (property) {
                "active" -> value.intValue?.let { it >= 0 } == true
                "accessibility-label" -> value is LuiWireValue.Str
                else -> false
            }
        }
        if (kind == LuiNodeKind.step) {
            return property == "text" && value is LuiWireValue.Str
        }
        if (kind == LuiNodeKind.timeline) {
            return when (property) {
                "gap" -> value.intValue?.let { it >= 0 } == true
                "grow" -> value.numberValue?.let { it.isFinite() && it >= 0 } == true
                "accessibility-label" -> value is LuiWireValue.Str
                else -> false
            }
        }
        if (kind == LuiNodeKind.timelineItem) {
            return when (property) {
                "title", "description", "meta", "indicator" -> value is LuiWireValue.Str
                "icon" -> value.stringValue?.let { isIconName(it) } == true
                "variant" -> value.stringValue in buttonVariants
                "connector", "selected", "press-enabled" -> value is LuiWireValue.Bool
                else -> false
            }
        }
        if (kind == LuiNodeKind.inputGroup) {
            return when (property) {
                "accessibility-label" -> value is LuiWireValue.Str
                "width", "height", "min-width" -> value.intValue?.let { it >= 0 } == true
                "grow" -> value.numberValue?.let { it.isFinite() && it >= 0 } == true
                else -> false
            }
        }
        if (kind == LuiNodeKind.inputGroupActions) {
            return property == "gap" && value.intValue?.let { it >= 0 } == true
        }
        if (kind == LuiNodeKind.toast) {
            return when (property) {
                "duration" -> value.intValue?.let { it >= 0 } == true
                "accessibility-label", "style-class" -> value is LuiWireValue.Str
                else -> false
            }
        }
        if (kind == LuiNodeKind.toolbar) {
            return when (property) {
                "orientation" -> value.stringValue == "horizontal" ||
                    value.stringValue == "vertical"
                "placement" -> value.stringValue in setOf(
                    "automatic", "bottom", "navigation", "principal",
                    "primary-action", "secondary-action", "status",
                    "confirmation-action", "cancellation-action",
                    "destructive-action", "top-bar-leading", "top-bar-trailing",
                )
                "gap" -> value.intValue?.let { it >= 0 } == true
                "accessibility-label", "style-class" -> value is LuiWireValue.Str
                else -> false
            }
        }
        if (kind == LuiNodeKind.bottomTabs) {
            return when (property) {
                "accessibility-label", "style-class" -> value is LuiWireValue.Str
                "grow" -> value.numberValue?.let { it.isFinite() && it >= 0 } == true
                "width", "height", "min-width", "max-width",
                "min-height", "max-height" -> value.intValue?.let { it >= 0 } == true
                else -> false
            }
        }
        if (kind == LuiNodeKind.bottomTab) {
            return when (property) {
                "title" -> value is LuiWireValue.Str
                "icon" -> value.stringValue?.let { isIconName(it) } == true
                "selected", "enabled", "press-enabled" -> value is LuiWireValue.Bool
                else -> false
            }
        }
        if (kind == LuiNodeKind.listSection) {
            return when (property) {
                "key" -> value is LuiWireValue.Str
                "separator" -> value.stringValue == "visible" || value.stringValue == "hidden"
                else -> false
            }
        }
        if (kind == LuiNodeKind.swipeActions) return false
        if (kind == LuiNodeKind.swipeAction) {
            return when (property) {
                "text", "background" -> value is LuiWireValue.Str
                "icon" -> value.stringValue?.let { isIconName(it) } == true
                "variant" -> value.stringValue in buttonVariants
                "edge" -> value.stringValue == "leading" || value.stringValue == "trailing"
                "enabled", "press-enabled" -> value is LuiWireValue.Bool
                else -> false
            }
        }
        if (kind == LuiNodeKind.filePicker) {
            return when (property) {
                "request", "completion" ->
                    value is LuiWireValue.Str || value is LuiWireValue.IntValue
                "types", "accept" -> value is LuiWireValue.Str
                "multiple", "enabled", "appear-enabled" -> value is LuiWireValue.Bool
                "directory" -> value is LuiWireValue.Bool
                "source" -> value.stringValue in setOf("files", "photos", "camera")
                else -> false
            }
        }
        // Theme props are admitted on every non-restrictive container kind.
        if (property == "theme") {
            return value is LuiWireValue.Str && canContainChildren(kind)
        }
        if (property == "theme-mode") {
            return value.stringValue in themeModes && canContainChildren(kind)
        }
        return when (property) {
            "main" ->
                value.stringValue in mainAlignments &&
                    (kind == LuiNodeKind.row ||
                        kind == LuiNodeKind.column ||
                        kind == LuiNodeKind.list ||
                        kind == LuiNodeKind.virtualList ||
                        isHorizontalGroupKind(kind))
            "cross" ->
                value.stringValue in crossAlignments &&
                    (kind == LuiNodeKind.row ||
                        kind == LuiNodeKind.column ||
                        kind == LuiNodeKind.list ||
                        kind == LuiNodeKind.virtualList ||
                        isHorizontalGroupKind(kind))
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
                    (kind == LuiNodeKind.radio || isTreeRowKind(kind))
            "toggle-enabled" ->
                value is LuiWireValue.Bool &&
                    (kind == LuiNodeKind.radio ||
                        kind == LuiNodeKind.drawer ||
                        isTreeRowKind(kind))
            "press-enabled" ->
                value is LuiWireValue.Bool &&
                    (kind == LuiNodeKind.text ||
                        kind == LuiNodeKind.column ||
                        kind == LuiNodeKind.radio ||
                        kind == LuiNodeKind.select ||
                        kind == LuiNodeKind.combobox ||
                        kind == LuiNodeKind.menuItem ||
                        kind == LuiNodeKind.listItem ||
                        kind == LuiNodeKind.tableCell ||
                        kind == LuiNodeKind.fileImage ||
                        isTreeRowKind(kind))
            "submit-enabled" ->
                value is LuiWireValue.Bool &&
                    (kind == LuiNodeKind.combobox || kind == LuiNodeKind.listItem)
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
                value.stringValue == "contents" &&
                    (kind == LuiNodeKind.box ||
                        kind == LuiNodeKind.column ||
                        kind == LuiNodeKind.row)
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
                value.numberValue?.isFinite() == true && kind == LuiNodeKind.popover
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
                        kind == LuiNodeKind.tableRow ||
                        kind == LuiNodeKind.tree ||
                        kind == LuiNodeKind.split ||
                        kind == LuiNodeKind.edgeInset ||
                        isHorizontalGroupKind(kind))
            "padding" ->
                value is LuiWireValue.IntValue &&
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip
            "padding-horizontal", "padding-vertical" ->
                value.intValue?.let { it >= 0 } == true &&
                    (kind == LuiNodeKind.row ||
                        kind == LuiNodeKind.column ||
                        kind == LuiNodeKind.grid ||
                        kind == LuiNodeKind.box)
            "background" ->
                value is LuiWireValue.Str &&
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
            "foreground" ->
                value is LuiWireValue.Str &&
                    (kind == LuiNodeKind.edgeInset ||
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
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
            "border-width" ->
                value.intValue?.let { it >= 0 } == true &&
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
            "corner-radius" ->
                value.intValue?.let { it >= 0 } == true &&
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
            "width", "height" ->
                value.intValue?.let { it >= 0 } == true &&
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip
            "min-width", "max-width", "min-height", "max-height" ->
                value.intValue?.let { it >= 0 } == true &&
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
            "style-class" ->
                value is LuiWireValue.Str &&
                    kind != LuiNodeKind.avatar &&
                    kind != LuiNodeKind.tooltip &&
                    !isModalSurface(kind)
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
            else -> false
        }
    }
}
