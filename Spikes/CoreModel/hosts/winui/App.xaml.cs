using System;
using Microsoft.UI.Xaml;

namespace CoreModelWinUI
{
    public partial class App : Application
    {
        private MainWindow window;

        public App()
        {
            InitializeComponent();
        }

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            // `selftest <folder>`: check everything, write the results there, and exit.
            string[] arguments = Environment.GetCommandLineArgs();
            int at = Array.IndexOf(arguments, "selftest");
            string selfTestFolder = at >= 0 && at + 1 < arguments.Length ? arguments[at + 1] : null;
            window = new MainWindow(selfTestFolder);
            window.Activate();
        }
    }
}
