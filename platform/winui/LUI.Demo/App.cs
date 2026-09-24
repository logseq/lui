using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace LUI.Demo
{
    public class App : Application
    {
        // No .xaml: the demo compiles its visual tree entirely in code
        // so the project also builds without the Windows-only XAML
        // compiler task. Application.Resources must be touched in
        // OnLaunched — inside the Application.Start init callback it
        // returns E_UNEXPECTED and the app fail-fasts.
        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            Resources.MergedDictionaries.Add(new XamlControlsResources());
            _window = new MainWindow();
            _window.Activate();
        }

        Window? _window;
    }
}
