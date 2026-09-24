using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace LUI.Demo
{
    public class App : Application
    {
        public App()
        {
            // No .xaml: the demo compiles its visual tree entirely in code
            // so the project also builds without the Windows-only XAML
            // compiler task.
            Resources.MergedDictionaries.Add(new XamlControlsResources());
        }

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            _window = new MainWindow();
            _window.Activate();
        }

        Window? _window;
    }
}
