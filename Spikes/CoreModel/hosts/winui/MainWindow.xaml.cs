using System;
using System.Collections.Generic;
using System.Linq;
using Compositor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CoreModelWinUI
{
    // A test window, not Compositor's UI: a layer list and a few buttons, all through LayerDocument (the C# side of
    // include/compositor_core.h).
    public sealed partial class MainWindow : Window
    {
#if CPP_CORE
        public const string CoreName = "C++ Core (CompositorCoreCpp.dll)";
#else
        public const string CoreName = "Swift Core (CompositorCore.dll)";
#endif
        private readonly LayerDocument document = new LayerDocument(1920, 1080);
        private List<OutlineRow> rows = new List<OutlineRow>();
        private int added;

        public MainWindow(string selfTestFolder)
        {
            InitializeComponent();
            Title = "Compositor Core spike — " + CoreName;
            Header.Text = CoreName;
            AppWindow.Resize(new Windows.Graphics.SizeInt32(900, 640));
            Closed += (sender, args) => document.Dispose();

            ulong background = document.AddLayer("배경");
            ulong sky = document.AddLayer("하늘");
            ulong people = document.AddLayer("People");
            document.Group(new[] { sky, people }, "보정 그룹");
            document.Rename(people, "인물 레이어");
            Refresh();

            if (selfTestFolder != null)
            {
                bool started = false;
                Activated += async (sender, args) =>
                {
                    if (started) return;
                    started = true;
                    int failures = await SelfTest.RunAsync(this, selfTestFolder);
                    Environment.Exit(failures);
                };
            }
        }

        internal LayerDocument Document => document;
        internal ListView LayerList => Layers;
        internal FrameworkElement RootElement => Root;
        internal IReadOnlyList<OutlineRow> Rows => rows;

        internal void Refresh()
        {
            rows = document.Outline();
            Layers.ItemsSource = rows.Select(Describe).ToList();
            string undo = document.UndoName;
            Status.Text = rows.Count + " rows · Undo: " + (undo ?? "—");
        }

        internal static string Describe(OutlineRow row)
        {
            return new string(' ', row.Depth * 4) + (row.IsGroup ? "▸ " : "• ") + row.Name + (row.IsVisible ? "" : "  (hidden)");
        }

        private void AddLayer(object sender, RoutedEventArgs e)
        {
            document.AddLayer("레이어 " + (++added));
            Refresh();
        }

        private void GroupTopTwo(object sender, RoutedEventArgs e)
        {
            var top = rows.Where(r => r.Depth == 0).Take(2).Select(r => r.Id).ToList();
            if (top.Count == 2)
            {
                try { document.Group(top, "그룹"); } catch (InvalidOperationException) { }
            }
            Refresh();
        }

        private void ToggleSelected(object sender, RoutedEventArgs e)
        {
            int index = Layers.SelectedIndex;
            if (index < 0 || index >= rows.Count) return;
            document.SetVisible(rows[index].Id, !rows[index].IsVisible);
            Refresh();
            Layers.SelectedIndex = index;
        }

        private void Undo(object sender, RoutedEventArgs e) { document.Undo(); Refresh(); }
        private void Redo(object sender, RoutedEventArgs e) { document.Redo(); Refresh(); }
    }
}
