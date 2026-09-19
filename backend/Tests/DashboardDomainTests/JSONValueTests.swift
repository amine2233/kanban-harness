import Foundation
import Testing
@testable import DashboardDomain

@Suite struct JSONValueTests {
    @Test func roundTripsArbitraryJSONPreservingIntegers() throws {
        let raw = #"{"a":[1,2.5,"s",null,true],"b":{"c":123456789012}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let out = try String(decoding: encoder.encode(value), as: UTF8.self)
        #expect(out == #"{"a":[1,2.5,"s",null,true],"b":{"c":123456789012}}"#)
    }

    @Test func containsStringSearchesNestedLeaves() {
        let value: JSONValue = .object(["edges": .array([.object(["to": .string("abc")])])])
        #expect(value.containsString("abc"))
        #expect(!value.containsString("zzz"))
    }
}
