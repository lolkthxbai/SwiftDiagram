import Foundation
import XCTest
import SwiftDiagramCore
import SwiftDiagramMermaid
import SwiftDiagramModel
import SwiftDiagramParser
import SwiftDiagramPlantUML
import SwiftDiagramRendering

final class PlantUMLTests: XCTestCase {
    func testMembersFixtureProducesBothGoldenFormatsFromOneModel() throws {
        let fixtureDirectory = repositoryRoot
            .appendingPathComponent("Tests/Fixtures/Members", isDirectory: true)
        let source = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("input.swd"),
            encoding: .utf8
        )
        let expectedMermaid = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("expected.mmd"),
            encoding: .utf8
        )
        let expectedPlantUML = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("expected.puml"),
            encoding: .utf8
        )
        let parseResult = SwiftDiagramParser().parse(source: source, fileName: "input.swd")
        let diagram = try XCTUnwrap(parseResult.diagram)
        XCTAssertFalse(parseResult.hasErrors)
        let options = RenderOptions(includePrivateMembers: true)

        XCTAssertEqual(try MermaidRenderer().render(diagram, options: options), expectedMermaid)
        XCTAssertEqual(try PlantUMLRenderer().render(diagram, options: options), expectedPlantUML)
    }

    func testStaticMethodUsesPlantUMLStaticConvention() throws {
        let diagram = Diagram(
            declarations: [
                TypeDeclaration(
                    kind: .struct,
                    name: "Factory",
                    members: [
                        .method(
                            MethodDeclaration(
                                name: "make",
                                returnType: .named("Factory", genericArguments: []),
                                accessLevel: .public,
                                isStatic: true
                            )
                        )
                    ]
                )
            ]
        )

        let output = try PlantUMLRenderer().render(diagram, options: RenderOptions())

        XCTAssertTrue(output.contains("{static} +make() : Factory"))
    }

    func testExtensionDisplayModesDoNotMutateSemanticModel() throws {
        let source = """
        protocol Codable {}
        struct User {}
        extension User: Codable {
            static func make() -> User
        }
        """
        let parseResult = SwiftDiagramParser().parse(source: source, fileName: "Extensions.swd")
        let diagram = try XCTUnwrap(parseResult.diagram)
        let original = diagram
        let renderers: [(RenderOptions) throws -> String] = [
            { try MermaidRenderer().render(diagram, options: $0) },
            { try PlantUMLRenderer().render(diagram, options: $0) }
        ]

        for render in renderers {
            let merged = try render(RenderOptions(extensionDisplayMode: .merged))
            XCTAssertTrue(merged.contains("make()"))
            XCTAssertFalse(merged.contains("extension User"))
            XCTAssertEqual(diagram, original)

            let separate = try render(RenderOptions(extensionDisplayMode: .separate))
            XCTAssertTrue(separate.contains("extension User"))
            XCTAssertTrue(separate.contains("extends"))
            XCTAssertEqual(diagram, original)

            let hidden = try render(RenderOptions(extensionDisplayMode: .hidden))
            XCTAssertFalse(hidden.contains("make()"))
            XCTAssertFalse(hidden.contains("extension User"))
            XCTAssertEqual(diagram, original)
        }
    }

    func testExtensionModesMatchGoldenOutputs() throws {
        let fixtureDirectory = repositoryRoot
            .appendingPathComponent("Tests/Fixtures/Extensions", isDirectory: true)
        let source = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("input.swd"),
            encoding: .utf8
        )
        let parseResult = SwiftDiagramParser().parse(source: source, fileName: "input.swd")
        let diagram = try XCTUnwrap(parseResult.diagram)
        XCTAssertFalse(parseResult.hasErrors)
        let modes: [(name: String, mode: ExtensionDisplayMode)] = [
            ("merged", .merged),
            ("separate", .separate),
            ("hidden", .hidden)
        ]

        for item in modes {
            let expectedMermaid = try String(
                contentsOf: fixtureDirectory.appendingPathComponent("expected.\(item.name).mmd"),
                encoding: .utf8
            )
            let expectedPlantUML = try String(
                contentsOf: fixtureDirectory.appendingPathComponent("expected.\(item.name).puml"),
                encoding: .utf8
            )
            let options = RenderOptions(extensionDisplayMode: item.mode)
            XCTAssertEqual(try MermaidRenderer().render(diagram, options: options), expectedMermaid)
            XCTAssertEqual(try PlantUMLRenderer().render(diagram, options: options), expectedPlantUML)
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
