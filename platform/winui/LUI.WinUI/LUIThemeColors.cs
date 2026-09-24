// Semantic color names from the wire protocol mapped onto WinUI theme
// resources (with literal fallbacks matching the fluent defaults).

using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace LUI.WinUI
{
    public static class LUIThemeColors
    {
        public static SolidColorBrush? Brush(string? name)
        {
            if (name == null) return null;
            switch (name.ToLowerInvariant())
            {
                case "transparent":
                    return new SolidColorBrush(Colors.Transparent);
                case "background":
                    return Resource("LayerFillColorDefaultBrush",
                        Color.FromArgb(0xFF, 0xF9, 0xF9, 0xF9));
                case "foreground":
                    return Resource("TextFillColorPrimaryBrush",
                        Color.FromArgb(0xE4, 0x1B, 0x1B, 0x1B));
                case "primary":
                    return Resource("AccentFillColorDefaultBrush",
                        Color.FromArgb(0xFF, 0x00, 0x62, 0xB0));
                case "primary-foreground":
                    return Resource("TextOnAccentFillColorPrimaryBrush",
                        Colors.White);
                case "secondary":
                    return Resource("CardBackgroundFillColorSecondaryBrush",
                        Color.FromArgb(0x80, 0xF6, 0xF6, 0xF6));
                case "glass":
                    return Resource("AcrylicBackgroundFillColorDefaultBrush",
                        Color.FromArgb(0xCC, 0xF9, 0xF9, 0xF9));
                case "secondary-foreground":
                    return Resource("TextFillColorSecondaryBrush",
                        Color.FromArgb(0x9E, 0x1B, 0x1B, 0x1B));
                case "success":
                    return new SolidColorBrush(
                        Color.FromArgb(0xFF, 0xD2, 0xF2, 0xD2));
                case "success-foreground":
                    return new SolidColorBrush(
                        Color.FromArgb(0xFF, 0x0F, 0x6B, 0x0F));
                case "warning":
                    return new SolidColorBrush(
                        Color.FromArgb(0xFF, 0xFF, 0xF4, 0xCE));
                case "warning-foreground":
                    return new SolidColorBrush(
                        Color.FromArgb(0xFF, 0x8D, 0x51, 0x00));
                case "error":
                    return Resource("SystemFillColorCriticalBackgroundBrush",
                        Color.FromArgb(0xFF, 0xFD, 0xE7, 0xE9));
                case "error-foreground":
                    return Resource("SystemFillColorCriticalBrush",
                        Color.FromArgb(0xFF, 0xC4, 0x2B, 0x1C));
                case "border":
                    return Resource("CardStrokeColorDefaultBrush",
                        Color.FromArgb(0x0F, 0x00, 0x00, 0x00));
                case "black":
                    return new SolidColorBrush(Colors.Black);
                case "white":
                    return new SolidColorBrush(Colors.White);
                case "red":
                    return new SolidColorBrush(Colors.Red);
                case "blue":
                    return new SolidColorBrush(Colors.Blue);
                case "green":
                    return new SolidColorBrush(Colors.Green);
                default:
                    return new SolidColorBrush(Colors.Transparent);
            }
        }

        static SolidColorBrush Resource(string key, Color fallback)
        {
            if (Application.Current?.Resources.TryGetValue(
                    key, out object? value) == true &&
                value is SolidColorBrush brush)
            {
                return brush;
            }
            return new SolidColorBrush(fallback);
        }
    }
}
