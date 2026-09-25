// Per-kind sync: applies kind-specific props and children to the already
// retained control. Shared frame/appearance props are handled by
// LUIPropertyApplier before this runs.

using System;
using System.Collections.Generic;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;

namespace LUI.WinUI
{
    public sealed partial class LUIElement
    {
        void SyncKind(LUINodeState state, LUISyncContext context)
        {
            switch (state.Kind)
            {
                case LUINodeKind.Root:
                    SyncPlainContainer(state, context);
                    break;
                case LUINodeKind.Stack:
                    SyncStackLike(state, context);
                    break;
                case LUINodeKind.Row:
                case LUINodeKind.Column:
                case LUINodeKind.Box:
                case LUINodeKind.Bubble:
                case LUINodeKind.Panel:
                case LUINodeKind.Card:
                    SyncFlexContainer(state, context);
                    break;
                case LUINodeKind.Grid:
                    SyncGrid(state, context);
                    break;
                case LUINodeKind.Scroll:
                case LUINodeKind.InputGroup:
                case LUINodeKind.InputGroupActions:
                case LUINodeKind.ListContainer:
                case LUINodeKind.VirtualList:
                case LUINodeKind.Stepper:
                case LUINodeKind.Timeline:
                case LUINodeKind.RadioGroup:
                case LUINodeKind.BottomTab:
                case LUINodeKind.Step:
                case LUINodeKind.TimelineItem:
                case LUINodeKind.Dialog:
                case LUINodeKind.Drawer:
                case LUINodeKind.Sheet:
                    SyncPlainContainer(state, context);
                    break;
                case LUINodeKind.Tabs:
                case LUINodeKind.ButtonGroup:
                case LUINodeKind.ToggleGroup:
                case LUINodeKind.Breadcrumb:
                case LUINodeKind.Pagination:
                    SyncHorizontalGroup(state, context);
                    break;
                case LUINodeKind.Toolbar:
                    SyncToolbar(state, context);
                    break;
                case LUINodeKind.Alert:
                    SyncAlert(state, context);
                    break;
                case LUINodeKind.Text:
                case LUINodeKind.Paragraph:
                case LUINodeKind.Label:
                case LUINodeKind.Heading:
                    SyncText(state, context);
                    break;
                case LUINodeKind.Button:
                    SyncButton(state, context);
                    break;
                case LUINodeKind.ToggleButton:
                    SyncToggleButton(state, context);
                    break;
                case LUINodeKind.Toggle:
                case LUINodeKind.SwitchControl:
                    SyncToggleSwitch(state, context);
                    break;
                case LUINodeKind.Radio:
                    SyncRadio(state, context);
                    break;
                case LUINodeKind.Slider:
                    SyncSlider(state, context);
                    break;
                case LUINodeKind.TextField:
                case LUINodeKind.Input:
                case LUINodeKind.Textarea:
                    SyncTextBox(state, context);
                    break;
                case LUINodeKind.SecureField:
                    SyncSecureField(state, context);
                    break;
                case LUINodeKind.SearchField:
                case LUINodeKind.Combobox:
                    SyncAutoSuggest(state, context);
                    break;
                case LUINodeKind.Checkbox:
                    SyncCheckBox(state, context);
                    break;
                case LUINodeKind.Progress:
                    SyncProgress(state, context);
                    break;
                case LUINodeKind.Divider:
                    SyncDivider(state, context);
                    break;
                case LUINodeKind.Spacer:
                    break;
                case LUINodeKind.Spinner:
                    if (Control is ProgressRing ring)
                    {
                        ring.IsActive = true;
                    }
                    break;
                case LUINodeKind.Icon:
                    SyncIcon(state, context);
                    break;
                case LUINodeKind.Select:
                    SyncSelect(state, context);
                    break;
                case LUINodeKind.ListItem:
                    SyncListItem(state, context);
                    break;
                case LUINodeKind.Avatar:
                    SyncAvatar(state, context);
                    break;
                case LUINodeKind.Image:
                    SyncImage(state, context);
                    break;
                case LUINodeKind.MediaSurface:
                    SyncMediaSurface(state, context);
                    break;
                case LUINodeKind.Table:
                    SyncTable(state, context);
                    break;
                case LUINodeKind.TableRow:
                    SyncTableRow(state, context);
                    break;
                case LUINodeKind.TableCell:
                    SyncTableCell(state, context);
                    break;
                case LUINodeKind.Tree:
                    SyncTree(state, context);
                    break;
                case LUINodeKind.Resizable:
                case LUINodeKind.Split:
                    SyncResizable(state, context);
                    break;
                case LUINodeKind.Accordion:
                    SyncAccordion(state, context);
                    break;
                case LUINodeKind.Toast:
                    // Presented by LUIModalPresenter; the node stays as a
                    // data carrier only.
                    break;
                case LUINodeKind.Tooltip:
                    if (Control is TextBlock tipText)
                    {
                        tipText.Text = LUIPropertyApplier.Text(state);
                    }
                    break;
                case LUINodeKind.DropdownMenu:
                case LUINodeKind.ContextMenu:
                    // Metadata children — the parent attaches them.
                    break;
                case LUINodeKind.MenuItem:
                    break;
                case LUINodeKind.BottomTabs:
                    SyncBottomTabs(state, context);
                    break;
                case LUINodeKind.StatusBar:
                    SyncStatusBar(state, context);
                    break;
            }
        }

        // ---- containers -------------------------------------------------

        void SyncStackLike(LUINodeState state, LUISyncContext context)
        {
            if (Control is not Grid grid) return;
            context.Host.SyncPanelChildren(
                grid, context.InlineChildrenOf(state), null);
        }

        void SyncFlexContainer(LUINodeState state, LUISyncContext context)
        {
            Panel? panel = ChildrenPanel;
            if (panel is not LUIGrid grid) return;
            bool horizontal = state.Kind == LUINodeKind.Row;
            LUIPropertyApplier.ConfigureFlexTracks(
                grid, horizontal, state, context);
            context.Host.SyncPanelChildren(
                grid, context.InlineChildrenOf(state),
                i => horizontal ? (i, 0) : (0, i));
        }

        void SyncGrid(LUINodeState state, LUISyncContext context)
        {
            if (Control is not LUIGrid grid) return;
            int columns = (int)(LUIPropertyApplier.Prop(
                state, LUIProperty.GridColumns)?.AsInt ?? 1);
            if (columns < 1) columns = 1;
            LUIPropertyApplier.ConfigureGridTracks(grid, state, context);
            context.Host.SyncPanelChildren(
                grid, context.InlineChildrenOf(state),
                i => (i % columns, i / columns));
        }

        void SyncPlainContainer(LUINodeState state, LUISyncContext context)
        {
            Panel? panel = ChildrenPanel;
            if (panel == null) return;
            context.Host.SyncPanelChildren(
                panel, context.InlineChildrenOf(state), i => (0, i));
        }

        void SyncHorizontalGroup(LUINodeState state, LUISyncContext context)
        {
            if (ChildrenPanel is not LUIGrid grid) return;
            LUIPropertyApplier.ConfigureFlexTracks(
                grid, true, state, context);
            context.Host.SyncPanelChildren(
                grid, context.InlineChildrenOf(state), i => (i, 0));
        }

        void SyncToolbar(LUINodeState state, LUISyncContext context)
        {
            if (ChildrenPanel is not LUIGrid grid) return;
            LUIPropertyApplier.ConfigureFlexTracks(
                grid, true, state, context);
            context.Host.SyncPanelChildren(
                grid, context.InlineChildrenOf(state), i => (i, 0));
        }

        // ---- feedback / text --------------------------------------------

        void SyncAlert(LUINodeState state, LUISyncContext context)
        {
            if (Control is not InfoBar bar) return;
            bar.Title = LUIPropertyApplier.Prop(
                state, LUIProperty.TitleValue)?.AsString
                ?? LUIPropertyApplier.Text(state);
            bar.Message = LUIPropertyApplier.Prop(
                state, LUIProperty.DescriptionValue)?.AsString ?? "";
            // The wire variant set is the button enum
            // (default|primary|secondary|outline|ghost|destructive);
            // only `destructive` carries severity color on alert (the
            // SwiftUI backend does the same).
            bar.Severity =
                LUIPropertyApplier.Prop(state, LUIProperty.VariantValue)?.AsString == "destructive"
                    ? InfoBarSeverity.Error
                    : InfoBarSeverity.Informational;
            Panel? panel = ChildrenPanel;
            if (panel == null)
            {
                var inner = new LUIGrid();
                bar.Content = inner;
                panel = inner;
            }
            context.Host.SyncPanelChildren(
                panel, context.InlineChildrenOf(state), i => (0, i));
        }

        void SyncText(LUINodeState state, LUISyncContext context)
        {
            if (Control is not TextBlock block) return;
            block.Text = LUIPropertyApplier.Text(state);
            block.TextWrapping = TextWrapping.Wrap;
            LUIPropertyApplier.ApplyTextStyle(
                block, state, state.Kind == LUINodeKind.Heading);
        }

        // ---- buttons -----------------------------------------------------

        void SyncButton(LUINodeState state, LUISyncContext context)
        {
            if (Control is not Button button) return;
            button.Content = LUIPropertyApplier.ButtonContent(state);
            LUIPropertyApplier.ApplyButtonVariant(button, state);
            button.Click -= OnClick;
            button.Click += OnClick;
        }

        void OnClick(object sender, RoutedEventArgs args)
        {
            LUISyncContext? context = Context;
            if (context != null)
            {
                Gate(() => context.Backend.PerformAction(Id));
            }
        }

        void SyncToggleButton(LUINodeState state, LUISyncContext context)
        {
            if (Control is not ToggleButton button) return;
            button.Content = LUIPropertyApplier.ButtonContent(state);
            LUIPropertyApplier.ApplyButtonVariant(button, state);
            bool? isChecked = LUIPropertyApplier.Prop(
                state, LUIProperty.Checked)?.AsBool;
            button.IsChecked = isChecked;
            button.Click -= OnToggleClick;
            button.Click += OnToggleClick;
        }

        void OnToggleClick(object sender, RoutedEventArgs args)
        {
            LUISyncContext? context = Context;
            if (context == null) return;
            if (Control is ToggleButton button)
            {
                Gate(() => context.Backend.PerformToggle(
                    Id, button.IsChecked == true));
            }
        }

        void SyncToggleSwitch(LUINodeState state, LUISyncContext context)
        {
            if (Control is not ToggleSwitch toggle) return;
            // `text` is the switch's always-visible label (Apple
            // Toggle(model.text, isOn:), Flutter SwitchListTile title);
            // Header is the label slot — OnContent/OffContent are the
            // on/off captions.
            toggle.Header = LUIPropertyApplier.Text(state);
            bool? isOn = LUIPropertyApplier.Prop(
                state, LUIProperty.Checked)?.AsBool;
            toggle.IsOn = isOn == true;
            toggle.Toggled -= OnToggled;
            toggle.Toggled += OnToggled;
        }

        void OnToggled(object sender, RoutedEventArgs args)
        {
            LUISyncContext? context = Context;
            if (context == null) return;
            if (Control is ToggleSwitch toggle)
            {
                Gate(() => context.Backend.PerformToggle(Id, toggle.IsOn));
            }
        }

        void SyncRadio(LUINodeState state, LUISyncContext context)
        {
            if (Control is not RadioButton radio) return;
            radio.Content = LUIPropertyApplier.Text(state);
            bool? isChecked = LUIPropertyApplier.Prop(
                state, LUIProperty.Checked)?.AsBool;
            radio.IsChecked = isChecked;
            radio.Checked -= OnRadioChecked;
            radio.Checked += OnRadioChecked;
        }

        void OnRadioChecked(object sender, RoutedEventArgs args)
        {
            LUISyncContext? context = Context;
            if (context != null)
            {
                Gate(() => context.Backend.PerformChange(Id));
            }
        }

        void SyncSlider(LUINodeState state, LUISyncContext context)
        {
            if (Control is not Slider slider) return;
            double? value = LUIPropertyApplier.Prop(
                state, LUIProperty.ProgressValue)?.AsFloat;
            slider.ValueChanged -= OnSliderChanged;
            if (value != null) slider.Value = value.Value;
            slider.ValueChanged += OnSliderChanged;
        }

        void OnSliderChanged(
            object sender, RangeBaseValueChangedEventArgs args)
        {
            LUISyncContext? context = Context;
            if (context != null)
            {
                Gate(() => context.Backend.PerformValueChange(Id, args.NewValue));
            }
        }

        // ---- inputs -------------------------------------------------------

        void SyncTextBox(LUINodeState state, LUISyncContext context)
        {
            if (Control is not TextBox box) return;
            box.PlaceholderText = LUIPropertyApplier.Prop(
                state, LUIProperty.PlaceholderValue)?.AsString ?? "";
            string? text = LUIPropertyApplier.Text(state);
            box.TextChanged -= OnTextChanged;
            box.KeyDown -= OnSubmitKey;
            if (box.Text != text) box.Text = text;
            box.TextChanged += OnTextChanged;
            box.KeyDown += OnSubmitKey;
        }

        void OnTextChanged(object sender, TextChangedEventArgs args)
        {
            LUISyncContext? context = Context;
            if (context != null && Control is TextBox box)
            {
                Gate(() => context.Backend.PerformTextChanged(Id, box.Text));
            }
        }

        void OnSubmitKey(object sender, KeyRoutedEventArgs args)
        {
            if (args.Key != Windows.System.VirtualKey.Enter) return;
            LUISyncContext? context = Context;
            if (context != null)
            {
                Gate(() => context.Backend.PerformSubmit(Id));
            }
        }

        void SyncSecureField(LUINodeState state, LUISyncContext context)
        {
            if (Control is not PasswordBox box) return;
            box.PlaceholderText = LUIPropertyApplier.Prop(
                state, LUIProperty.PlaceholderValue)?.AsString ?? "";
            string? text = LUIPropertyApplier.Text(state);
            box.PasswordChanged -= OnPasswordChanged;
            box.KeyDown -= OnSubmitKey;
            if (box.Password != text) box.Password = text;
            box.PasswordChanged += OnPasswordChanged;
            box.KeyDown += OnSubmitKey;
        }

        void OnPasswordChanged(object sender, RoutedEventArgs args)
        {
            LUISyncContext? context = Context;
            if (context != null && Control is PasswordBox box)
            {
                Gate(() => context.Backend.PerformTextChanged(
                    Id, box.Password));
            }
        }

        void SyncAutoSuggest(LUINodeState state, LUISyncContext context)
        {
            if (Control is not AutoSuggestBox box) return;
            box.PlaceholderText = LUIPropertyApplier.Prop(
                state, LUIProperty.PlaceholderValue)?.AsString ?? "";
            string? text = LUIPropertyApplier.Text(state);
            box.TextChanged -= OnSuggestTextChanged;
            box.QuerySubmitted -= OnQuerySubmitted;
            if (box.Text != text) box.Text = text;
            box.TextChanged += OnSuggestTextChanged;
            box.QuerySubmitted += OnQuerySubmitted;
        }

        void OnSuggestTextChanged(
            object sender, AutoSuggestBoxTextChangedEventArgs args)
        {
            LUISyncContext? context = Context;
            if (context != null &&
                args.Reason == AutoSuggestionBoxTextChangeReason.UserInput &&
                Control is AutoSuggestBox box)
            {
                Gate(() => context.Backend.PerformTextChanged(Id, box.Text));
            }
        }

        void OnQuerySubmitted(
            object sender, AutoSuggestBoxQuerySubmittedEventArgs args)
        {
            LUISyncContext? context = Context;
            if (context != null)
            {
                Gate(() => context.Backend.PerformSubmit(Id));
            }
        }

        void SyncCheckBox(LUINodeState state, LUISyncContext context)
        {
            if (Control is not CheckBox box) return;
            box.Content = LUIPropertyApplier.Text(state);
            box.Checked -= OnCheckChanged;
            box.Unchecked -= OnCheckChanged;
            bool? isChecked = LUIPropertyApplier.Prop(
                state, LUIProperty.Checked)?.AsBool;
            box.IsChecked = isChecked;
            box.Checked += OnCheckChanged;
            box.Unchecked += OnCheckChanged;
        }

        void OnCheckChanged(object sender, RoutedEventArgs args)
        {
            LUISyncContext? context = Context;
            if (context != null && Control is CheckBox box)
            {
                Gate(() => context.Backend.PerformToggle(
                    Id, box.IsChecked == true));
            }
        }

        // ---- misc leaf controls -------------------------------------------

        void SyncProgress(LUINodeState state, LUISyncContext context)
        {
            if (Control is not ProgressBar bar) return;
            double? value = LUIPropertyApplier.Prop(
                state, LUIProperty.ProgressValue)?.AsFloat;
            if (value != null) bar.Value = value.Value;
        }

        void SyncDivider(LUINodeState state, LUISyncContext context)
        {
            if (Control is not Border divider) return;
            bool horizontal = LUIPropertyApplier.Prop(
                state, LUIProperty.OrientationValue)?.AsString !=
                "vertical";
            divider.Height = horizontal ? 1 : double.NaN;
            divider.Width = horizontal ? double.NaN : 1;
            divider.HorizontalAlignment = horizontal
                ? HorizontalAlignment.Stretch
                : HorizontalAlignment.Center;
            divider.VerticalAlignment = horizontal
                ? VerticalAlignment.Center
                : VerticalAlignment.Stretch;
            divider.Background =
                LUIThemeColors.Brush(context, state, "border");
        }

        void SyncIcon(LUINodeState state, LUISyncContext context)
        {
            if (Control is not FontIcon icon) return;
            string? name = LUIPropertyApplier.Prop(
                state, LUIProperty.IconName)?.AsString;
            icon.Glyph = name == null ? "" : LUIIconGlyphs.Glyph(name) ?? "";
        }

        void SyncSelect(LUINodeState state, LUISyncContext context)
        {
            if (Control is not DropDownButton button) return;
            string? text = LUIPropertyApplier.Text(state);
            button.Content = string.IsNullOrEmpty(text)
                ? LUIPropertyApplier.Prop(
                    state, LUIProperty.PlaceholderValue)?.AsString ?? ""
                : text;
            var flyout = new MenuFlyout();
            foreach (long childId in state.Children)
            {
                if (context.Backend.States.TryGetValue(
                        childId, out LUINodeState? child) &&
                    child.Kind == LUINodeKind.DropdownMenu)
                {
                    LUIMenuBuilder.Fill(context, flyout.Items, child);
                }
            }
            button.Flyout = flyout;
            button.Click -= OnClick;
            button.Click += OnClick;
        }

        void SyncListItem(LUINodeState state, LUISyncContext context)
        {
            Panel? panel = ChildrenPanel;
            if (panel != null)
            {
                context.Host.SyncPanelChildren(
                    panel, context.InlineChildrenOf(state), i => (0, i));
            }
        }

        void SyncAvatar(LUINodeState state, LUISyncContext context)
        {
            if (Control is not PersonPicture avatar) return;
            long? imageId = LUIPropertyApplier.Prop(
                state, LUIProperty.ImageIdValue)?.AsInt;
            avatar.Initials = "";
            avatar.DisplayName = LUIPropertyApplier.Text(state);
            if (imageId != null &&
                context.Images.TryGetValue(
                    imageId.Value,
                    out Microsoft.UI.Xaml.Media.Imaging.BitmapSource? bmp))
            {
                avatar.ProfilePicture = bmp;
            }
            else
            {
                avatar.ProfilePicture = null;
            }
        }

        void SyncImage(LUINodeState state, LUISyncContext context)
        {
            if (Control is not Image image) return;
            long? imageId = LUIPropertyApplier.Prop(
                state, LUIProperty.ImageIdValue)?.AsInt;
            image.Source = imageId != null &&
                context.Images.TryGetValue(
                    imageId.Value,
                    out Microsoft.UI.Xaml.Media.Imaging.BitmapSource? bmp)
                ? bmp
                : null;
        }

        void SyncMediaSurface(LUINodeState state, LUISyncContext context)
        {
            if (Control is not Border border) return;
            long? surfaceId = LUIPropertyApplier.Prop(
                state, LUIProperty.SurfaceIdValue)?.AsInt;
            border.Child = surfaceId != null &&
                context.Surfaces.TryGetValue(
                    surfaceId.Value, out FrameworkElement? surface)
                ? surface
                : null;
        }

        // ---- structured containers ----------------------------------------

        void SyncTable(LUINodeState state, LUISyncContext context)
        {
            if (ChildrenPanel is not LUIGrid grid) return;
            LUIPropertyApplier.ConfigureFlexTracks(
                grid, false, state, context);
            context.Host.SyncPanelChildren(
                grid, context.InlineChildrenOf(state), i => (0, i));
        }

        void SyncTableRow(LUINodeState state, LUISyncContext context)
        {
            if (ChildrenPanel is not LUIGrid grid) return;
            LUIPropertyApplier.ConfigureFlexTracks(
                grid, true, state, context);
            context.Host.SyncPanelChildren(
                grid, context.InlineChildrenOf(state), i => (i, 0));
        }

        void SyncTableCell(LUINodeState state, LUISyncContext context)
        {
            if (Control is not Border border) return;
            if (border.Child is not TextBlock block)
            {
                block = new TextBlock();
                border.Child = block;
            }
            block.Text = LUIPropertyApplier.Text(state);
            block.TextWrapping = TextWrapping.Wrap;
            LUIPropertyApplier.ApplyTextStyle(
                block, state,
                LUIPropertyApplier.Prop(
                    state, LUIProperty.SizeValue)?.AsString == "heading");
        }

        void SyncTree(LUINodeState state, LUISyncContext context)
        {
            if (ChildrenPanel is not LUIGrid grid) return;
            LUIPropertyApplier.ConfigureFlexTracks(
                grid, false, state, context);
            var rows = new List<UIElement>();
            foreach (long childId in context.InlineChildrenOf(state))
            {
                LUIElement child = context.ElementFor(childId);
                rows.Add(BuildTreeRow(child, context));
            }
            context.Host.ReplaceChildren(grid, rows);
        }

        UIElement BuildTreeRow(LUIElement child, LUISyncContext context)
        {
            var row = new LUIGrid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            if (!context.Backend.States.TryGetValue(
                    child.Id, out LUINodeState? state))
            {
                return row;
            }
            double level = LUIPropertyApplier.Prop(
                state, LUIProperty.TreeLevel)?.AsFloat ?? 0;
            bool expanded = LUIPropertyApplier.Prop(
                state, LUIProperty.Expanded)?.AsBool == true;
            row.Margin = new Thickness(level * 16, 0, 0, 0);

            var chevron = new FontIcon
            {
                Glyph = expanded ? "\uE70D" : "\uE76C",
                FontSize = 10,
                VerticalAlignment = VerticalAlignment.Center,
            };
            var toggle = new Button
            {
                Content = chevron,
                Background = null,
                Padding = new Thickness(4),
                BorderThickness = new Thickness(0),
            };
            long childId = child.Id;
            toggle.Click += (_, _) =>
            {
                LUISyncContext? ctx = Context;
                if (ctx != null)
                {
                    Gate(() => ctx.Backend.PerformToggle(childId, !expanded));
                }
            };
            Grid.SetColumn(toggle, 0);
            row.Children.Add(toggle);

            Grid.SetColumn(child.Control, 1);
            row.Children.Add(child.Control);
            return row;
        }

        void SyncResizable(LUINodeState state, LUISyncContext context)
        {
            if (ChildrenPanel is not LUIGrid grid) return;
            var children = context.InlineChildrenOf(state);
            bool isSplit = state.Kind == LUINodeKind.Split;
            // Split: two columns sized by `progress` (0..1). Resizable:
            // uniform star tracks with a GridSplitter every boundary.
            double split = isSplit
                ? LUIPropertyApplier.Prop(
                    state, LUIProperty.ProgressValue)?.AsFloat ?? 0.5
                : 0;
            grid.ColumnDefinitions.Clear();
            grid.RowDefinitions.Clear();
            int cols = children.Count + (isSplit ? 0 : children.Count - 1);
            for (int i = 0; i < cols; i++)
            {
                bool isThumb = !isSplit && i % 2 == 1;
                double weight;
                if (isThumb)
                {
                    weight = 0; // fixed-width thumb set below
                }
                else if (isSplit)
                {
                    int childIndex = i;
                    weight = childIndex == 0 ? Math.Max(split, 0.01)
                        : Math.Max(1 - split, 0.01);
                }
                else
                {
                    weight = 1;
                }
                grid.ColumnDefinitions.Add(new ColumnDefinition
                {
                    Width = isThumb
                        ? new GridLength(6)
                        : new GridLength(weight, GridUnitType.Star),
                });
            }
            context.Host.SyncPanelChildren(
                grid, children,
                childIndex => (isSplit ? childIndex : childIndex * 2, 0));
            // Splitter thumbs are plain controls (not element children) —
            // drop the previous pass's thumbs before re-adding.
            for (int i = grid.Children.Count - 1; i >= 0; i--)
            {
                if (grid.Children[i] is FrameworkElement fe &&
                    fe.Name == SplitThumbName)
                {
                    grid.Children.RemoveAt(i);
                }
            }
            if (!isSplit)
            {
                var thumbs = new List<UIElement>();
                for (int i = 1; i < cols; i += 2)
                {
                    int thumbColumn = i;
                    var thumb = new Border
                    {
                        Name = SplitThumbName,
                        Background = LUIThemeColors.Brush(
                            context, state, "border"),
                        Opacity = 0.4,
                    };
                    thumb.ManipulationMode =
                        ManipulationModes.TranslateX;
                    thumb.ManipulationDelta += (_, args) =>
                    {
                        GridResize(thumbColumn, args.Delta.Translation.X);
                    };
                    Grid.SetColumn(thumb, i);
                    thumbs.Add(thumb);
                }
                foreach (UIElement thumb in thumbs)
                {
                    grid.Children.Add(thumb);
                }
            }
        }

        const string SplitThumbName = "__lui_split_thumb";

        // Resizable thumbs adjust the star weights of the two columns they
        // separate. Approximation of the protocol's resize animation props.
        void GridResize(int thumbColumn, double delta)
        {
            if (ChildrenPanel is not LUIGrid grid) return;
            if (thumbColumn - 1 < 0 ||
                thumbColumn + 1 >= grid.ColumnDefinitions.Count)
            {
                return;
            }
            ColumnDefinition left = grid.ColumnDefinitions[thumbColumn - 1];
            ColumnDefinition right = grid.ColumnDefinitions[thumbColumn + 1];
            double total = left.Width.Value + right.Width.Value;
            if (total <= 0 || grid.ActualWidth <= 0) return;
            double deltaWeight = delta / grid.ActualWidth * total;
            left.Width = new GridLength(
                Math.Max(0.05, left.Width.Value + deltaWeight),
                GridUnitType.Star);
            right.Width = new GridLength(
                Math.Max(0.05, right.Width.Value - deltaWeight),
                GridUnitType.Star);
        }

        void SyncAccordion(LUINodeState state, LUISyncContext context)
        {
            if (Control is not Expander expander) return;
            expander.Header = LUIPropertyApplier.Prop(
                state, LUIProperty.TitleValue)?.AsString
                ?? LUIPropertyApplier.Text(state);
            bool expanded = LUIPropertyApplier.Prop(
                state, LUIProperty.Expanded)?.AsBool == true;
            expander.IsExpanded = expanded;
            if (expander.Content is not Panel panel)
            {
                panel = new LUIGrid();
                expander.Content = panel;
            }
            context.Host.SyncPanelChildren(
                panel, context.InlineChildrenOf(state), i => (0, i));
        }

        void SyncBottomTabs(LUINodeState state, LUISyncContext context)
        {
            if (Control is not Grid root) return;
            // Row 0: content (selected tab's children); Row 1: the bar.
            root.RowDefinitions.Clear();
            root.RowDefinitions.Add(new RowDefinition
            {
                Height = new GridLength(1, GridUnitType.Star),
            });
            root.RowDefinitions.Add(new RowDefinition
            {
                Height = GridLength.Auto,
            });
            var content = new LUIGrid();
            var bar = new LUIGrid();
            int index = 0;
            long? selected = LUIPropertyApplier.Prop(
                state, LUIProperty.ActiveIndex)?.AsInt;
            var barChildren = new List<UIElement>();
            foreach (long childId in state.Children)
            {
                if (!context.Backend.States.TryGetValue(
                        childId, out LUINodeState? tab) ||
                    tab.Kind != LUINodeKind.BottomTab)
                {
                    continue;
                }
                int tabIndex = index;
                var button = new Button
                {
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    HorizontalContentAlignment = HorizontalAlignment.Center,
                    Background = null,
                    BorderThickness = new Thickness(0),
                    Padding = new Thickness(8, 8, 8, 8),
                };
                var stack = new LUIGrid();
                stack.RowDefinitions.Add(new RowDefinition
                {
                    Height = GridLength.Auto,
                });
                stack.RowDefinitions.Add(new RowDefinition
                {
                    Height = GridLength.Auto,
                });
                string? iconName = LUIPropertyApplier.Prop(
                    tab, LUIProperty.IconName)?.AsString;
                if (iconName != null)
                {
                    stack.Children.Add(new FontIcon
                    {
                        Glyph = LUIIconGlyphs.Glyph(iconName) ?? "",
                        FontSize = 18,
                        HorizontalAlignment = HorizontalAlignment.Center,
                    });
                }
                var label = new TextBlock
                {
                    Text = LUIPropertyApplier.Text(tab),
                    FontSize = 11,
                    HorizontalAlignment = HorizontalAlignment.Center,
                };
                Grid.SetRow(label, 1);
                stack.Children.Add(label);
                button.Content = stack;
                long tabId = childId;
                button.Click += (_, _) =>
                {
                    LUISyncContext? ctx = Context;
                    if (ctx != null)
                    {
                        Gate(() => ctx.Backend.PerformAction(tabId));
                    }
                };
                if (selected == null ? index == 0 : selected == index)
                {
                    button.Foreground =
                        LUIThemeColors.Brush(context, tab, "primary");
                }
                bar.ColumnDefinitions.Add(new ColumnDefinition
                {
                    Width = new GridLength(1, GridUnitType.Star),
                });
                Grid.SetColumn(button, index);
                barChildren.Add(button);
                // Tab content: element for the tab's children.
                if (selected == null ? index == 0 : selected == index)
                {
                    context.Host.SyncPanelChildren(
                        content, context.InlineChildrenOf(tab),
                        i => (0, i));
                }
                index++;
            }
            context.Host.ReplaceChildren(bar, barChildren);
            content.SetValue(Grid.RowProperty, 0);
            bar.SetValue(Grid.RowProperty, 1);
            context.Host.ReplaceChildren(
                root, new List<UIElement> { content, bar });
        }

        void SyncStatusBar(LUINodeState state, LUISyncContext context)
        {
            if (Control is not Border border) return;
            if (border.Child is not TextBlock block)
            {
                block = new TextBlock();
                border.Child = block;
            }
            block.Text = LUIPropertyApplier.Text(state);
            block.FontSize = 12;
            border.Padding = new Thickness(8, 4, 8, 4);
        }
    }
}
