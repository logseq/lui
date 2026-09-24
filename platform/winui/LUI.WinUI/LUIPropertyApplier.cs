// Shared property application: frame sizing, padding, colors, borders,
// accessibility, text styling, flex/grid track configuration. Maps the
// semantic vocabulary of the wire protocol onto WinUI equivalents —
// `grow` -> star-sized track, `gap` -> spacing, `container-relative-frame`
// -> a SizeChanged-driven sizer.

using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;

namespace LUI.WinUI
{
    internal static class LUIPropertyApplier
    {
        internal static LUIWireValue? Prop(
            LUINodeState state, LUIProperty property) =>
            state.Properties.TryGetValue(property, out LUIWireValue? value)
                ? value
                : null;

        internal static string Text(LUINodeState state) =>
            Prop(state, LUIProperty.TextValue)?.AsString ?? "";

        public static void Apply(
            FrameworkElement control, LUINodeState state,
            LUISyncContext context)
        {
            ApplyFrame(control, state);
            ApplyPadding(control, state);
            ApplyAppearance(control, state);
            ApplyAccessibility(control, state);
            if (control is Control ctl)
            {
                bool enabled =
                    Prop(state, LUIProperty.Enabled)?.AsBool ?? true;
                ctl.IsEnabled = enabled;
            }
        }

        static void ApplyFrame(FrameworkElement control, LUINodeState state)
        {
            control.Width = Prop(
                state, LUIProperty.WidthValue)?.AsFloat ?? double.NaN;
            control.Height = Prop(
                state, LUIProperty.HeightValue)?.AsFloat ?? double.NaN;
            control.MinWidth = Prop(
                state, LUIProperty.MinWidth)?.AsFloat ?? 0;
            control.MinHeight = Prop(
                state, LUIProperty.MinHeight)?.AsFloat ?? 0;
            control.MaxWidth = Prop(
                state, LUIProperty.MaxWidth)?.AsFloat ??
                double.PositiveInfinity;
            control.MaxHeight = Prop(
                state, LUIProperty.MaxHeight)?.AsFloat ??
                double.PositiveInfinity;
        }

        static void ApplyPadding(FrameworkElement control, LUINodeState state)
        {
            double all = Prop(
                state, LUIProperty.PaddingValue)?.AsFloat ?? -1;
            double horizontal = Prop(
                state, LUIProperty.PaddingHorizontal)?.AsFloat ??
                Math.Max(all, 0);
            double vertical = Prop(
                state, LUIProperty.PaddingVertical)?.AsFloat ??
                Math.Max(all, 0);
            var padding = new Thickness(horizontal, vertical,
                horizontal, vertical);
            switch (control)
            {
                case Control ctl:
                    ctl.Padding = padding;
                    break;
                case Border border:
                    border.Padding = padding;
                    break;
                case TextBlock block:
                    block.Padding = padding;
                    break;
            }
        }

        static void ApplyAppearance(
            FrameworkElement control, LUINodeState state)
        {
            Brush? background = LUIThemeColors.Brush(
                Prop(state, LUIProperty.BackgroundValue)?.AsString);
            Brush? foreground = LUIThemeColors.Brush(
                Prop(state, LUIProperty.ForegroundValue)?.AsString);
            Brush? border = LUIThemeColors.Brush(
                Prop(state, LUIProperty.BorderColorValue)?.AsString);
            double borderWidth = Prop(
                state, LUIProperty.BorderWidth)?.AsFloat ??
                (border == null ? 0 : 1);
            double radius = Prop(
                state, LUIProperty.CornerRadius)?.AsFloat ?? 0;

            switch (control)
            {
                case Border b:
                    if (background != null) b.Background = background;
                    b.BorderBrush = border;
                    b.BorderThickness = new Thickness(borderWidth);
                    b.CornerRadius = new CornerRadius(radius);
                    break;
                case Control ctl:
                    if (background != null) ctl.Background = background;
                    if (foreground != null) ctl.Foreground = foreground;
                    if (ctl is not Button)
                    {
                        ctl.BorderBrush = border;
                        ctl.BorderThickness = new Thickness(borderWidth);
                    }
                    ctl.CornerRadius = new CornerRadius(radius);
                    break;
                case TextBlock block:
                    if (foreground != null) block.Foreground = foreground;
                    break;
            }
            // Foreground on non-Control leaf controls.
            if (control is FontIcon icon && foreground != null)
            {
                icon.Foreground = foreground;
            }
        }

        static void ApplyAccessibility(
            FrameworkElement control, LUINodeState state)
        {
            string? label = Prop(
                state, LUIProperty.AccessibilityLabel)?.AsString;
            if (label != null)
            {
                AutomationProperties.SetName(control, label);
            }
            string? identifier = Prop(
                state, LUIProperty.AccessibilityIdentifier)?.AsString;
            if (identifier != null)
            {
                AutomationProperties.SetAutomationId(control, identifier);
            }
        }

        // ---- text ---------------------------------------------------------

        internal static void ApplyTextStyle(
            TextBlock block, LUINodeState state, bool isHeading)
        {
            double? headingLevel = Prop(
                state, LUIProperty.HeadingLevel)?.AsFloat;
            string? size = Prop(state, LUIProperty.SizeValue)?.AsString;
            double fontSize;
            if (isHeading || headingLevel != null)
            {
                fontSize = headingLevel switch
                {
                    1 => 28,
                    2 => 22,
                    3 => 18,
                    4 => 15,
                    5 => 13,
                    6 => 11,
                    _ => 20,
                };
                block.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
            }
            else
            {
                fontSize = size switch
                {
                    "sm" => 12,
                    "lg" => 18,
                    "heading" => 24,
                    "display" => 40,
                    _ => 14,
                };
            }
            block.FontSize = fontSize;

            string? alignment = Prop(
                state, LUIProperty.TextAlignment)?.AsString;
            block.TextAlignment = alignment switch
            {
                "center" => TextAlignment.Center,
                "right" or "end" => TextAlignment.Right,
                _ => TextAlignment.Left,
            };
        }

        // ---- buttons --------------------------------------------------------

        internal static object ButtonContent(LUINodeState state)
        {
            string text = Text(state);
            string? iconName = Prop(
                state, LUIProperty.InlineIconName)?.AsString ??
                Prop(state, LUIProperty.IconName)?.AsString;
            if (iconName == null)
            {
                return text;
            }
            var icon = new FontIcon
            {
                Glyph = LUIIconGlyphs.Glyph(iconName) ?? "",
                FontSize = 14,
                VerticalAlignment = VerticalAlignment.Center,
            };
            if (text.Length == 0)
            {
                return icon;
            }
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = GridLength.Auto,
            });
            grid.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(6),
            });
            grid.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = GridLength.Auto,
            });
            var label = new TextBlock { Text = text };
            string placement = Prop(
                state, LUIProperty.IconPlacementValue)?.AsString ??
                "leading";
            if (placement == "trailing")
            {
                Grid.SetColumn(label, 0);
                Grid.SetColumn(icon, 2);
            }
            else
            {
                Grid.SetColumn(icon, 0);
                Grid.SetColumn(label, 2);
            }
            grid.Children.Add(icon);
            grid.Children.Add(label);
            return grid;
        }

        internal static void ApplyButtonVariant(
            ButtonBase button, LUINodeState state)
        {
            string? variant = Prop(
                state, LUIProperty.VariantValue)?.AsString;
            if (variant == "primary" &&
                Application.Current?.Resources.TryGetValue(
                    "AccentButtonStyle", out object? style) == true &&
                style is Style accent)
            {
                button.Style = accent;
            }
        }

        // ---- track configuration --------------------------------------------

        // Configures a grid as a horizontal (Row) or vertical (Column) flex
        // container: one track per child, `grow` -> star, `gap` -> spacing.
        internal static void ConfigureFlexTracks(
            LUIGrid grid, bool horizontal, LUINodeState state,
            LUISyncContext context)
        {
            var children = context.InlineChildrenOf(state);
            double gap = Prop(state, LUIProperty.Gap)?.AsFloat ?? 0;
            if (horizontal)
            {
                grid.RowDefinitions.Clear();
                grid.ColumnSpacing = gap;
                grid.ColumnDefinitions.Clear();
                foreach (long childId in children)
                {
                    double grow = ChildGrow(context, childId);
                    grid.ColumnDefinitions.Add(new ColumnDefinition
                    {
                        Width = grow > 0
                            ? new GridLength(grow, GridUnitType.Star)
                            : GridLength.Auto,
                    });
                }
            }
            else
            {
                grid.ColumnDefinitions.Clear();
                grid.RowSpacing = gap;
                grid.RowDefinitions.Clear();
                foreach (long childId in children)
                {
                    double grow = ChildGrow(context, childId);
                    grid.RowDefinitions.Add(new RowDefinition
                    {
                        Height = grow > 0
                            ? new GridLength(grow, GridUnitType.Star)
                            : GridLength.Auto,
                    });
                }
            }
        }

        static double ChildGrow(LUISyncContext context, long childId)
        {
            if (context.Backend.States.TryGetValue(
                    childId, out LUINodeState? child))
            {
                return Prop(child, LUIProperty.GrowValue)?.AsFloat ?? 0;
            }
            return 0;
        }

        // Grid kind: `grid-columns` columns, children flow row-major.
        internal static void ConfigureGridTracks(
            LUIGrid grid, LUINodeState state, LUISyncContext context)
        {
            int columns = (int)(Prop(
                state, LUIProperty.GridColumns)?.AsInt ?? 1);
            if (columns < 1) columns = 1;
            var children = context.InlineChildrenOf(state);
            int rows = (children.Count + columns - 1) / columns;
            double gap = Prop(state, LUIProperty.Gap)?.AsFloat ?? 0;
            grid.ColumnSpacing = gap;
            grid.RowSpacing = gap;
            grid.ColumnDefinitions.Clear();
            for (int i = 0; i < columns; i++)
            {
                grid.ColumnDefinitions.Add(new ColumnDefinition
                {
                    Width = new GridLength(1, GridUnitType.Star),
                });
            }
            grid.RowDefinitions.Clear();
            for (int i = 0; i < rows; i++)
            {
                grid.RowDefinitions.Add(new RowDefinition
                {
                    Height = GridLength.Auto,
                });
            }
        }
    }
}
