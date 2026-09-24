// Wire icon names -> Segoe Fluent Icons codepoints. The built-in names
// mirror the vocabulary in src/lui_protocol.ml; "app:<slug>" names are
// custom and resolve through a caller-supplied glyph provider.

using System.Collections.Generic;

namespace LUI.WinUI
{
    public static class LUIIconGlyphs
    {
        static readonly IReadOnlyDictionary<string, string> BuiltIn =
            new Dictionary<string, string>
            {
                ["alert"] = "\uE7BA",
                ["archive"] = "\uE7B8",
                ["arrow-down"] = "\uE74B",
                ["arrow-right"] = "\uE72A",
                ["arrow-up"] = "\uE74A",
                ["check"] = "\uE73E",
                ["check-circle"] = "\uE930",
                ["chevron-down"] = "\uE70D",
                ["chevron-left"] = "\uE76B",
                ["chevron-right"] = "\uE76C",
                ["chevron-up"] = "\uE70E",
                ["circle-dot"] = "\uE91F",
                ["clock"] = "\uE917",
                ["copy"] = "\uE8C8",
                ["download"] = "\uE896",
                ["edit"] = "\uE70F",
                ["ellipsis"] = "\uE712",
                ["external-link"] = "\uE8A7",
                ["eye"] = "\uE7B3",
                ["file-text"] = "\uE8A5",
                ["folder"] = "\uE8B7",
                ["folder-open"] = "\uE838",
                ["git-branch"] = "\uF2A4",
                ["git-merge"] = "\uF2A5",
                ["git-pull-request"] = "\uF2A6",
                ["info"] = "\uE946",
                ["menu"] = "\uE700",
                ["mic"] = "\uE720",
                ["moon"] = "\uE708",
                ["music"] = "\uE8D6",
                ["panel-left"] = "\uF2C1",
                ["panel-right"] = "\uF2C2",
                ["pause"] = "\uE769",
                ["play"] = "\uE768",
                ["plus"] = "\uE710",
                ["refresh-cw"] = "\uE72C",
                ["repeat"] = "\uE8EE",
                ["save"] = "\uE74E",
                ["search"] = "\uE721",
                ["send"] = "\uE724",
                ["settings"] = "\uE713",
                ["shuffle"] = "\uE8B1",
                ["skip-back"] = "\uE892",
                ["skip-forward"] = "\uE893",
                ["sun"] = "\uE706",
                ["terminal"] = "\uE756",
                ["trash"] = "\uE74D",
                ["volume"] = "\uE767",
                ["wrench"] = "\uE90F",
                ["x"] = "\uE711",
                ["x-circle"] = "\uE711",
            };

        // Returns the Segoe Fluent Icons glyph for a built-in name, or null
        // for custom "app:<slug>" icons (resolved by the host app).
        public static string? Glyph(string name) =>
            BuiltIn.TryGetValue(name, out string? glyph) ? glyph : null;
    }
}
