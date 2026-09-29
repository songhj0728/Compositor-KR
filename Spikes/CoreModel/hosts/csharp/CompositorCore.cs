// The C# side of include/compositor_core.h: what a C# WinUI 3 app would use to reach either Core. Written in C# 5
// so the compiler that ships with Windows (.NET Framework's csc.exe) builds it; it compiles unchanged on .NET 8.
// Build with /define:CPP_CORE to bind the C++ Core's DLL instead of the Swift one.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Compositor.Core
{
    internal static class NativeMethods
    {
#if CPP_CORE
        public const string Library = "CompositorCoreCpp";
#else
        public const string Library = "CompositorCore";
#endif

        // Strings cross as NUL-terminated UTF-8 bytes; .NET Framework has no UTF-8 string marshaling of its own.
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern HistoryHandle cc_history_create(int width, int height);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern void cc_history_destroy(IntPtr history);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern ulong cc_add_layer(HistoryHandle history, byte[] name, ulong parent);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern ulong cc_add_group(HistoryHandle history, byte[] name, ulong parent);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern ulong cc_group(HistoryHandle history, ulong[] ids, UIntPtr count, byte[] name);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern int cc_set_visible(HistoryHandle history, ulong id, int visible);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern int cc_rename(HistoryHandle history, ulong id, byte[] name);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern int cc_undo(HistoryHandle history);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern int cc_redo(HistoryHandle history);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern UIntPtr cc_undo_name(HistoryHandle history, byte[] buffer, UIntPtr capacity);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern UIntPtr cc_outline_count(HistoryHandle history);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        public static extern int cc_outline_row(HistoryHandle history, UIntPtr index, out ulong id, out int depth,
                                                out int isGroup, out int isVisible, byte[] name, UIntPtr nameCapacity);
    }

    // Frees the Core's history when the garbage collector (or Dispose) lets go of it.
    internal sealed class HistoryHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        private HistoryHandle() : base(true) { }

        protected override bool ReleaseHandle()
        {
            NativeMethods.cc_history_destroy(handle);
            return true;
        }
    }

    public struct OutlineRow
    {
        public ulong Id;
        public int Depth;
        public bool IsGroup;
        public bool IsVisible;
        public string Name;
    }

    // The Core as a C# class: what a WinUI view model would hold. Failures the Core reports become exceptions here,
    // on the C# side, where they're safe.
    public sealed class LayerDocument : IDisposable
    {
        private readonly HistoryHandle history;

        public LayerDocument(int width, int height)
        {
            history = NativeMethods.cc_history_create(width, height);
            if (history.IsInvalid) throw new OutOfMemoryException("The Core could not make a document.");
        }

        public ulong AddLayer(string name, ulong parent = 0) { return Made(NativeMethods.cc_add_layer(history, Utf8(name), parent)); }
        public ulong AddGroup(string name, ulong parent = 0) { return Made(NativeMethods.cc_add_group(history, Utf8(name), parent)); }

        public ulong Group(IList<ulong> ids, string name)
        {
            var array = new ulong[ids.Count];
            ids.CopyTo(array, 0);
            return Made(NativeMethods.cc_group(history, array, (UIntPtr)array.Length, Utf8(name)));
        }

        public bool SetVisible(ulong id, bool visible) { return NativeMethods.cc_set_visible(history, id, visible ? 1 : 0) != 0; }
        public bool Rename(ulong id, string name) { return NativeMethods.cc_rename(history, id, Utf8(name)) != 0; }
        public bool Undo() { return NativeMethods.cc_undo(history) != 0; }
        public bool Redo() { return NativeMethods.cc_redo(history) != 0; }

        public string UndoName
        {
            get
            {
                var buffer = new byte[256];
                ulong length = (ulong)NativeMethods.cc_undo_name(history, buffer, (UIntPtr)buffer.Length);
                if (length == 0) return null;
                if (length >= (ulong)buffer.Length)
                {
                    buffer = new byte[length + 1];
                    NativeMethods.cc_undo_name(history, buffer, (UIntPtr)buffer.Length);
                }
                return FromUtf8(buffer);
            }
        }

        // The layers panel's rows, top first.
        public List<OutlineRow> Outline()
        {
            int count = (int)(ulong)NativeMethods.cc_outline_count(history);
            var rows = new List<OutlineRow>(count);
            var name = new byte[1024];
            for (int i = 0; i < count; ++i)
            {
                ulong id; int depth, isGroup, isVisible;
                if (NativeMethods.cc_outline_row(history, (UIntPtr)i, out id, out depth, out isGroup, out isVisible,
                                                 name, (UIntPtr)name.Length) == 0) break;
                rows.Add(new OutlineRow { Id = id, Depth = depth, IsGroup = isGroup != 0, IsVisible = isVisible != 0,
                                          Name = FromUtf8(name) });
            }
            return rows;
        }

        // Raw access for tests of the boundary itself.
        internal string OutlineName(int index, int capacity)
        {
            var name = new byte[capacity];
            ulong id; int depth, isGroup, isVisible;
            NativeMethods.cc_outline_row(history, (UIntPtr)index, out id, out depth, out isGroup, out isVisible, name,
                                         (UIntPtr)name.Length);
            return FromUtf8(name);
        }

        public void Dispose() { history.Dispose(); }

        private static ulong Made(ulong id)
        {
            if (id == 0) throw new InvalidOperationException("The Core refused the change.");
            return id;
        }

        private static byte[] Utf8(string text)
        {
            var bytes = Encoding.UTF8.GetBytes(text ?? "");
            var terminated = new byte[bytes.Length + 1];
            Buffer.BlockCopy(bytes, 0, terminated, 0, bytes.Length);
            return terminated;
        }

        private static string FromUtf8(byte[] buffer)
        {
            int length = Array.IndexOf(buffer, (byte)0);
            return Encoding.UTF8.GetString(buffer, 0, length < 0 ? buffer.Length : length);
        }
    }
}
