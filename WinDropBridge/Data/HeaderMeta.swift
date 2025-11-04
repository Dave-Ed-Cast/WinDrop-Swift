//
//  HeaderMeta.swift
//  WinDropBridge
//
//  Created by Davide Castaldi on 03/11/25.
//

import Foundation

public struct HeaderMeta {
    let filename: String
    let size: Int
    let mime: String
    let chunked: Bool

    init(filename: String, size: Int, mime: String, chunked: Bool = false) {
        self.filename = filename
        self.size = size
        self.mime = mime
        self.chunked = chunked
    }

    /// Always uses LF for writing; parser tolerates CRLF.
    func serialize() -> String {
        var lines: [String] = [
            "FILENAME:\(filename)",
            "SIZE:\(size)",
            "MIME:\(mime)"
        ]
        if chunked { lines.append("CHUNKED:YES") }
        lines.append("ENDHEADER")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Tolerant parser: handles CRLF, extra spaces, missing optional fields.
    static func parse(_ text: String) -> HeaderMeta? {
        let trimmed = text.replacingOccurrences(of: "\r", with: "")
        var map: [String: String] = [:]
        for raw in trimmed.split(separator: "\n") {
            guard let idx = raw.firstIndex(of: ":") else { continue }
            let key = raw[..<idx].trimmingCharacters(in: .whitespaces)
            let value = raw[raw.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            map[key.uppercased()] = value
        }

        guard let filename = map["FILENAME"], !filename.isEmpty else { return nil }
        let size = Int(map["SIZE"] ?? "0") ?? 0
        let mime = map["MIME"] ?? "application/octet-stream"
        let chunked = (map["CHUNKED"]?.uppercased() == "YES")

        // If not chunked we require a positive size.
        if !chunked && size <= 0 { return nil }
        return HeaderMeta(filename: filename, size: size, mime: mime, chunked: chunked)
    }
}
