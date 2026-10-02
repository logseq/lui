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

        void Position(FrameworkElement control, LUINodeState state)
        {
            switch (state.Kind)
            {
                case LUINodeKind.Dialog:
                    control.HorizontalAlignment = HorizontalAlignment.Center;
                    control.VerticalAlignment = VerticalAlignment.Center;
                    control.MaxWidth = 520;
                    control.Margin = new Thickness(24);
                    var dialogShadow = new ThemeShadow();
                    dialogShadow.Receivers.Add(_overlay);
                    control.Shadow = dialogShadow;
                    control.Translation =
                        new System.Numerics.Vector3(0, 0, 32);
                    break;
                case LUINodeKind.Sheet:
                {
                    control.VerticalAlignment = VerticalAlignment.Bottom;
                    // detents: comma-separated medium|large|fraction —
                    // the sheet opens at the first detent and can grow to
                    // the largest (medium = 0.5, large = 1.0 of the
                    // overlay). sizing: form/fitted center the sheet at a
                    // fixed width; page stretches edge to edge.
                    double overlayHeight = _overlay.ActualHeight > 0
                        ? _overlay.ActualHeight : 480;
                    double restFraction = 0.0, maxFraction = 0.0;
                    string? detents = LUIPropertyApplier.Prop(
                        state, LUIProperty.Detents)?.AsString;
                    if (detents != null)
                    {
                        bool first = true;
                        foreach (string token in detents.Split(','))
                        {
                            string trimmed = token.Trim();
                            double fraction =
                                trimmed == "medium" ? 0.5 :
                                trimmed == "large" ? 1.0 :
                                (double.TryParse(
                                    trimmed,
                                    System.Globalization.NumberStyles.Float,
                                    System.Globalization.CultureInfo
                                        .InvariantCulture,
                                    out double parsed) &&
                                 parsed > 0.0 && parsed <= 1.0
                                    ? parsed : -1.0);
                            if (fraction > 0.0)
                            {
                                if (first)
                                {
                                    restFraction = fraction;
                                    first = false;
                                }
                                if (fraction > maxFraction)
                                {
                                    maxFraction = fraction;
                                }
                            }
                        }
                    }
                    string? sizing = LUIPropertyApplier.Prop(
                        state, LUIProperty.Sizing)?.AsString;
                    if (sizing == "form" || sizing == "fitted")
                    {
                        control.HorizontalAlignment =
                            HorizontalAlignment.Center;
                        control.MaxWidth = 640;
                    }
                    else
                    {
                        control.HorizontalAlignment =
                            HorizontalAlignment.Stretch;
                    }
                    control.MinHeight = overlayHeight * restFraction;
                    control.MaxHeight = maxFraction > 0.0
                        ? overlayHeight * maxFraction : 480;
                    var sheetShadow = new ThemeShadow();
                    sheetShadow.Receivers.Add(_overlay);
                    control.Shadow = sheetShadow;
                    control.Translation =
                        new System.Numerics.Vector3(0, 0, 32);
                    break;
                }
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
