import Foundation

let path = "Compositor/Document/EditorSession.swift"
var lines = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: .newlines)

if let idx = lines.firstIndex(where: { $0.contains("var blurMode:") }) {
    lines.insert("    var liquifyMode: LiquifyMode = .forwardWarp", at: idx + 1)
}

try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
