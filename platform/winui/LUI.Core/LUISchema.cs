// Port of src/lui_protocol.ml: kind/property support matrices, vocabulary
// checks, and per-node invariants. Keep the arms in sync with the OCaml
// source — test/property_matrix asserts the generator's matrices match it.

using System.Collections.Generic;

namespace LUI
{
    public enum LUIEventKind
    {
        Press,
        LongPress,
        TextChanged,
        Submit,
        ToggleChanged,
        Change,
        ValueChanged,
        Dismiss,
        DoublePress,
        Appear,
        Picked,
        Extension,
        ScrollCompleted,
        VisibleRange,
    }

    public static class LUISchema
    {
        public static bool ModalSurface(LUINodeKind kind) =>
            kind == LUINodeKind.Dialog ||
            kind == LUINodeKind.Drawer ||
            kind == LUINodeKind.Sheet;

        public static bool TreeRowKind(LUINodeKind kind) =>
            kind == LUINodeKind.Row ||
            kind == LUINodeKind.Column ||
            kind == LUINodeKind.Panel ||
            kind == LUINodeKind.Card ||
            kind == LUINodeKind.Box ||
            kind == LUINodeKind.ListItem;

        public static bool ContextMenuHostKind(LUINodeKind kind)
        {
            switch (kind)
            {
                case LUINodeKind.Button:
                case LUINodeKind.ToggleButton:
                case LUINodeKind.Toggle:
                case LUINodeKind.Radio:
                case LUINodeKind.Slider:
                case LUINodeKind.NumberStepper:
                case LUINodeKind.TextField:
                case LUINodeKind.SecureField:
                case LUINodeKind.Input:
                case LUINodeKind.SearchField:
                case LUINodeKind.Textarea:
                case LUINodeKind.Checkbox:
                case LUINodeKind.SwitchControl:
                case LUINodeKind.Select:
                case LUINodeKind.Combobox:
                case LUINodeKind.MenuItem:
                case LUINodeKind.ListItem:
                case LUINodeKind.Accordion:
                case LUINodeKind.Text:
                case LUINodeKind.TableCell:
                    return true;
                default:
                    return false;
            }
        }

        public static bool ContextMenuLeafHostKind(LUINodeKind kind)
        {
            switch (kind)
            {
                case LUINodeKind.Button:
                case LUINodeKind.ToggleButton:
                case LUINodeKind.Toggle:
                case LUINodeKind.Radio:
                case LUINodeKind.Slider:
                case LUINodeKind.NumberStepper:
                case LUINodeKind.TextField:
                case LUINodeKind.SecureField:
                case LUINodeKind.Input:
                case LUINodeKind.SearchField:
                case LUINodeKind.Textarea:
                case LUINodeKind.Checkbox:
                case LUINodeKind.SwitchControl:
                case LUINodeKind.Select:
                case LUINodeKind.Combobox:
                case LUINodeKind.MenuItem:
                case LUINodeKind.Text:
                case LUINodeKind.TableCell:
                    return true;
                default:
                    return false;
            }
        }

        public static bool HorizontalContainer(LUINodeKind kind) =>
            kind == LUINodeKind.Tabs ||
            kind == LUINodeKind.ButtonGroup ||
            kind == LUINodeKind.ToggleGroup ||
            kind == LUINodeKind.Breadcrumb ||
            kind == LUINodeKind.Pagination;

        public static bool ButtonKind(LUINodeKind kind) =>
            kind == LUINodeKind.Button || kind == LUINodeKind.ToggleButton;

        public static bool TextControlKind(LUINodeKind kind) =>
            kind == LUINodeKind.TextField ||
            kind == LUINodeKind.SecureField ||
            kind == LUINodeKind.Input ||
            kind == LUINodeKind.SearchField ||
            kind == LUINodeKind.Textarea ||
            kind == LUINodeKind.Combobox;

        public static bool ToolbarChildKind(LUINodeKind kind)
        {
            switch (kind)
            {
                case LUINodeKind.Button:
                case LUINodeKind.ToggleButton:
                case LUINodeKind.ButtonGroup:
                case LUINodeKind.ToggleGroup:
                case LUINodeKind.Checkbox:
                case LUINodeKind.SwitchControl:
                case LUINodeKind.Toggle:
                case LUINodeKind.RadioGroup:
                case LUINodeKind.Select:
                case LUINodeKind.Combobox:
                case LUINodeKind.TextField:
                case LUINodeKind.SecureField:
                case LUINodeKind.Input:
                case LUINodeKind.SearchField:
                case LUINodeKind.MenuItem:
                case LUINodeKind.Spacer:
                case LUINodeKind.Divider:
                case LUINodeKind.Text:
                    return true;
                default:
                    return false;
            }
        }

        public static bool EventSupported(LUINodeKind kind, LUIEventKind eventKind)
        {
            switch (eventKind)
            {
                case LUIEventKind.Press:
                    switch (kind)
                    {
                        case LUINodeKind.Button:
                        case LUINodeKind.Column:
                        case LUINodeKind.Radio:
                        case LUINodeKind.Select:
                        case LUINodeKind.Combobox:
                        case LUINodeKind.MenuItem:
                        case LUINodeKind.ListItem:
                        case LUINodeKind.Text:
                        case LUINodeKind.TableCell:
                        case LUINodeKind.TimelineItem:
                        case LUINodeKind.FileImage:
                        case LUINodeKind.BottomTab:
                        case LUINodeKind.SwipeAction:
                            return true;
                        default:
                            return false;
                    }
                case LUIEventKind.LongPress:
                    switch (kind)
                    {
                        case LUINodeKind.Button:
                        case LUINodeKind.ToggleButton:
                        case LUINodeKind.ListItem:
                            return true;
                        default:
                            return false;
                    }
                case LUIEventKind.TextChanged:
                    return TextControlKind(kind);
                case LUIEventKind.Submit:
                    switch (kind)
                    {
                        case LUINodeKind.TextField:
                        case LUINodeKind.SecureField:
                        case LUINodeKind.Input:
                        case LUINodeKind.SearchField:
                        case LUINodeKind.Textarea:
                        case LUINodeKind.Combobox:
                        case LUINodeKind.ListItem:
                            return true;
                        default:
                            return false;
                    }
                case LUIEventKind.ToggleChanged:
                    switch (kind)
                    {
                        case LUINodeKind.ToggleButton:
                        case LUINodeKind.Checkbox:
                        case LUINodeKind.SwitchControl:
                        case LUINodeKind.Toggle:
                        case LUINodeKind.Radio:
                        case LUINodeKind.Accordion:
                        case LUINodeKind.Drawer:
                        case LUINodeKind.ListItem:
                            return true;
                        default:
                            return false;
                    }
                case LUIEventKind.Change:
                    return kind == LUINodeKind.Radio;
                case LUIEventKind.ValueChanged:
                    return kind == LUINodeKind.Slider ||
                        kind == LUINodeKind.NumberStepper ||
                        kind == LUINodeKind.Split;
                case LUIEventKind.Dismiss:
                    switch (kind)
                    {
                        case LUINodeKind.Select:
                        case LUINodeKind.Combobox:
                        case LUINodeKind.DropdownMenu:
                        case LUINodeKind.Toast:
                        case LUINodeKind.Dialog:
                        case LUINodeKind.Drawer:
                        case LUINodeKind.Sheet:
                        case LUINodeKind.FilePicker:
                        case LUINodeKind.FilePreview:
                            return true;
                        default:
                            return false;
                    }
                case LUIEventKind.DoublePress:
                    return kind == LUINodeKind.ListItem;
                case LUIEventKind.Picked:
                    return kind == LUINodeKind.FilePicker;
                case LUIEventKind.Appear:
                    return kind != LUINodeKind.Root;
                case LUIEventKind.ScrollCompleted:
                case LUIEventKind.VisibleRange:
                    return kind == LUINodeKind.ListContainer;
                case LUIEventKind.Extension:
                    return false;
                default:
                    return false;
            }
        }

        public static bool TrueProperty(
            IReadOnlyDictionary<LUIProperty, LUIWireValue> properties,
            LUIProperty property) =>
            properties.TryGetValue(property, out LUIWireValue? value) &&
            value is LUIWireValue.Bool { Value: true };

        public static bool TreeitemProperties(
            IReadOnlyDictionary<LUIProperty, LUIWireValue> properties) =>
            properties.TryGetValue(LUIProperty.RoleValue, out LUIWireValue? value) &&
            value is LUIWireValue.String { Value: "treeitem" };

        public static bool EventSupportedForProperties(
            LUINodeKind kind,
            IReadOnlyDictionary<LUIProperty, LUIWireValue> properties,
            LUIEventKind eventKind)
        {
            if (eventKind == LUIEventKind.Appear &&
                TrueProperty(properties, LUIProperty.AppearEnabled))
            {
                return true;
            }
            if (TreeitemProperties(properties))
            {
                switch (eventKind)
                {
                    case LUIEventKind.Press:
                        return TrueProperty(properties, LUIProperty.PressEnabled);
                    case LUIEventKind.Change:
                        return TrueProperty(properties, LUIProperty.ChangeEnabled);
                    case LUIEventKind.ToggleChanged:
                        return TrueProperty(properties, LUIProperty.ToggleEnabled);
                    default:
                        return EventSupported(kind, eventKind);
                }
            }
            return EventSupported(kind, eventKind);
        }

        public static bool ContainerRelativeFrameSupported(string value) =>
            value == "horizontal" || value == "vertical" || value == "both" ||
            value == "min-horizontal" || value == "min-vertical" ||
            value == "min-both";

        public static bool OrientationSupported(string value) =>
            value == "horizontal" || value == "vertical";

        public static bool PlacementSupported(string value) =>
            value == "automatic" || value == "bottom" || value == "navigation" ||
            value == "principal" || value == "primary-action" ||
            value == "secondary-action" || value == "status" ||
            value == "confirmation-action" || value == "cancellation-action" ||
            value == "destructive-action" || value == "top-bar-leading" ||
            value == "top-bar-trailing";

        public static bool ControlSizeSupported(string value) =>
            value == "default" || value == "sm" || value == "lg" ||
            value == "icon";

        public static bool ButtonVariantSupported(string value) =>
            value == "default" || value == "primary" || value == "secondary" ||
            value == "outline" || value == "ghost" || value == "destructive";

        public static bool IconPlacementSupported(string value) =>
            value == "leading" || value == "trailing" || value == "top";

        public static bool BuiltInIconNameSupported(string value)
        {
            switch (value)
            {
                case "alert":
                case "archive":
                case "arrow-down":
                case "arrow-right":
                case "arrow-up":
                case "check":
                case "check-circle":
                case "chevron-down":
                case "chevron-left":
                case "chevron-right":
                case "chevron-up":
                case "circle-dot":
                case "clock":
                case "copy":
                case "download":
                case "edit":
                case "ellipsis":
                case "external-link":
                case "eye":
                case "file-text":
                case "folder":
                case "folder-open":
                case "git-branch":
                case "git-merge":
                case "git-pull-request":
                case "info":
                case "menu":
                case "mic":
                case "moon":
                case "music":
                case "panel-left":
                case "panel-right":
                case "pause":
                case "play":
                case "plus":
                case "refresh-cw":
                case "repeat":
                case "save":
                case "search":
                case "send":
                case "settings":
                case "shuffle":
                case "skip-back":
                case "skip-forward":
                case "sun":
                case "terminal":
                case "trash":
                case "volume":
                case "wrench":
                case "x":
                case "x-circle":
                    return true;
                default:
                    return false;
            }
        }

        static bool SlugSegment(string value)
        {
            // matches [a-z0-9]+(-[a-z0-9]+)*
            static bool SlugChar(char c) =>
                (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
            int n = value.Length;
            if (n == 0 || !SlugChar(value[0]) || !SlugChar(value[n - 1]))
            {
                return false;
            }
            for (int i = 0; i < n; i++)
            {
                if (SlugChar(value[i])) continue;
                // a '-' must be followed by a slug char; the final char is
                // known to be one, so i + 1 < n here
                if (value[i] != '-' || !SlugChar(value[i + 1])) return false;
            }
            return true;
        }

        public static bool CustomIconNameSupported(string value)
        {
            const string prefix = "app:";
            return value.Length > prefix.Length &&
                value.StartsWith(prefix, System.StringComparison.Ordinal) &&
                SlugSegment(value.Substring(prefix.Length));
        }

        public static bool IconNameSupported(string value) =>
            BuiltInIconNameSupported(value) || CustomIconNameSupported(value);

        public static bool MainAlignmentSupported(string value) =>
            value == "start" || value == "center" || value == "end" ||
            value == "space_between";

        public static bool CrossAlignmentSupported(string value) =>
            value == "stretch" || value == "start" || value == "center" ||
            value == "end";

        public static bool CommonPropertySupported(
            LUINodeKind kind, LUIProperty property)
        {
            switch (property)
            {
                case LUIProperty.MainAlignment:
                case LUIProperty.CrossAlignment:
                    return kind == LUINodeKind.Row ||
                        kind == LUINodeKind.Column ||
                        kind == LUINodeKind.ListContainer ||
                        kind == LUINodeKind.VirtualList ||
                        kind == LUINodeKind.Card ||
                        kind == LUINodeKind.Panel ||
                        kind == LUINodeKind.Box ||
                        HorizontalContainer(kind);
                case LUIProperty.GrowValue:
                    return kind != LUINodeKind.Avatar && !ModalSurface(kind) &&
                        kind != LUINodeKind.Tooltip;
                case LUIProperty.GridColumns:
                    return kind == LUINodeKind.Grid;
                case LUIProperty.PaddingValue:
                    return kind != LUINodeKind.Avatar &&
                        kind != LUINodeKind.Tooltip;
                case LUIProperty.PaddingHorizontal:
                    return kind == LUINodeKind.Row ||
                        kind == LUINodeKind.Column ||
                        kind == LUINodeKind.Grid ||
                        kind == LUINodeKind.Box ||
                        kind == LUINodeKind.Button ||
                        kind == LUINodeKind.Card ||
                        kind == LUINodeKind.Panel ||
                        kind == LUINodeKind.Scroll;
                case LUIProperty.PaddingVertical:
                    return kind == LUINodeKind.Row ||
                        kind == LUINodeKind.Column ||
                        kind == LUINodeKind.Grid ||
                        kind == LUINodeKind.Box ||
                        kind == LUINodeKind.Card ||
                        kind == LUINodeKind.Panel ||
                        kind == LUINodeKind.Scroll;
                case LUIProperty.BackgroundValue:
                case LUIProperty.BorderColorValue:
                case LUIProperty.BorderWidth:
                case LUIProperty.CornerRadius:
                    return !ModalSurface(kind) && kind != LUINodeKind.Tooltip;
                case LUIProperty.ForegroundValue:
                    switch (kind)
                    {
                        case LUINodeKind.Row:
                        case LUINodeKind.Column:
                        case LUINodeKind.Grid:
                        case LUINodeKind.Box:
                        case LUINodeKind.Panel:
                        case LUINodeKind.Card:
                        case LUINodeKind.Stack:
                        case LUINodeKind.Scroll:
                        case LUINodeKind.Avatar:
                        case LUINodeKind.EdgeInset:
                        case LUINodeKind.Overlay:
                        case LUINodeKind.ViewThatFits:
                        case LUINodeKind.Text:
                        case LUINodeKind.Heading:
                        case LUINodeKind.Paragraph:
                        case LUINodeKind.Label:
                        case LUINodeKind.Button:
                        case LUINodeKind.ToggleButton:
                        case LUINodeKind.TextField:
                        case LUINodeKind.SecureField:
                        case LUINodeKind.Input:
                        case LUINodeKind.SearchField:
                        case LUINodeKind.Textarea:
                        case LUINodeKind.Checkbox:
                        case LUINodeKind.Toggle:
                        case LUINodeKind.Radio:
                        case LUINodeKind.Slider:
                        case LUINodeKind.NumberStepper:
                        case LUINodeKind.Spinner:
                        case LUINodeKind.Icon:
                        case LUINodeKind.Select:
                        case LUINodeKind.Combobox:
                        case LUINodeKind.DropdownMenu:
                        case LUINodeKind.MenuItem:
                        case LUINodeKind.ListItem:
                        case LUINodeKind.TableCell:
                        case LUINodeKind.Resizable:
                        case LUINodeKind.Split:
                        case LUINodeKind.Alert:
                        case LUINodeKind.Bubble:
                        case LUINodeKind.StatusBar:
                        case LUINodeKind.Link:
                        case LUINodeKind.FileImage:
                            return true;
                        default:
                            return false;
                    }
                case LUIProperty.WidthValue:
                case LUIProperty.HeightValue:
                    return kind != LUINodeKind.Tooltip;
                case LUIProperty.MinWidth:
                case LUIProperty.MaxWidth:
                case LUIProperty.MinHeight:
                case LUIProperty.MaxHeight:
                    return !ModalSurface(kind) && kind != LUINodeKind.Tooltip;
                case LUIProperty.ContainerRelativeFrameValue:
                case LUIProperty.ContainerRelativeFrameInset:
                    return kind != LUINodeKind.Root && !ModalSurface(kind);
                case LUIProperty.StyleClass:
                    return kind != LUINodeKind.Tooltip;
                case LUIProperty.AccessibilityLabel:
                    return kind == LUINodeKind.Button ||
                        kind == LUINodeKind.ToggleButton ||
                        kind == LUINodeKind.Select ||
                        kind == LUINodeKind.TextField ||
                        kind == LUINodeKind.SecureField ||
                        kind == LUINodeKind.Input ||
                        kind == LUINodeKind.SearchField ||
                        kind == LUINodeKind.Textarea ||
                        kind == LUINodeKind.Checkbox ||
                        kind == LUINodeKind.SwitchControl ||
                        kind == LUINodeKind.Toggle ||
                        kind == LUINodeKind.RadioGroup ||
                        kind == LUINodeKind.Radio ||
                        kind == LUINodeKind.Slider ||
                        kind == LUINodeKind.NumberStepper ||
                        HorizontalContainer(kind) ||
                        kind == LUINodeKind.Avatar ||
                        kind == LUINodeKind.Image ||
                        kind == LUINodeKind.MediaSurface ||
                        kind == LUINodeKind.Tree ||
                        kind == LUINodeKind.Resizable ||
                        kind == LUINodeKind.Split ||
                        kind == LUINodeKind.Drawer ||
                        kind == LUINodeKind.Alert ||
                        kind == LUINodeKind.Bubble ||
                        kind == LUINodeKind.ListItem ||
                        kind == LUINodeKind.Link ||
                        kind == LUINodeKind.FileImage ||
                        TreeRowKind(kind);
                case LUIProperty.AccessibilityIdentifier:
                    return true;
                case LUIProperty.PlaceholderValue:
                    return kind == LUINodeKind.TextField ||
                        kind == LUINodeKind.SecureField ||
                        kind == LUINodeKind.Input ||
                        kind == LUINodeKind.SearchField ||
                        kind == LUINodeKind.Textarea ||
                        kind == LUINodeKind.Select ||
                        kind == LUINodeKind.Combobox;
                case LUIProperty.HeadingLevel:
                    return kind == LUINodeKind.Heading;
                case LUIProperty.Checked:
                    return kind == LUINodeKind.Checkbox ||
                        kind == LUINodeKind.SwitchControl ||
                        kind == LUINodeKind.Toggle ||
                        kind == LUINodeKind.Radio;
                case LUIProperty.ProgressValue:
                    return kind == LUINodeKind.Progress ||
                        kind == LUINodeKind.Slider ||
                        kind == LUINodeKind.NumberStepper ||
                        kind == LUINodeKind.Split;
                case LUIProperty.OrientationValue:
                    return kind == LUINodeKind.Divider ||
                        kind == LUINodeKind.Tabs ||
                        kind == LUINodeKind.Scroll ||
                        kind == LUINodeKind.ViewThatFits;
                case LUIProperty.PlacementValue:
                    return kind == LUINodeKind.Toolbar;
                case LUIProperty.SizeValue:
                    return kind == LUINodeKind.Button ||
                        kind == LUINodeKind.ToggleButton ||
                        kind == LUINodeKind.Spinner ||
                        kind == LUINodeKind.Icon ||
                        kind == LUINodeKind.TableCell ||
                        kind == LUINodeKind.MenuItem;
                case LUIProperty.IconName:
                    return kind == LUINodeKind.Icon;
                case LUIProperty.VariantValue:
                    return kind == LUINodeKind.Button ||
                        kind == LUINodeKind.ToggleButton ||
                        kind == LUINodeKind.MenuItem ||
                        kind == LUINodeKind.Alert ||
                        kind == LUINodeKind.Bubble;
                case LUIProperty.InlineIconName:
                    return kind == LUINodeKind.Button ||
                        kind == LUINodeKind.ToggleButton ||
                        kind == LUINodeKind.MenuItem ||
                        kind == LUINodeKind.ListItem ||
                        kind == LUINodeKind.BottomTab ||
                        kind == LUINodeKind.Link;
                case LUIProperty.IconPlacementValue:
                    return kind == LUINodeKind.Button ||
                        kind == LUINodeKind.ToggleButton ||
                        kind == LUINodeKind.ListItem ||
                        kind == LUINodeKind.Link;
                case LUIProperty.Selected:
                    return kind == LUINodeKind.Button ||
                        kind == LUINodeKind.ToggleButton ||
                        kind == LUINodeKind.MenuItem ||
                        kind == LUINodeKind.ListItem ||
                        kind == LUINodeKind.TableRow ||
                        kind == LUINodeKind.Drawer ||
                        kind == LUINodeKind.BottomTab ||
                        kind == LUINodeKind.VirtualList ||
                        TreeRowKind(kind);
                case LUIProperty.Autofocus:
                    return kind == LUINodeKind.Button ||
                        kind == LUINodeKind.ToggleButton ||
                        kind == LUINodeKind.TextField ||
                        kind == LUINodeKind.SecureField ||
                        kind == LUINodeKind.Input ||
                        kind == LUINodeKind.SearchField ||
                        kind == LUINodeKind.Textarea;
                case LUIProperty.SubmitOnEnter:
                    return kind == LUINodeKind.Textarea;
                case LUIProperty.LongPressEnabled:
                    return kind == LUINodeKind.Button ||
                        kind == LUINodeKind.ToggleButton ||
                        kind == LUINodeKind.ListItem;
                case LUIProperty.ChangeEnabled:
                    return kind == LUINodeKind.Radio || TreeRowKind(kind);
                case LUIProperty.ToggleEnabled:
                    return kind == LUINodeKind.Radio ||
                        kind == LUINodeKind.Drawer || TreeRowKind(kind);
                case LUIProperty.PressEnabled:
                    return kind == LUINodeKind.Text ||
                        kind == LUINodeKind.Column ||
                        kind == LUINodeKind.Radio ||
                        kind == LUINodeKind.Select ||
                        kind == LUINodeKind.Combobox ||
                        kind == LUINodeKind.MenuItem ||
                        kind == LUINodeKind.ListItem ||
                        kind == LUINodeKind.TableCell ||
                        kind == LUINodeKind.BottomTab ||
                        kind == LUINodeKind.FileImage ||
                        TreeRowKind(kind);
                case LUIProperty.SubmitEnabled:
                    return kind == LUINodeKind.Combobox ||
                        kind == LUINodeKind.ListItem;
                case LUIProperty.DoublePressEnabled:
                    return kind == LUINodeKind.ListItem;
                case LUIProperty.AppearEnabled:
                    return kind != LUINodeKind.Root;
                case LUIProperty.ImageIdValue:
                case LUIProperty.SourceX:
                case LUIProperty.SourceY:
                case LUIProperty.SourceWidth:
                case LUIProperty.SourceHeight:
                    return kind == LUINodeKind.Avatar ||
                        kind == LUINodeKind.Image;
                case LUIProperty.SurfaceIdValue:
                    return kind == LUINodeKind.MediaSurface;
                case LUIProperty.PathValue:
                    return kind == LUINodeKind.FileImage ||
                        kind == LUINodeKind.FilePreview;
                case LUIProperty.UrlValue:
                    return kind == LUINodeKind.Link;
                case LUIProperty.MaxPixelSize:
                    return kind == LUINodeKind.FileImage;
                case LUIProperty.AnchorValue:
                case LUIProperty.AnchorAlignmentValue:
                case LUIProperty.AnchorOffset:
                    return kind == LUINodeKind.DropdownMenu ||
                        kind == LUINodeKind.Tooltip;
                case LUIProperty.TooltipDelay:
                    return kind == LUINodeKind.Tooltip;
                case LUIProperty.DurationValue:
                    return false;
                case LUIProperty.TextAlignment:
                    return kind == LUINodeKind.Text ||
                        kind == LUINodeKind.Button ||
                        kind == LUINodeKind.ToggleButton ||
                        kind == LUINodeKind.TableCell ||
                        kind == LUINodeKind.Bubble ||
                        kind == LUINodeKind.StatusBar;
                case LUIProperty.RoleValue:
                    return TreeRowKind(kind) || kind == LUINodeKind.ListItem;
                case LUIProperty.TreeLevel:
                case LUIProperty.Expanded:
                    return TreeRowKind(kind);
                case LUIProperty.ResizeDuration:
                case LUIProperty.ResizeEasing:
                case LUIProperty.ResizeOrigin:
                    return kind == LUINodeKind.Split;
                case LUIProperty.KeyValue:
                case LUIProperty.SeparatorValue:
                    return kind == LUINodeKind.ListItem ||
                        kind == LUINodeKind.ListSection;
                case LUIProperty.StyleValue:
                case LUIProperty.ScrollTarget:
                case LUIProperty.ScrollAnchor:
                case LUIProperty.ScrollToken:
                case LUIProperty.ScrollAnimated:
                case LUIProperty.TrackVisibleRange:
                    return kind == LUINodeKind.ListContainer;
                case LUIProperty.EdgeValue:
                    return kind == LUINodeKind.SwipeAction;
                case LUIProperty.MinValue:
                case LUIProperty.MaxValue:
                case LUIProperty.StepValue:
                    return kind == LUINodeKind.NumberStepper;
                case LUIProperty.Detents:
                case LUIProperty.Sizing:
                    return kind == LUINodeKind.Sheet;
                case LUIProperty.ThemeValue:
                case LUIProperty.ThemeMode:
                    return CanContainChildren(kind);
                case LUIProperty.EdgeValue:
                case LUIProperty.Visible:
                    return kind == LUINodeKind.EdgeInset;
                // AlignmentValue is admitted ahead of the restrictive matrix
                // in PropertySupported.
                case LUIProperty.AlignmentValue:
                    return kind != LUINodeKind.Root;
                case LUIProperty.TextValue:
                    switch (kind)
                    {
                        case LUINodeKind.Text:
                        case LUINodeKind.Heading:
                        case LUINodeKind.Paragraph:
                        case LUINodeKind.Label:
                        case LUINodeKind.Button:
                        case LUINodeKind.ToggleButton:
                        case LUINodeKind.TextField:
                        case LUINodeKind.SecureField:
                        case LUINodeKind.Input:
                        case LUINodeKind.SearchField:
                        case LUINodeKind.Textarea:
                        case LUINodeKind.Checkbox:
                        case LUINodeKind.SwitchControl:
                        case LUINodeKind.Toggle:
                        case LUINodeKind.Radio:
                        case LUINodeKind.Select:
                        case LUINodeKind.Combobox:
                        case LUINodeKind.MenuItem:
                        case LUINodeKind.ListItem:
                        case LUINodeKind.Avatar:
                        case LUINodeKind.Dialog:
                        case LUINodeKind.Drawer:
                        case LUINodeKind.Sheet:
                        case LUINodeKind.Tooltip:
                        case LUINodeKind.NumberStepper:
                        case LUINodeKind.TableCell:
                        case LUINodeKind.Alert:
                        case LUINodeKind.Bubble:
                        case LUINodeKind.StatusBar:
                        case LUINodeKind.Link:
                            return true;
                        default:
                            return false;
                    }
                case LUIProperty.Enabled:
                    switch (kind)
                    {
                        case LUINodeKind.Button:
                        case LUINodeKind.ToggleButton:
                        case LUINodeKind.TextField:
                        case LUINodeKind.SecureField:
                        case LUINodeKind.Input:
                        case LUINodeKind.SearchField:
                        case LUINodeKind.Textarea:
                        case LUINodeKind.Checkbox:
                        case LUINodeKind.SwitchControl:
                        case LUINodeKind.Toggle:
                        case LUINodeKind.Radio:
                        case LUINodeKind.Slider:
                        case LUINodeKind.NumberStepper:
                        case LUINodeKind.Select:
                        case LUINodeKind.Combobox:
                        case LUINodeKind.MenuItem:
                        case LUINodeKind.ListItem:
                        case LUINodeKind.Drawer:
                        case LUINodeKind.BottomTab:
                        case LUINodeKind.Link:
                            return true;
                        default:
                            return false;
                    }
                case LUIProperty.ActiveIndex:
                case LUIProperty.DescriptionValue:
                case LUIProperty.MetaValue:
                case LUIProperty.IndicatorValue:
                case LUIProperty.Connector:
                    return false;
                case LUIProperty.TitleValue:
                    return kind == LUINodeKind.BottomTab;
                case LUIProperty.Gap:
                    return kind == LUINodeKind.Row ||
                        kind == LUINodeKind.Column ||
                        kind == LUINodeKind.Grid ||
                        kind == LUINodeKind.ListContainer ||
                        kind == LUINodeKind.VirtualList ||
                        kind == LUINodeKind.DropdownMenu ||
                        kind == LUINodeKind.TableRow ||
                        kind == LUINodeKind.Tree ||
                        kind == LUINodeKind.Scroll ||
                        kind == LUINodeKind.Card ||
                        kind == LUINodeKind.Panel ||
                        kind == LUINodeKind.Box ||
                        kind == LUINodeKind.Split ||
                        kind == LUINodeKind.EdgeInset ||
                        HorizontalContainer(kind);
                default:
                    return false;
            }
        }

        public static bool PropertySupported(
            LUINodeKind kind, LUIProperty property)
        {
            if (property == LUIProperty.AccessibilityIdentifier) return true;
            // Position hint honored on overlay children and the overlay
            // itself; admitted before the restrictive matrix so e.g. an
            // aligned menu-trigger child still carries it. Inert elsewhere.
            if (property == LUIProperty.AlignmentValue)
                return kind != LUINodeKind.Root;
            // The restrictive arms mirror schema/components.json
            // kindProperties; test/property_matrix asserts the two stay in
            // sync. LUIWireSchema.RestrictiveMatrix is generated from it.
            switch (kind)
            {
                case LUINodeKind.Root:
                    return property == LUIProperty.ThemeValue ||
                        property == LUIProperty.ThemeMode;
                case LUINodeKind.ContextMenu:
                    return false;
                case LUINodeKind.Dialog:
                    return property == LUIProperty.DescriptionValue ||
                        CommonPropertySupported(kind, property);
                default:
                    if (LUIWireSchema.RestrictiveMatrix.TryGetValue(
                            kind, out IReadOnlySet<LUIProperty>? allowed))
                    {
                        return allowed.Contains(property);
                    }
                    return CommonPropertySupported(kind, property);
            }
        }

        static bool IsFinite(double value) =>
            !double.IsNaN(value) && !double.IsInfinity(value);

        public static bool PropertyValueSupported(
            LUIProperty property, LUIWireValue value)
        {
            switch (property)
            {
                case LUIProperty.TextValue:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.Enabled:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.Gap:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.MainAlignment:
                {
                    return value is LUIWireValue.String text &&
                        MainAlignmentSupported(text.Value);
                }
                case LUIProperty.CrossAlignment:
                {
                    return value is LUIWireValue.String text &&
                        CrossAlignmentSupported(text.Value);
                }
                case LUIProperty.GrowValue:
                {
                    return value is LUIWireValue.Float { Value: >= 0.0 };
                }
                case LUIProperty.GridColumns:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.PaddingValue:
                {
                    return value is LUIWireValue.Int;
                }
                case LUIProperty.PaddingHorizontal:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.PaddingVertical:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.BackgroundValue:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.ForegroundValue:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.BorderColorValue:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.BorderWidth:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.CornerRadius:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.WidthValue:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.HeightValue:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.MinWidth:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.MaxWidth:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.MinHeight:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.MaxHeight:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.ContainerRelativeFrameValue:
                {
                    return value is LUIWireValue.String text &&
                        ContainerRelativeFrameSupported(text.Value);
                }
                case LUIProperty.ContainerRelativeFrameInset:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.PlaceholderValue:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.AccessibilityLabel:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.AccessibilityIdentifier:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.StyleClass:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.HeadingLevel:
                {
                    return value is LUIWireValue.Int { Value: >= 1 and <= 6 };
                }
                case LUIProperty.Checked:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.ProgressValue:
                {
                    return value is LUIWireValue.Float;
                }
                case LUIProperty.OrientationValue:
                {
                    return value is LUIWireValue.String text &&
                        OrientationSupported(text.Value);
                }
                case LUIProperty.PlacementValue:
                {
                    return value is LUIWireValue.String text &&
                        PlacementSupported(text.Value);
                }
                case LUIProperty.SizeValue:
                {
                    return value is LUIWireValue.String text &&
                        ControlSizeSupported(text.Value);
                }
                case LUIProperty.IconName:
                {
                    return value is LUIWireValue.String text &&
                        IconNameSupported(text.Value);
                }
                case LUIProperty.VariantValue:
                {
                    return value is LUIWireValue.String text &&
                        ButtonVariantSupported(text.Value);
                }
                case LUIProperty.InlineIconName:
                {
                    return value is LUIWireValue.String text &&
                        IconNameSupported(text.Value);
                }
                case LUIProperty.IconPlacementValue:
                {
                    return value is LUIWireValue.String text &&
                        IconPlacementSupported(text.Value);
                }
                case LUIProperty.Selected:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.Autofocus:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.SubmitOnEnter:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.LongPressEnabled:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.ChangeEnabled:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.ToggleEnabled:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.PressEnabled:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.SubmitEnabled:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.DoublePressEnabled:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.AppearEnabled:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.ImageIdValue:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.SurfaceIdValue:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.ActiveIndex:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.TitleValue:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.DescriptionValue:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.MetaValue:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.IndicatorValue:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.Connector:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.SourceX:
                case LUIProperty.SourceY:
                case LUIProperty.SourceWidth:
                case LUIProperty.SourceHeight:
                {
                    return value is LUIWireValue.Float number &&
                        IsFinite(number.Value);
                }
                case LUIProperty.AnchorValue:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "above" || text.Value == "below" ||
                         text.Value == "left" || text.Value == "right");
                }
                case LUIProperty.AnchorAlignmentValue:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "start" || text.Value == "end" ||
                         text.Value == "stretch");
                }
                case LUIProperty.AnchorOffset:
                {
                    return value is LUIWireValue.Float;
                }
                case LUIProperty.TooltipDelay:
                case LUIProperty.DurationValue:
                {
                    return value is LUIWireValue.Int number &&
                        number.Value >= 0 && number.Value <= 2147483647;
                }
                case LUIProperty.TextAlignment:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "start" || text.Value == "center" ||
                         text.Value == "end");
                }
                case LUIProperty.RoleValue:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "treeitem" ||
                         text.Value == "navigation" ||
                         text.Value == "navigation-heading");
                }
                case LUIProperty.TreeLevel:
                {
                    return value is LUIWireValue.Int { Value: > 0 };
                }
                case LUIProperty.Expanded:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.ResizeDuration:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.ResizeEasing:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "linear" || text.Value == "standard" ||
                         text.Value == "emphasized" ||
                         text.Value == "spring");
                }
                case LUIProperty.ResizeOrigin:
                {
                    return value is LUIWireValue.Float number &&
                        IsFinite(number.Value);
                }
                case LUIProperty.ThemeValue:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.ThemeMode:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "system" || text.Value == "light" ||
                         text.Value == "dark");
                }
                case LUIProperty.KeyValue:
                case LUIProperty.ScrollTarget:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.SeparatorValue:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "visible" || text.Value == "hidden");
                }
                case LUIProperty.StyleValue:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "plain" || text.Value == "inset" ||
                         text.Value == "inset-grouped");
                }
                case LUIProperty.ScrollAnchor:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "top" || text.Value == "center" ||
                         text.Value == "bottom");
                }
                case LUIProperty.ScrollToken:
                {
                    return value is LUIWireValue.Int { Value: >= 0 };
                }
                case LUIProperty.ScrollAnimated:
                case LUIProperty.TrackVisibleRange:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.EdgeValue:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "leading" || text.Value == "trailing");
                }
                case LUIProperty.PickerRequest:
                case LUIProperty.PickerCompletion:
                {
                    return value is LUIWireValue.String ||
                        value is LUIWireValue.Int;
                }
                case LUIProperty.PickerTypes:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.PickerMultiple:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.PickerSource:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "files" || text.Value == "photos" ||
                         text.Value == "camera");
                }
                case LUIProperty.MinValue:
                case LUIProperty.MaxValue:
                {
                    return value is LUIWireValue.Float number &&
                        IsFinite(number.Value);
                }
                case LUIProperty.StepValue:
                {
                    return value is LUIWireValue.Float stepValue &&
                        IsFinite(stepValue.Value) && stepValue.Value > 0.0;
                }
                case LUIProperty.Detents:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.Sizing:
                {
                    return value is LUIWireValue.String sizing &&
                        (sizing.Value == "form" || sizing.Value == "fitted" ||
                         sizing.Value == "page");
                }
                case LUIProperty.PathValue:
                case LUIProperty.UrlValue:
                {
                    return value is LUIWireValue.String;
                }
                case LUIProperty.MaxPixelSize:
                {
                    return value is LUIWireValue.Int { Value: > 0 };
                }
                case LUIProperty.EdgeValue:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "top" || text.Value == "bottom" ||
                         text.Value == "leading" || text.Value == "trailing");
                }
                case LUIProperty.Visible:
                {
                    return value is LUIWireValue.Bool;
                }
                case LUIProperty.AlignmentValue:
                {
                    return value is LUIWireValue.String text &&
                        (text.Value == "top-leading" || text.Value == "top" ||
                         text.Value == "top-trailing" ||
                         text.Value == "leading" || text.Value == "center" ||
                         text.Value == "trailing" ||
                         text.Value == "bottom-leading" ||
                         text.Value == "bottom" ||
                         text.Value == "bottom-trailing");
                }
                default:
                {
                    return false;
            }
        }


                }        public static bool PropertyValueSupportedForKind(
            LUINodeKind kind, LUIProperty property, LUIWireValue value)
        {
            if (property == LUIProperty.SizeValue)
            {
                if (value is LUIWireValue.String size)
                {
                    if (kind == LUINodeKind.TableCell)
                    {
                        return ControlSizeSupported(size.Value) ||
                            size.Value == "heading" || size.Value == "display";
                    }
                    return ControlSizeSupported(size.Value);
                }
                return false;
            }
            return PropertyValueSupported(property, value);
        }

        static long IntProperty(
            IReadOnlyDictionary<LUIProperty, LUIWireValue> properties,
            LUIProperty property, long fallback) =>
            properties.TryGetValue(property, out LUIWireValue? value) &&
            value is LUIWireValue.Int number
                ? number.Value
                : fallback;

        static bool SizeAxisSupported(
            IReadOnlyDictionary<LUIProperty, LUIWireValue> properties,
            LUIProperty fixedProperty, LUIProperty minProperty,
            LUIProperty maxProperty)
        {
            long minimum = IntProperty(properties, minProperty, 0);
            long fixedValue = IntProperty(properties, fixedProperty, minimum);
            if (fixedValue < minimum) return false;
            if (!properties.TryGetValue(maxProperty, out LUIWireValue? max))
            {
                return true;
            }
            if (max is LUIWireValue.Int maximum)
            {
                return minimum <= maximum.Value && fixedValue <= maximum.Value;
            }
            return false;
        }

        public static bool SurfaceSizeSupported(
            IReadOnlyDictionary<LUIProperty, LUIWireValue> properties) =>
            SizeAxisSupported(
                properties, LUIProperty.WidthValue, LUIProperty.MinWidth,
                LUIProperty.MaxWidth) &&
            SizeAxisSupported(
                properties, LUIProperty.HeightValue, LUIProperty.MinHeight,
                LUIProperty.MaxHeight);

        static string StringPropertyOr(
            IReadOnlyDictionary<LUIProperty, LUIWireValue> properties,
            LUIProperty property, string fallback) =>
            properties.TryGetValue(property, out LUIWireValue? value) &&
            value is LUIWireValue.String text
                ? text.Value
                : fallback;

        static bool StringPropertyNonempty(
            IReadOnlyDictionary<LUIProperty, LUIWireValue> properties,
            LUIProperty property) =>
            properties.TryGetValue(property, out LUIWireValue? value) &&
            value is LUIWireValue.String { Value: not "" };

        static double FloatPropertyOf(
            IReadOnlyDictionary<LUIProperty, LUIWireValue> properties,
            LUIProperty property, double fallback) =>
            properties.TryGetValue(property, out LUIWireValue? value) &&
            value is LUIWireValue.Float number
                ? number.Value
                : fallback;

        public static bool NodePropertiesSupported(
            LUINodeKind kind,
            IReadOnlyDictionary<LUIProperty, LUIWireValue> properties)
        {
            if (!SurfaceSizeSupported(properties)) return false;
            if (kind == LUINodeKind.Icon)
            {
                if (!properties.TryGetValue(
                        LUIProperty.IconName, out LUIWireValue? name) ||
                    !PropertyValueSupported(LUIProperty.IconName, name))
                {
                    return false;
                }
            }
            if (kind == LUINodeKind.EdgeInset &&
                !properties.ContainsKey(LUIProperty.EdgeValue))
            {
                return false;
            }
            if (kind == LUINodeKind.Button || kind == LUINodeKind.ToggleButton ||
                kind == LUINodeKind.Toggle || kind == LUINodeKind.Radio)
            {
                string text = StringPropertyOr(
                    properties, LUIProperty.TextValue, "");
                string label = StringPropertyOr(
                    properties, LUIProperty.AccessibilityLabel, "");
                string icon = StringPropertyOr(
                    properties, LUIProperty.InlineIconName, "");
                if (text == "" && label == "") return false;
                if (text == "" && icon != "" && label == "") return false;
            }
            if (kind == LUINodeKind.RadioGroup || kind == LUINodeKind.Slider)
            {
                if (!StringPropertyNonempty(
                        properties, LUIProperty.AccessibilityLabel))
                {
                    return false;
                }
            }
            if (kind == LUINodeKind.Select || kind == LUINodeKind.Combobox)
            {
                string text = StringPropertyOr(
                    properties, LUIProperty.TextValue, "");
                string placeholder = StringPropertyOr(
                    properties, LUIProperty.PlaceholderValue, "");
                if (text == "" && placeholder == "") return false;
            }
            if (kind == LUINodeKind.MenuItem || kind == LUINodeKind.Accordion)
            {
                if (!StringPropertyNonempty(properties, LUIProperty.TextValue))
                {
                    return false;
                }
            }
            if (ModalSurface(kind) &&
                !StringPropertyNonempty(properties, LUIProperty.TextValue))
            {
                return false;
            }
            if (kind == LUINodeKind.Tooltip)
            {
                if (!StringPropertyNonempty(properties, LUIProperty.TextValue))
                {
                    return false;
                }
                if (properties.ContainsKey(LUIProperty.TooltipDelay) &&
                    !properties.ContainsKey(LUIProperty.AnchorValue))
                {
                    return false;
                }
            }
            if (kind == LUINodeKind.DropdownMenu ||
                kind == LUINodeKind.Tooltip)
            {
                if ((properties.ContainsKey(LUIProperty.AnchorAlignmentValue) ||
                     properties.ContainsKey(LUIProperty.AnchorOffset)) &&
                    !properties.ContainsKey(LUIProperty.AnchorValue))
                {
                    return false;
                }
            }
            if (kind == LUINodeKind.Avatar || kind == LUINodeKind.Image)
            {
                bool hasImage =
                    properties.ContainsKey(LUIProperty.ImageIdValue);
                int sourceCount =
                    (properties.ContainsKey(LUIProperty.SourceX) ? 1 : 0) +
                    (properties.ContainsKey(LUIProperty.SourceY) ? 1 : 0) +
                    (properties.ContainsKey(LUIProperty.SourceWidth) ? 1 : 0) +
                    (properties.ContainsKey(LUIProperty.SourceHeight) ? 1 : 0);
                double sourceX =
                    FloatPropertyOf(properties, LUIProperty.SourceX, 0.0);
                double sourceY =
                    FloatPropertyOf(properties, LUIProperty.SourceY, 0.0);
                double sourceWidth =
                    FloatPropertyOf(properties, LUIProperty.SourceWidth, 0.0);
                double sourceHeight =
                    FloatPropertyOf(properties, LUIProperty.SourceHeight, 0.0);
                if (kind == LUINodeKind.Avatar)
                {
                    if (!StringPropertyNonempty(
                            properties, LUIProperty.TextValue))
                    {
                        return false;
                    }
                }
                else if (!hasImage)
                {
                    return false;
                }
                if (sourceCount != 0 && sourceCount != 4) return false;
                if (sourceCount != 0 && !hasImage) return false;
                if (sourceCount != 0 &&
                    (sourceX < 0.0 || sourceY < 0.0 || sourceWidth <= 0.0 ||
                     sourceHeight <= 0.0))
                {
                    return false;
                }
            }
            if (kind == LUINodeKind.MediaSurface &&
                !properties.ContainsKey(LUIProperty.SurfaceIdValue))
            {
                return false;
            }
            if ((kind == LUINodeKind.FileImage ||
                 kind == LUINodeKind.FilePreview) &&
                !StringPropertyNonempty(properties, LUIProperty.PathValue))
            {
                return false;
            }
            if (kind == LUINodeKind.Link &&
                !StringPropertyNonempty(properties, LUIProperty.UrlValue))
            {
                return false;
            }
            if (kind == LUINodeKind.Stepper &&
                !properties.ContainsKey(LUIProperty.ActiveIndex))
            {
                return false;
            }
            if (kind == LUINodeKind.Step || kind == LUINodeKind.TimelineItem ||
                kind == LUINodeKind.BottomTabs)
            {
                LUIProperty property = kind == LUINodeKind.Step
                    ? LUIProperty.TextValue
                    : kind == LUINodeKind.TimelineItem
                        ? LUIProperty.TitleValue
                        : LUIProperty.AccessibilityLabel;
                if (!StringPropertyNonempty(properties, property))
                {
                    return false;
                }
            }
            if (kind == LUINodeKind.BottomTab)
            {
                if (!StringPropertyNonempty(properties, LUIProperty.TitleValue) ||
                    !TrueProperty(properties, LUIProperty.PressEnabled))
                {
                    return false;
                }
            }
            if (kind == LUINodeKind.Slider || kind == LUINodeKind.Progress)
            {
                if (!properties.TryGetValue(
                        LUIProperty.ProgressValue, out LUIWireValue? progress) ||
                    progress is not LUIWireValue.Float)
                {
                    return false;
                }
            }
            if (kind == LUINodeKind.NumberStepper)
            {
                if (!properties.TryGetValue(
                        LUIProperty.ProgressValue,
                        out LUIWireValue? stepperValue) ||
                    stepperValue is not LUIWireValue.Float)
                {
                    return false;
                }
                if (!StringPropertyNonempty(
                        properties, LUIProperty.TextValue) &&
                    !StringPropertyNonempty(
                        properties, LUIProperty.AccessibilityLabel))
                {
                    return false;
                }
                // min defaults to 0.0 and max is unbounded; compare the
                // effective endpoints so a lone negative max still fails.
                double stepperMinimum = properties.TryGetValue(
                        LUIProperty.MinValue, out LUIWireValue? minimum) &&
                    minimum is LUIWireValue.Float minFloat
                        ? minFloat.Value : 0.0;
                double stepperMaximum = properties.TryGetValue(
                        LUIProperty.MaxValue, out LUIWireValue? maximum) &&
                    maximum is LUIWireValue.Float maxFloat
                        ? maxFloat.Value : double.MaxValue;
                if (stepperMinimum > stepperMaximum)
                {
                    return false;
                }
            }
            if (kind == LUINodeKind.Tree || kind == LUINodeKind.Toolbar)
            {
                if (!StringPropertyNonempty(
                        properties, LUIProperty.AccessibilityLabel))
                {
                    return false;
                }
            }
            if (kind == LUINodeKind.Split)
            {
                long duration = IntProperty(
                    properties, LUIProperty.ResizeDuration, 0);
                if (properties.ContainsKey(LUIProperty.ResizeEasing) &&
                    duration <= 0)
                {
                    return false;
                }
                if (properties.ContainsKey(LUIProperty.ResizeOrigin) &&
                    duration <= 0)
                {
                    return false;
                }
            }
            if (TreeRowKind(kind))
            {
                bool treeitem = TreeitemProperties(properties);
                bool hasTreeMetadata =
                    properties.ContainsKey(LUIProperty.TreeLevel) ||
                    properties.ContainsKey(LUIProperty.Expanded) ||
                    properties.ContainsKey(LUIProperty.ChangeEnabled) ||
                    properties.ContainsKey(LUIProperty.ToggleEnabled);
                // A list-item may carry expansion state as a disclosure row
                // without the treeitem role.
                bool disclosureListItem =
                    kind == LUINodeKind.ListItem && !treeitem &&
                    !properties.ContainsKey(LUIProperty.TreeLevel) &&
                    !properties.ContainsKey(LUIProperty.ChangeEnabled) &&
                    (properties.ContainsKey(LUIProperty.Expanded) ||
                     properties.ContainsKey(LUIProperty.ToggleEnabled));
                if (hasTreeMetadata && !treeitem && !disclosureListItem)
                {
                    return false;
                }
                if (properties.ContainsKey(LUIProperty.Expanded) &&
                    !TrueProperty(properties, LUIProperty.ToggleEnabled))
                {
                    return false;
                }
            }
            if (kind == LUINodeKind.SwipeAction &&
                !StringPropertyNonempty(properties, LUIProperty.TextValue) &&
                !StringPropertyNonempty(properties, LUIProperty.InlineIconName))
            {
                return false;
            }
            return true;
        }

        public static bool CanContainChildren(LUINodeKind kind)
        {
            if (HorizontalContainer(kind) || ContextMenuLeafHostKind(kind))
            {
                return true;
            }
            switch (kind)
            {
                case LUINodeKind.Root:
                case LUINodeKind.Row:
                case LUINodeKind.Column:
                case LUINodeKind.Grid:
                case LUINodeKind.Stack:
                case LUINodeKind.EdgeInset:
                case LUINodeKind.Overlay:
                case LUINodeKind.ViewThatFits:
                case LUINodeKind.Panel:
                case LUINodeKind.Card:
                case LUINodeKind.Box:
                case LUINodeKind.Scroll:
                case LUINodeKind.ListContainer:
                case LUINodeKind.VirtualList:
                case LUINodeKind.RadioGroup:
                case LUINodeKind.DropdownMenu:
                case LUINodeKind.ContextMenu:
                case LUINodeKind.ListItem:
                case LUINodeKind.Dialog:
                case LUINodeKind.Drawer:
                case LUINodeKind.Sheet:
                case LUINodeKind.Accordion:
                case LUINodeKind.Table:
                case LUINodeKind.TableRow:
                case LUINodeKind.Tree:
                case LUINodeKind.Resizable:
                case LUINodeKind.Split:
                case LUINodeKind.Stepper:
                case LUINodeKind.Timeline:
                case LUINodeKind.InputGroup:
                case LUINodeKind.InputGroupActions:
                case LUINodeKind.Toast:
                case LUINodeKind.Toolbar:
                case LUINodeKind.Alert:
                case LUINodeKind.Bubble:
                case LUINodeKind.BottomTabs:
                case LUINodeKind.BottomTab:
                case LUINodeKind.ListSection:
                case LUINodeKind.ListSectionHeader:
                case LUINodeKind.ListSectionFooter:
                case LUINodeKind.SwipeActions:
                case LUINodeKind.FilePicker:
                case LUINodeKind.Link:
                    return true;
                default:
                    return false;
            }
        }

        public static bool ChildKindSupported(
            LUINodeKind parentKind, LUINodeKind childKind)
        {
            if (childKind == LUINodeKind.Root) return false;
            if (parentKind == LUINodeKind.Root) return true;
            if (parentKind == LUINodeKind.MenuItem)
            {
                return childKind == LUINodeKind.ContextMenu ||
                    childKind == LUINodeKind.DropdownMenu;
            }
            if (ContextMenuLeafHostKind(parentKind))
            {
                return childKind == LUINodeKind.ContextMenu;
            }
            switch (parentKind)
            {
                case LUINodeKind.Table:
                    return childKind == LUINodeKind.TableRow;
                case LUINodeKind.TableRow:
                    return childKind == LUINodeKind.TableCell;
                case LUINodeKind.BottomTabs:
                    return childKind == LUINodeKind.BottomTab;
                case LUINodeKind.BottomTab:
                    return childKind != LUINodeKind.BottomTab;
                case LUINodeKind.Tree:
                    return TreeRowKind(childKind) ||
                        childKind == LUINodeKind.VirtualList;
                case LUINodeKind.Stepper:
                    return childKind == LUINodeKind.Step;
                case LUINodeKind.Timeline:
                    return childKind == LUINodeKind.TimelineItem;
                case LUINodeKind.InputGroup:
                    return childKind == LUINodeKind.Textarea ||
                        childKind == LUINodeKind.InputGroupActions;
                case LUINodeKind.Toolbar:
                    return ToolbarChildKind(childKind);
                case LUINodeKind.DropdownMenu:
                case LUINodeKind.ContextMenu:
                    return childKind == LUINodeKind.MenuItem ||
                        childKind == LUINodeKind.Divider;
                case LUINodeKind.ListSection:
                    return childKind == LUINodeKind.ListItem ||
                        childKind == LUINodeKind.ListSectionHeader ||
                        childKind == LUINodeKind.ListSectionFooter;
                case LUINodeKind.SwipeActions:
                    return childKind == LUINodeKind.SwipeAction;
                default:
                    break;
            }
            if (childKind == LUINodeKind.ListSection)
            {
                return parentKind == LUINodeKind.ListContainer;
            }
            if (childKind == LUINodeKind.ListSectionHeader ||
                childKind == LUINodeKind.ListSectionFooter)
            {
                return parentKind == LUINodeKind.ListSection;
            }
            if (childKind == LUINodeKind.SwipeActions)
            {
                return parentKind == LUINodeKind.ListItem;
            }
            if (childKind == LUINodeKind.SwipeAction)
            {
                return parentKind == LUINodeKind.SwipeActions;
            }
            return true;
        }
    }
}
