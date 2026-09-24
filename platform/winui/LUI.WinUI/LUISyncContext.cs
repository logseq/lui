// Context passed to every element during a sync pass: access to the
// protocol backend (for child states and event entry points) and to the
// element map (for resolving child ids to controls).

using System.Collections.Generic;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;

namespace LUI.WinUI
{
    public sealed class LUISyncContext
    {
        internal LUISyncContext(LUIWinUIBackend host, LUIBackend backend)
        {
            Host = host;
            Backend = backend;
        }

        internal LUIWinUIBackend Host { get; }
        public LUIBackend Backend { get; }

        // Image and media-surface registries are owned by the host app:
        // register decoded bitmaps and presenter elements by the ids the
        // runtime references in `image` / `surface` properties.
        public Dictionary<long, BitmapSource> Images { get; } =
            new Dictionary<long, BitmapSource>();
        public Dictionary<long, FrameworkElement> Surfaces { get; } =
            new Dictionary<long, FrameworkElement>();

        internal LUIElement ElementFor(long id) => Host.ElementFor(id);

        // Children ids that render inline inside the parent. Overlay kinds
        // (dropdown/context menus, tooltips, modal surfaces, toasts) are
        // excluded — the parent's sync or the root presenter attaches them.
        internal IReadOnlyList<long> InlineChildrenOf(LUINodeState state)
        {
            var inline = new List<long>();
            foreach (long childId in state.Children)
            {
                if (Backend.States.TryGetValue(
                        childId, out LUINodeState? child))
                {
                    if (IsOverlayKind(child.Kind, state.Kind))
                    {
                        continue;
                    }
                    inline.Add(childId);
                }
                else if (Backend.ExtensionStates.ContainsKey(childId))
                {
                    inline.Add(childId);
                }
            }
            return inline;
        }

        static bool IsOverlayKind(LUINodeKind kind, LUINodeKind parentKind)
        {
            switch (kind)
            {
                case LUINodeKind.ContextMenu:
                case LUINodeKind.Toast:
                    return true;
                case LUINodeKind.Tooltip:
                    // Only `stack` treats tooltip children as overlays;
                    // other containers render them as inline text.
                    return parentKind == LUINodeKind.Stack;
                case LUINodeKind.DropdownMenu:
                    return parentKind == LUINodeKind.Stack;
                default:
                    return LUISchema.ModalSurface(kind);
            }
        }
    }
}
