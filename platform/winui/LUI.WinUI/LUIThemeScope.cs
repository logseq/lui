// Scoped theme tokens: a `theme` prop (flat JSON string/string map) on a
// node defines a token table covering that node and its descendants; color
// resolution walks wire ancestors so the nearest scope wins before the
// platform theme resources in LUIThemeColors. `theme-mode` maps onto the
// rendered element's RequestedTheme.

using System.Collections.Generic;
using System.Text.Json;
using Microsoft.UI.Xaml;

namespace LUI.WinUI
{
    public static class LUIThemeScope
    {
        /// Decodes the `theme` wire prop. Entries are lower-cased so lookup
        /// matches semantic names case-insensitively; values stay strings —
        /// non-color tokens may join the table later.
        public static Dictionary<string, string>? Parse(string? json)
        {
            if (string.IsNullOrEmpty(json)) return null;
            try
            {
                using var document = JsonDocument.Parse(json);
                if (document.RootElement.ValueKind != JsonValueKind.Object)
                    return null;
                var tokens = new Dictionary<string, string>();
                foreach (JsonProperty entry in
                    document.RootElement.EnumerateObject())
                {
                    if (entry.Value.ValueKind == JsonValueKind.String)
                    {
                        tokens[entry.Name.ToLowerInvariant()] =
                            entry.Value.GetString() ?? "";
                    }
                }
                return tokens;
            }
            catch (JsonException)
            {
                return null;
            }
        }

        /// Nearest-scope token lookup: the node's own `theme` prop first,
        /// then each wire ancestor's, so a themed subtree overrides the
        /// app-level theme.
        public static string? Token(
            LUISyncContext context, LUINodeState? state, string? name)
        {
            if (state == null || name == null) return null;
            string key = name.ToLowerInvariant();
            for (LUINodeState? current = state; current != null;)
            {
                if (current.Properties.TryGetValue(
                        LUIProperty.ThemeValue, out LUIWireValue? theme) &&
                    Parse(theme?.AsString)?.TryGetValue(
                        key, out string? value) == true)
                {
                    return value;
                }
                current = current.Parent is long parentId &&
                    context.Backend.States.TryGetValue(
                        parentId, out LUINodeState? parent)
                        ? parent
                        : null;
            }
            return null;
        }
    }
}
