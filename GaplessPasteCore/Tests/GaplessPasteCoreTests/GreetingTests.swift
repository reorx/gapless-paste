import Testing
@testable import GaplessPasteCore

@Test func greetingMessage() {
    #expect(Greeting().message(for: "World") == "Hello, World!")
}
