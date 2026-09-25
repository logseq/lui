using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.XamlTypeInfo;

namespace LUI.Demo
{
    public class App : Application, IXamlMetadataProvider
    {
        // No .xaml: the demo compiles its visual tree entirely in code
        // so the project also builds without the Windows-only XAML
        // compiler task. Application.Resources must be touched in
        // OnLaunched — inside the Application.Start init callback it
        // returns E_UNEXPECTED and the app fail-fasts.
        //
        // The XAML compiler would normally generate the
        // IXamlMetadataProvider implementation from App.xaml.
        // Without it, activating XamlControlsResources fails to resolve
        // control theme resources (E_FAIL "Cannot find a resource with
        // the given key: AcrylicBackgroundFillColorDefaultBrush"), so
        // it is implemented here by delegating to the provider WASDK
        // ships for the controls library.
        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            Resources.MergedDictionaries.Add(new XamlControlsResources());
            _window = new MainWindow();
            _window.Activate();
        }

        public IXamlType GetXamlType(string fullName) => _provider.GetXamlType(fullName);

        public IXamlType GetXamlType(System.Type type) => _provider.GetXamlType(type);

        public XmlnsDefinition[] GetXmlnsDefinitions() => _provider.GetXmlnsDefinitions();

        private readonly XamlControlsXamlMetaDataProvider _provider = new();

        Window? _window;
    }
}
