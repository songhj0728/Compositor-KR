import Foundation

let path = "Compositor/UI/BrushControls.swift"
var lines = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: .newlines)

let target = "                }.pickerStyle(.segmented).labelsHidden().fixedSize()"

if let idx = lines.firstIndex(where: { $0.contains(target) }) {
    let insertStr = """
            if session.blurMode == .liquify {
                Picker("Liquify Mode", selection: $session.liquifyMode) {
                    ForEach(LiquifyMode.allCases, id: \\.self) { Text(LocalizedStringKey($0.displayName)).tag($0) }
                }.labelsHidden().fixedSize()
            }
"""
    lines.insert(insertStr, at: idx + 1)
}

try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
