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
