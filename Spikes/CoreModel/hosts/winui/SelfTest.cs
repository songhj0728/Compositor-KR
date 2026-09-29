using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Text;
using System.Threading.Tasks;
using Compositor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace CoreModelWinUI
{
    // Runs inside the WinUI process, on its UI thread, once the window is up: the spike's questions as checks.
    internal static class SelfTest
    {
        public static async Task<int> RunAsync(MainWindow window, string folder)
        {
            Directory.CreateDirectory(folder);
            var report = new List<string>();
            int failures = 0;
            void Check(bool ok, string name, string detail = "")
            {
                if (!ok) failures++;
                report.Add((ok ? "PASS " : "FAIL ") + name + (detail.Length > 0 ? " — " + detail : ""));
            }
            void Info(string text) { report.Add("INFO " + text); }

            try
            {
                Info("core: " + MainWindow.CoreName);
                Info(".NET runtime: " + Environment.Version);
                // RuntimeInfo throws in a self-contained app (it wants Microsoft.WindowsAppRuntime.Insights.Resource.dll,
                // which isn't deployed), so read the runtime's file versions instead.
                foreach (string dll in new[] { "Microsoft.WindowsAppRuntime.dll", "Microsoft.ui.xaml.dll" })
                {
                    string path = Path.Combine(AppContext.BaseDirectory, dll);
                    Info(dll + ": " + (File.Exists(path) ? FileVersionInfo.GetVersionInfo(path).FileVersion : "not in the app folder"));
                }
                Info("OS: " + Environment.OSVersion.VersionString);

                // 1. The window is up.
                Check(window.AppWindow.IsVisible, "window activated and visible", window.Title);

                // 2. Core calls from the UI thread, including Korean names.
                bool uiThread = window.DispatcherQueue.HasThreadAccess;
                var rows = window.Rows;
                Check(uiThread && rows.Count == 4 && rows[0].IsGroup && rows[0].Name == "보정 그룹" && rows[3].Name == "배경",
                      "C# → C ABI → Core on the UI thread",
                      string.Join(" | ", rows.Select(r => new string('>', r.Depth) + r.Name)));

                // 3. The list shows what the Core returned.
                var list = window.LayerList;
                ListViewItem first = null;
                for (int i = 0; i < 50 && first == null; i++)
                {
                    await Task.Delay(100);
                    first = list.ContainerFromIndex(0) as ListViewItem;
                }
                string shown = first?.Content as string;
                Check(first != null && first.ActualHeight > 0 && shown != null && shown.Contains("보정 그룹"),
                      "ListView renders the Core's rows", shown ?? "no container");

                // 4. Buttons, pressed through UI Automation, change the Core and the list.
                var root = (Panel)window.RootElement;
                var buttons = root.Children.OfType<StackPanel>().First().Children.OfType<Button>().ToList();
                Button Find(string label) { return buttons.First(b => (string)b.Content == label); }
                void Press(Button b) { new ButtonAutomationPeer(b).Invoke(); }
                int before = window.Rows.Count;
                Press(Find("Add Layer"));
                bool added = window.Rows.Count == before + 1 && window.Document.UndoName == "Add Layer" && window.Rows[0].Name == "레이어 1";
                Press(Find("Undo"));
                bool undone = window.Rows.Count == before;
                Press(Find("Redo"));
                bool redone = window.Rows.Count == before + 1;
                Check(added && undone && redone, "buttons → Core → list (add, undo, redo)",
                      $"rows {before} → {before + 1} → {before} → {window.Rows.Count}");

                // 5. A Core used from a background thread, results brought back to the UI thread.
                var background = await Task.Run(() =>
                {
                    bool offUi = !window.DispatcherQueue.HasThreadAccess;
                    using (var doc = new LayerDocument(4000, 3000))
                    {
                        for (int i = 0; i < 500; i++) doc.AddLayer("백그라운드 " + i);
                        return (offUi, count: doc.Outline().Count, top: doc.Outline()[0].Name);
                    }
                });
                Check(background.offUi && background.count == 500 && background.top == "백그라운드 499" && window.DispatcherQueue.HasThreadAccess,
                      "Core on a background thread, result back on the UI thread", $"{background.count} rows, top '{background.top}'");

                // 6. Cost of the boundary as written: every outline row is a separate call that rebuilds the outline.
                foreach (int n in new[] { 500, 2000 })
                {
                    using (var doc = new LayerDocument(4000, 3000))
                    {
                        var watch = Stopwatch.StartNew();
                        for (int i = 0; i < n; i++) doc.AddLayer("L" + i);
                        double addMs = watch.Elapsed.TotalMilliseconds;
                        watch.Restart();
                        int count = doc.Outline().Count;
                        double outlineMs = watch.Elapsed.TotalMilliseconds;
                        Info($"{n} layers: adding {addMs:F1} ms ({addMs / n * 1000:F1} µs each, undo step each); " +
                             $"reading the outline row by row {outlineMs:F1} ms ({count} rows)");
                    }
                }

                // 7. Which DLLs this process actually loaded, and from where.
                string appFolder = AppContext.BaseDirectory.TrimEnd('\\');
                foreach (ProcessModule module in Process.GetCurrentProcess().Modules)
                {
                    string name = module.ModuleName;
                    if (name.StartsWith("CompositorCore", StringComparison.OrdinalIgnoreCase) || name.StartsWith("swift", StringComparison.OrdinalIgnoreCase)
                        || name.StartsWith("Microsoft.ui.xaml", StringComparison.OrdinalIgnoreCase) || name.StartsWith("Microsoft.WindowsAppRuntime", StringComparison.OrdinalIgnoreCase)
                        || name.StartsWith("vcruntime", StringComparison.OrdinalIgnoreCase) || name.StartsWith("msvcp", StringComparison.OrdinalIgnoreCase))
                    {
                        string where = Path.GetDirectoryName(module.FileName).Equals(appFolder, StringComparison.OrdinalIgnoreCase) ? "app folder" : module.FileName;
                        Info("loaded " + name + " from " + where);
                    }
                }

                // 8. A picture of the window, as XAML rendered it.
                var bitmap = new RenderTargetBitmap();
                await bitmap.RenderAsync(window.RootElement);
                byte[] pixels = (await bitmap.GetPixelsAsync()).ToArray();
                using (var stream = new InMemoryRandomAccessStream())
                {
                    var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
                    encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, (uint)bitmap.PixelWidth,
                                         (uint)bitmap.PixelHeight, 96, 96, pixels);
                    await encoder.FlushAsync();
                    stream.Seek(0);
                    using (var file = File.Create(Path.Combine(folder, "window.png")))
                        await stream.AsStreamForRead().CopyToAsync(file);
                }
                Check(bitmap.PixelWidth > 0 && pixels.Any(b => b != 0), "window rendered to window.png",
                      $"{bitmap.PixelWidth}×{bitmap.PixelHeight}");
            }
            catch (Exception error)
            {
                failures++;
                report.Add("FAIL unexpected exception — " + error);
            }

            report.Add(failures == 0 ? "RESULT all checks passed" : $"RESULT {failures} check(s) failed");
            File.WriteAllLines(Path.Combine(folder, "selftest.txt"), report, new UTF8Encoding(false));
            return failures;
        }
    }
}
