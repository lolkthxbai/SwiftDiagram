import Foundation
import XCTest

final class CLITests: XCTestCase {
    func testRenderAndValidateCommands() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let validInput = temporaryDirectory.appendingPathComponent("Valid.swd")
        try "struct User { let id: UUID }".write(to: validInput, atomically: true, encoding: .utf8)

        let validation = try runCLI(["validate", validInput.path])
        XCTAssertEqual(validation.status, 0, validation.stderr)

        let rendering = try runCLI(["render", validInput.path])
        XCTAssertEqual(rendering.status, 0, rendering.stderr)
        XCTAssertTrue(rendering.stdout.hasPrefix("classDiagram\n"))
        XCTAssertTrue(rendering.stderr.isEmpty)

        let output = temporaryDirectory.appendingPathComponent("Valid.mmd")
        let fileRendering = try runCLI([
            "render", validInput.path, "--format", "mermaid", "--output", output.path
        ])
        XCTAssertEqual(fileRendering.status, 0, fileRendering.stderr)
        XCTAssertTrue(fileRendering.stdout.isEmpty)
        XCTAssertTrue(try String(contentsOf: output, encoding: .utf8).hasPrefix("classDiagram\n"))

        let plantOutput = temporaryDirectory.appendingPathComponent("Valid.puml")
        let plantRendering = try runCLI([
            "render", validInput.path, "--format", "plantuml", "--output", plantOutput.path
        ])
        XCTAssertEqual(plantRendering.status, 0, plantRendering.stderr)
        XCTAssertTrue(plantRendering.stdout.isEmpty)
        let plantText = try String(contentsOf: plantOutput, encoding: .utf8)
        XCTAssertTrue(plantText.hasPrefix("@startuml\n"))
        XCTAssertTrue(plantText.hasSuffix("@enduml\n"))
    }

    func testInvalidInputReturnsFailureAndLocatedDiagnostic() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let invalidInput = temporaryDirectory.appendingPathComponent("Invalid.swd")
        try "struct User { let id UUID }".write(to: invalidInput, atomically: true, encoding: .utf8)

        let result = try runCLI(["validate", invalidInput.path])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("Invalid.swd:1:22: error SWD1018"), result.stderr)
    }

    func testFormatCheckAndInPlaceWorkflow() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let input = temporaryDirectory.appendingPathComponent("Format.swd")
        try "struct User{let id:UUID}".write(to: input, atomically: true, encoding: .utf8)

        let initialCheck = try runCLI(["format", input.path, "--check"])
        XCTAssertNotEqual(initialCheck.status, 0)
        XCTAssertTrue(initialCheck.stderr.contains("not canonically formatted"))

        let rewrite = try runCLI(["format", input.path, "--in-place"])
        XCTAssertEqual(rewrite.status, 0, rewrite.stderr)
        XCTAssertEqual(try String(contentsOf: input, encoding: .utf8), "struct User {\n    let id: UUID\n}\n")

        let finalCheck = try runCLI(["format", input.path, "--check"])
        XCTAssertEqual(finalCheck.status, 0, finalCheck.stderr)
        XCTAssertTrue(finalCheck.stdout.isEmpty)
        XCTAssertTrue(finalCheck.stderr.isEmpty)
    }

    func testMultiDirectoryFilteringMatchesGoldenOutputsAndIsDeterministic() throws {
        let fixture = repositoryRoot.appendingPathComponent("Tests/Fixtures/Filtering", isDirectory: true)
        let filters = [
            "--include-file", "Domain/**",
            "--include-file", "Services/**",
            "--include-file", "Support/**",
            "--exclude-file", "**/Preview.swd",
            "--declaration-access", "public,open",
            "--member-access", "public",
            "--exclude-element", "Temp*",
            "--exclude-relationship-target", "Audit*"
        ]

        let mermaid = try runCLI(["render", fixture.path, "--format", "mermaid"] + filters)
        let repeated = try runCLI(["render", fixture.path, "--format", "mermaid"] + filters)
        let expectedMermaid = try String(
            contentsOf: fixture.appendingPathComponent("expected.mmd"),
            encoding: .utf8
        )
        XCTAssertEqual(mermaid.status, 0, mermaid.stderr)
        XCTAssertEqual(mermaid.stdout, expectedMermaid)
        XCTAssertEqual(repeated.stdout, mermaid.stdout)

        let withoutMethods = try runCLI(
            ["render", fixture.path, "--format", "mermaid", "--exclude-methods"] + filters
        )
        XCTAssertEqual(withoutMethods.status, 0, withoutMethods.stderr)
        XCTAssertFalse(withoutMethods.stdout.contains("refresh()"))
        XCTAssertFalse(withoutMethods.stdout.contains("display()"))

        let plantUML = try runCLI(["render", fixture.path, "--format", "plantuml"] + filters)
        let expectedPlantUML = try String(
            contentsOf: fixture.appendingPathComponent("expected.puml"),
            encoding: .utf8
        )
        XCTAssertEqual(plantUML.status, 0, plantUML.stderr)
        XCTAssertEqual(plantUML.stdout, expectedPlantUML)

        let shuffledInputs = [
            fixture.appendingPathComponent("Services/Team.swd").path,
            fixture.appendingPathComponent("Support/Audit.swd").path,
            fixture.appendingPathComponent("Domain/Models.swd").path
        ]
        let shuffled = try runCLI(
            ["render"] + shuffledInputs + [
                "--declaration-access", "public,open",
                "--member-access", "public",
                "--exclude-element", "Temp*",
                "--exclude-relationship-target", "Audit*"
            ]
        )
        XCTAssertEqual(shuffled.status, 0, shuffled.stderr)
        XCTAssertEqual(shuffled.stdout, expectedMermaid)
    }

    func testDeclarationAndMemberAccessFiltersAreIndependent() throws {
        let fixture = repositoryRoot.appendingPathComponent("Tests/Fixtures/Filtering", isDirectory: true)

        let internalDeclarations = try runCLI([
            "render", fixture.path,
            "--include-file", "Domain/**",
            "--declaration-access", "internal",
            "--member-access", "public"
        ])
        XCTAssertEqual(internalDeclarations.status, 0, internalDeclarations.stderr)
        XCTAssertTrue(internalDeclarations.stdout.contains("class Session"))
        XCTAssertTrue(internalDeclarations.stdout.contains("+UUID id"))
        XCTAssertFalse(internalDeclarations.stdout.contains("class User"))
        XCTAssertFalse(internalDeclarations.stdout.contains("Team"))

        let privateMembers = try runCLI([
            "render", fixture.path,
            "--include-file", "Domain/**",
            "--include-file", "Services/**",
            "--include-file", "Support/**",
            "--exclude-file", "**/Preview.swd",
            "--declaration-access", "public,open",
            "--member-access", "private"
        ])
        XCTAssertEqual(privateMembers.status, 0, privateMembers.stderr)
        XCTAssertTrue(privateMembers.stdout.contains("-String token"))
        XCTAssertTrue(privateMembers.stdout.contains("-String secret"))
        XCTAssertFalse(privateMembers.stdout.contains("+UUID id"))
    }

    private func runCLI(_ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = repositoryRoot.appendingPathComponent(".build/debug/swiftdiagram")
        process.arguments = arguments
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: standardError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
