import DashboardDomain
import Foundation
import Testing
@testable import DashboardAI

@Suite struct JSONCompleterTests {
    let full = #"{"title":"Fix \"login\" crash","description":"Line 1\nLine 2","acceptance_criteria":["No crash","Test added"],"priority":"high","points":13,"nested":{"ok":true,"n":null}}"#

    func object(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    @Test func everyPrefixParsesAndNeverInventsAValue() throws {
        let complete = try #require(object(JSONCompleter.complete(full)))
        for cut in 1 ... full.count {
            let prefix = String(full.prefix(cut))
            guard let partial = JSONCompleter.complete(prefix) else { continue }
            let parsed = try #require(object(partial), "prefix \(cut) must parse")
            for (key, value) in parsed {
                let expected = try #require(complete[key], "prefix \(cut): key \(key) is invented")
                if let s = value as? String, let e = expected as? String {
                    #expect(e.hasPrefix(s), "prefix \(cut): '\(s)' is not a prefix of '\(e)'")
                } else if let list = value as? [String], let e = expected as? [String] {
                    #expect(list.count <= e.count, "prefix \(cut)")
                    for (i, item) in list.enumerated() {
                        #expect(i == list.count - 1 ? e[i].hasPrefix(item) : e[i] == item, "prefix \(cut): \(key)[\(i)]")
                    }
                } else if let dict = value as? [String: Any], let e = expected as? [String: Any] {
                    #expect(Set(dict.keys).isSubset(of: Set(e.keys)))
                } else {
                    #expect("\(value)" == "\(expected)", "prefix \(cut): \(key)")
                }
            }
        }
    }

    @Test func completesTheHalfTypedShapes() {
        let cases: [(String, String)] = [
            (#"{"title":"Fi"#, #"{"title":"Fi"}"#),
            (#"{"title":"Fix","pri"#, #"{"title":"Fix"}"#),
            (#"{"title":"Fix","priority":"#, #"{"title":"Fix"}"#),
            (#"{"title":"Fix","points":1"#, #"{"title":"Fix"}"#),
            (#"{"title":"Fix","points":13,"#, #"{"title":"Fix","points":13}"#),
            (#"{"title":"Fix","done":tr"#, #"{"title":"Fix"}"#),
            (#"{"title":"Fix","done":true,"#, #"{"title":"Fix","done":true}"#),
            (#"{"acceptance_criteria":["a","b"#, #"{"acceptance_criteria":["a","b"]}"#),
            (#"{"acceptance_criteria":["a",""#, #"{"acceptance_criteria":["a",""]}"#),
            (#"{"title":"a \"quoted"#, #"{"title":"a \"quoted"}"#),
            (#"{"title":"back\"#, #"{"title":"back"}"#),
            (#"{"nested":{"x":[1,{"y":"z"#, #"{"nested":{"x":[1,{"y":"z"}]}}"#),
            ("Sure, here is the draft:\n```json\n{\"title\":\"Fix\"", #"{"title":"Fix"}"#),
        ]
        for (input, expected) in cases {
            let got = JSONCompleter.complete(input).flatMap { try? JSONSerialization.jsonObject(with: $0) as? NSDictionary }
            let want = try? JSONSerialization.jsonObject(with: Data(expected.utf8)) as? NSDictionary
            #expect(got == want, "input: \(input)")
        }
        #expect(JSONCompleter.complete("") == nil)
        #expect(JSONCompleter.complete("no json yet") == nil)
        #expect(JSONCompleter.complete("{") != nil)
    }

    @Test func partialDraftParsesLenientlyAndReportsEmptiness() {
        #expect(PartialTicketDraft.parse(Data()).isEmpty)
        let partial = PartialTicketDraft.parse(Data(#"{"title":"T","priority":"bogus","acceptance_criteria":["a",1],"points":"3"}"#.utf8))
        #expect(partial == PartialTicketDraft(title: "T", acceptanceCriteria: ["a"]))
        #expect(!partial.isEmpty)
    }
}
