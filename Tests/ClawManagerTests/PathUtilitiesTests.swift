import Testing
@testable import ClawManager

@Suite("PathUtilities")
struct PathUtilitiesTests {
    @Test("Demangle workspace paths")
    func demanglePaths() {
        #expect(
            PathUtilities.demangleWorkspacePath("-Users-michael-Documents-GitHub-Foo")
            == "/Users/michael/Documents/GitHub/Foo"
        )
    }

    @Test("Demangle path with trailing hyphen")
    func demangleTrailingHyphen() {
        #expect(
            PathUtilities.demangleWorkspacePath("-Users-michael-Documents-GitHub-Foo-")
            == "/Users/michael/Documents/GitHub/Foo"
        )
    }

    @Test("UUID validation — valid")
    func validUUID() {
        #expect(PathUtilities.isUUID("a4980909-1c26-4009-bcad-b28ac820810b"))
        #expect(PathUtilities.isUUID("bc888ff3-9624-41f0-8f91-fc0c96b3e90c"))
    }

    @Test("UUID validation — invalid")
    func invalidUUID() {
        #expect(!PathUtilities.isUUID("not-a-uuid"))
        #expect(!PathUtilities.isUUID("sessions-index.json"))
        #expect(!PathUtilities.isUUID("memory"))
    }

    @Test("Project name extraction")
    func projectName() {
        #expect(PathUtilities.projectName(from: "/Users/michael/Documents/GitHub/Foo") == "Foo")
        #expect(PathUtilities.projectName(from: "/Users/michael/ClawManager") == "ClawManager")
    }
}
