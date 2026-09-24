using System;
using Microsoft.UI.Xaml;

namespace LUI.Demo
{
    public static class Program
    {
        // Unpackaged app entry point: initialize the WinRT wrappers before
        // starting the application message loop.
        [STAThread]
        static int Main(string[] args)
        {
            WinRT.ComWrappersSupport.InitializeComWrappers();
            Application.Start(p => new App());
            return 0;
        }
    }
}
