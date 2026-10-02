// Root surface hosted by the app: a Grid whose bottom layer renders the
// root node and whose top layer is the modal/flyout overlay owned by
// LUIModalPresenter.

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace LUI.WinUI
{
    public sealed class LUIWinUIRoot : Grid
    {
        internal LUIWinUIRoot()
        {
            // Fluent "layer" backdrop under everything the wire renders —
            // cards and dialogs sit on this fill like a WinUI window.
            Background = new SolidColorBrush(
                Windows.UI.Color.FromArgb(0xFF, 0xF9, 0xF9, 0xF9));
            var content = new LUIGrid();
            var overlay = new Grid { Visibility = Visibility.Collapsed };
            overlay.IsHitTestVisible = true;
            Children.Add(content);
            Children.Add(overlay);
            Content = content;
            Overlay = overlay;
        }

        internal LUIGrid Content { get; }
        internal Grid Overlay { get; }
    }
}
