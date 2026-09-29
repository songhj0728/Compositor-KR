// Question 4 of the spike: can Swift call Windows APIs itself, without C/C++ glue? This calls a few of the kinds an
// image editor needs — a window and its message callback, UTF-16 strings, a shell folder that must be freed with
// CoTaskMemFree, the display's DPI — straight from Swift through the WinSDK module, and uses the Core for the data.
import CoreModel

#if os(Windows)
import WinSDK

var document = Document(width: 1920, height: 1080)
_ = try! document.addLayer(named: "배경")
let group = try! document.addGroup(named: "Retouch")
_ = try! document.addLayer(named: "Dodge & Burn", in: group)

func wide(_ text: String) -> [WCHAR] { Array(text.utf16) + [0] }

func string(fromWide pointer: UnsafePointer<WCHAR>) -> String {
    String(decodingCString: pointer, as: UTF16.self)
}

// 1. The Documents folder: a COM-allocated string, freed by us.
var documents: PWSTR?
let folderResult = withUnsafePointer(to: FOLDERID_Documents) { SHGetKnownFolderPath($0, 0, nil, &documents) }
if folderResult == S_OK, let documents {
    print("Documents folder: \(string(fromWide: documents))")
    CoTaskMemFree(documents)
} else {
    print("SHGetKnownFolderPath failed: \(folderResult)")
}

// 2. DPI awareness and the system DPI, as a canvas that draws at native resolution needs.
_ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
print("System DPI: \(GetDpiForSystem())")

// 3. A window with a Swift message callback. It is never shown; one message goes round the loop and ends it.
var receivedTitle = ""
let windowProc: WNDPROC = { window, message, wParam, lParam in
    if message == UINT(WM_USER) {
        var buffer = [WCHAR](repeating: 0, count: 256)
        GetWindowTextW(window, &buffer, Int32(buffer.count))
        receivedTitle = buffer.withUnsafeBufferPointer { string(fromWide: $0.baseAddress!) }
        PostQuitMessage(0)
        return 0
    }
    return DefWindowProcW(window, message, wParam, lParam)
}

let className = wide("CompositorSpikeWindow")
let instance = GetModuleHandleW(nil)
let registered = className.withUnsafeBufferPointer { name -> ATOM in
    var windowClass = WNDCLASSEXW()
    windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
    windowClass.lpfnWndProc = windowProc
    windowClass.hInstance = instance
    windowClass.lpszClassName = name.baseAddress
    return RegisterClassExW(&windowClass)
}
precondition(registered != 0, "RegisterClassExW failed: \(GetLastError())")

let title = "Compositor — \(document.outline.count) layers, top: \(document.outline[0].node.name)"
let window = CreateWindowExW(0, className, wide(title), WS_OVERLAPPEDWINDOW, 0, 0, 640, 480, nil, nil, instance, nil)
precondition(window != nil, "CreateWindowExW failed: \(GetLastError())")
PostMessageW(window, UINT(WM_USER), 0, 0)
var message = MSG()
// BOOL arrives as Bool, so GetMessageW's -1 (error) reads as true; fine here, a real app checks GetLastError.
while GetMessageW(&message, nil, 0, 0) {
    TranslateMessage(&message)
    DispatchMessageW(&message)
}
DestroyWindow(window)
print("Window title read back through the callback: \(receivedTitle)")
precondition(receivedTitle == title, "title did not round-trip")
print("Windows API demo passed")
#else
print("This demo calls Windows APIs; it only does something on Windows.")
#endif
