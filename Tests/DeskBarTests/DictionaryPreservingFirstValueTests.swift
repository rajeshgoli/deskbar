import Testing
@testable import DeskBar

@Test
func dictionaryPreservingFirstValueIgnoresDuplicateKeys() {
    let dictionary = Dictionary(preservingFirstValues: [
        ("pid-1", "Finder"),
        ("pid-2", "Terminal"),
        ("pid-1", "Duplicate Finder")
    ])

    #expect(dictionary["pid-1"] == "Finder")
    #expect(dictionary["pid-2"] == "Terminal")
}
