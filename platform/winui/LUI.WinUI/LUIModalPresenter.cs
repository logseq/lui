// Presents modal surfaces (dialog, sheet, drawer) and toasts from node
// state inside a full-size overlay Grid at the root. The element's own
// control renders the surface body — the presenter only positions it:
// dialog -> centered card, sheet -> bottom edge, drawer -> right edge,
// toast -> stacked InfoBar at the top edge. Backdrop taps, close buttons,
// and toast durations all route through PerformDismiss.

using System.Collections.Generic;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace LUI.WinUI
{
    internal sealed class LUIModalPresenter
    {
        readonly Grid _overlay;
        readonly LUISyncContext _context;
        readonly List<long> _presented = new List<long>();

        internal LUIModalPresenter(Grid overlay, LUISyncContext context)
        {
            _overlay = overlay;
            _context = context;
            _overlay.Background = new SolidColorBrush(
                Windows.UI.Color.FromArgb(0x66, 0x00, 0x00, 0x00));
            _overlay.Tapped += (_, _) =>
            {
                foreach (long id in new List<long>(_presented))
                {
                    try
                    {
                        _context.Backend.PerformDismiss(id);
                    }
                    catch (LUIBackendException)
                    {
                    }
                }
            };
        }

        internal void Sync(IReadOnlyList<long> surfaceIds)
        {
            var want = new HashSet<long>(surfaceIds);
            for (int i = _presented.Count - 1; i >= 0; i--)
            {
                if (!want.Contains(_presented[i]))
                {
                    LUIElement element = _context.ElementFor(_presented[i]);
                    _overlay.Children.Remove(element.Control);
                    _presented.RemoveAt(i);
                }
            }
            foreach (long id in surfaceIds)
            {
                if (!_context.Backend.States.TryGetValue(
                        id, out LUINodeState? state))
                {
                    continue;
                }
                LUIElement element = _context.ElementFor(id);
                element.Sync(state, _context);
                if (!_presented.Contains(id))
                {
                    Position(element.Control, state);
                    if (element.Control is InfoBar toast)
                    {
                        toast.IsOpen = true;
                        toast.CloseButtonClick += (_, _) =>
                        {
                            try
                            {
                                _context.Backend.PerformDismiss(id);
                            }
                            catch (LUIBackendException)
                            {
                            }
                        };
                    }
                    _overlay.Children.Add(element.Control);
                    _presented.Add(id);
                }
            }
            _overlay.Visibility = _presented.Count == 0
                ? Visibility.Collapsed
                : Visibility.Visible;
        }

        static void Position(FrameworkElement control, LUINodeState state)
        {
            switch (state.Kind)
            {
                case LUINodeKind.Dialog:
                    control.HorizontalAlignment = HorizontalAlignment.Center;
                    control.VerticalAlignment = VerticalAlignment.Center;
                    control.MaxWidth = 520;
                    control.Margin = new Thickness(24);
                    break;
                case LUINodeKind.Sheet:
                    control.HorizontalAlignment =
                        HorizontalAlignment.Stretch;
                    control.VerticalAlignment = VerticalAlignment.Bottom;
                    control.MaxHeight = 480;
                    break;
                case LUINodeKind.Drawer:
                    control.HorizontalAlignment = HorizontalAlignment.Right;
                    control.VerticalAlignment = VerticalAlignment.Stretch;
                    control.Width = 320;
                    break;
                case LUINodeKind.Toast:
                    control.HorizontalAlignment =
                        HorizontalAlignment.Center;
                    control.VerticalAlignment = VerticalAlignment.Top;
                    control.Margin = new Thickness(0, 12, 0, 0);
                    break;
            }
        }

        internal void Clear()
        {
            _presented.Clear();
            _overlay.Children.Clear();
        }
    }
}
