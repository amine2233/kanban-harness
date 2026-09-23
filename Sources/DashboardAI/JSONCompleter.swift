import Foundation

/// Turns the JSON a model has produced *so far* into a parseable object by
/// closing whatever is open (strings, arrays, objects) and dropping a trailing
/// token that cannot be finished (a bare key, a half number, a stray comma).
/// Used to render partial drafts while streaming; never used for the final result.
public enum JSONCompleter {
    public static func complete(_ text: String) -> Data? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var body = String(text[start...])
        var stack: [Character] = []
        var inString = false
        var escaped = false
        var lastSignificant: Character = "{"
        var lastKeyStart: String.Index?
        var stringStart: String.Index?
        var index = body.startIndex
        while index < body.endIndex {
            let char = body[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                    lastSignificant = char
                }
            } else {
                switch char {
                case "\"":
                    inString = true
                    stringStart = index
                case "{", "[":
                    stack.append(char)
                    lastSignificant = char
                case "}", "]":
                    _ = stack.popLast()
                    lastSignificant = char
                case ":":
                    lastKeyStart = stringStart
                    lastSignificant = char
                case ",":
                    lastSignificant = char
                case " ", "\n", "\r", "\t":
                    break
                default:
                    lastSignificant = char
                }
            }
            index = body.index(after: index)
        }

        if inString {
            // An unterminated string: keep it (a partial value is useful) unless it is a
            // key or a half escape, in which case cut back to before it.
            if escaped { body.removeLast() }
            let isKey = stack.last == "{" && Self.expectsKey(body, stringStart: stringStart)
            if isKey, let stringStart { body = String(body[..<stringStart]) } else { body += "\"" }
            inString = false
        }
        body = Self.trimDanglingTail(body, stack: &stack, lastKeyStart: lastKeyStart)
        while let open = stack.popLast() {
            body += open == "{" ? "}" : "]"
        }
        _ = lastSignificant
        let data = Data(body.utf8)
        return (try? JSONSerialization.jsonObject(with: data)) != nil ? data : nil
    }

    /// Inside an object, a string that follows `{` or `,` is a key.
    private static func expectsKey(_ body: String, stringStart: String.Index?) -> Bool {
        guard let stringStart else { return false }

        let before = body[..<stringStart].reversed().first { !$0.isWhitespace }
        return before == "{" || before == ","
    }

    /// Removes a trailing comma, a `"key":` without value, or a half-written bare token.
    private static func trimDanglingTail(
        _ body: String,
        stack: inout [Character],
        lastKeyStart: String.Index?
    ) -> String {
        var body = body
        while let last = body.last, last.isWhitespace {
            body.removeLast()
        }
        if body.last == "," {
            body.removeLast()
            return body
        }
        if body.last == ":", let lastKeyStart {
            body = String(body[..<lastKeyStart])
            while let last = body.last, last.isWhitespace {
                body.removeLast()
            }
            if body.last == "," { body.removeLast() }
        } else if let last = body.last, !["\"", "}", "]", "{", "["].contains(last) {
            // a trailing bare token: true/false/null cannot grow, a number still can, so it is dropped
            var token = ""
            var cut = body.endIndex
            var index = body.endIndex
            while index > body.startIndex {
                index = body.index(before: index)
                let character = body[index]
                if ["\"", "}", "]", "{", "[", ",", ":"].contains(character) || character
                    .isWhitespace { break }
                token.insert(character, at: token.startIndex)
                cut = index
            }
            let complete = ["true", "false", "null"].contains(token)
            if !complete {
                body = String(body[..<cut])
                while let last = body.last, last.isWhitespace {
                    body.removeLast()
                }
                if body.last == ":", let lastKeyStart {
                    body = String(body[..<lastKeyStart])
                    while let last = body.last, last.isWhitespace {
                        body.removeLast()
                    }
                }
                if body.last == "," { body.removeLast() }
            }
        }
        return body
    }
}
