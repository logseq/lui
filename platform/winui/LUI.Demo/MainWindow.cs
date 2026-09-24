using LUI.WinUI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace LUI.Demo
{
    public sealed class MainWindow : Window
    {
        public MainWindow()
        {
            Title = "LUI WinUI Demo";
            _host = new LUIWinUIHost();
            try
            {
                // The embedded OCaml runtime emits the initial patch batch
                // through the bridge; gestures flow back via lui_ocaml_*.
                _host.Start();
                Content = _host.Root;
            }
            catch (System.Exception error)
            {
                // The native lui_ocaml_bridge library must be built first
                // (see platform/native/ and the README). Surface the failure
                // instead of crashing so the window still opens.
                Content = new TextBlock
                {
                    Text = $"OCaml runtime unavailable: {error.Message}",
                    TextWrapping = TextWrapping.Wrap,
                    Margin = new Thickness(24),
                };
            }
            Closed += (_, _) => _host.Dispose();
        }

        readonly LUIWinUIHost _host;
    }
}
