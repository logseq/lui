// Builds WinUI MenuFlyout trees from dropdownMenu/contextMenu node states
// and ToolTip content from tooltip nodes. MenuItem children that contain a
// nested dropdownMenu become MenuFlyoutSubItems.

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;

namespace LUI.WinUI
{
    internal static class LUIMenuBuilder
    {
        public static FlyoutBase Build(
            LUISyncContext context, long menuId, LUINodeState menu)
        {
            var flyout = new MenuFlyout();
            Fill(context, flyout.Items, menu);
            flyout.Closed += (_, _) =>
            {
                try
                {
                    context.Backend.PerformDismiss(menuId);
                }
                catch (LUIBackendException)
                {
                    // Dismissal is best-effort when the node was removed.
                }
            };
            return flyout;
        }

        public static void Fill(
            LUISyncContext context,
            System.Collections.Generic.IList<MenuFlyoutItemBase> items,
            LUINodeState menu)
        {
            items.Clear();
            foreach (long childId in menu.Children)
            {
                if (!context.Backend.States.TryGetValue(
                        childId, out LUINodeState? child))
                {
                    continue;
                }
                items.Add(Item(context, childId, child));
            }
        }

        static MenuFlyoutItemBase Item(
            LUISyncContext context, long stateId, LUINodeState state)
        {
            switch (state.Kind)
            {
                case LUINodeKind.Divider:
                    return new MenuFlyoutSeparator();
                case LUINodeKind.MenuItem:
                    break;
                default:
                    // Non-menu children still render as disabled rows so the
                    // menu stays structurally complete.
                    return new MenuFlyoutItem
                    {
                        Text = LUIPropertyApplier.Text(state),
                        IsEnabled = false,
                    };
            }

            // menuItem: possibly a submenu host when it contains a
            // dropdownMenu child.
            string text = LUIPropertyApplier.Text(state);
            bool enabled = LUIPropertyApplier.Prop(
                state, LUIProperty.Enabled)?.AsBool ?? true;
            string? iconName = LUIPropertyApplier.Prop(
                state, LUIProperty.IconName)?.AsString ??
                LUIPropertyApplier.Prop(
                    state, LUIProperty.InlineIconName)?.AsString;
            IconElement? icon = iconName == null
                ? null
                : new FontIcon
                {
                    Glyph = LUIIconGlyphs.Glyph(iconName) ?? "",
                };

            LUINodeState? submenu = null;
            foreach (long childId in state.Children)
            {
                if (context.Backend.States.TryGetValue(
                        childId, out LUINodeState? child) &&
                    child.Kind == LUINodeKind.DropdownMenu)
                {
                    submenu = child;
                    break;
                }
            }

            if (submenu != null)
            {
                var sub = new MenuFlyoutSubItem
                {
                    Text = text,
                    IsEnabled = enabled,
                    Icon = icon,
                };
                Fill(context, sub.Items, submenu);
                return sub;
            }

            var item = new MenuFlyoutItem
            {
                Text = text,
                IsEnabled = enabled,
                Icon = icon,
            };
            item.Click += (_, _) =>
            {
                try
                {
                    context.Backend.PerformAction(stateId);
                }
                catch (LUIBackendException)
                {
                    // Menu items that lose their gate are no-ops.
                }
            };
            return item;
        }

        public static ToolTip BuildToolTip(LUINodeState tooltip)
        {
            return new ToolTip
            {
                Content = LUIPropertyApplier.Text(tooltip),
            };
        }
    }
}
