// The C++ host's checks (hosts/cpp/host.cpp), from C#, through CompositorCore.cs — against either Core's DLL.
using System;
using System.Text;
using Compositor.Core;

internal static class HostTests
{
    private static int failures;

    private static void Check(bool condition, string what)
    {
        if (condition) return;
        ++failures;
        Console.Error.WriteLine("FAIL: " + what);
    }

    private static int Main()
    {
        // Setting it fails without a console (as on CI runners); the text is still UTF-8 through the pipe then.
        try { Console.OutputEncoding = Encoding.UTF8; } catch (System.IO.IOException) { }
        using (var document = new LayerDocument(1920, 1080))
        {
            ulong background = document.AddLayer("배경");
            ulong sky = document.AddLayer("하늘");
            ulong people = document.AddLayer("People");
            Check(document.UndoName == "Add Layer", "undo name after adding");

            ulong group = document.Group(new[] { sky, people }, "보정 그룹");
            Check(document.SetVisible(sky, false), "hide");
            Check(document.Rename(people, "인물 레이어"), "rename");
            Check(!document.Rename(12345, "nothing"), "renaming a missing layer fails");
            Check(document.UndoName == "Rename Layer", "undo name after rename");

            var rows = document.Outline();
            Console.WriteLine("Outline:");
            foreach (var row in rows)
                Console.WriteLine("  " + new string(' ', row.Depth * 2) + (row.IsGroup ? "[G] " : "[L] ") + row.Name +
                                  (row.IsVisible ? "" : " (hidden)") + " (#" + row.Id + ")");
            Check(rows.Count == 4, "four rows");
            Check(rows[0].Id == group && rows[0].IsGroup && rows[0].Name == "보정 그룹", "group on top");
            Check(rows[3].Id == background && rows[3].Name == "배경", "background at the bottom");
            Check(document.OutlineName(0, 7) == "보정", "cut between characters");
            Check(document.OutlineName(0, 5) == "보", "cut backs off a split character");

            try
            {
                document.Group(new ulong[] { background, 999 }, "x");
                Check(false, "grouping a missing layer throws");
            }
            catch (InvalidOperationException) { }

            Check(document.Undo() && document.Undo() && document.Undo(), "three undos");
            Check(document.Outline().Count == 3, "three rows after undo");
            Check(document.Redo(), "redo");
            Check(document.Outline().Count == 4, "four rows after redo");
        }
        if (failures > 0)
        {
            Console.Error.WriteLine(failures + " check(s) failed");
            return 1;
        }
        Console.WriteLine("C# host checks passed");
        return 0;
    }
}
