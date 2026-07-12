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

    func testFilteringDoesNotMutateSemanticModel() throws {
        let source = """
        public struct User {
            public let id: UUID
            private var token: String
        }
        internal struct Session {}
        User references Session
        """
        let parseResult = SwiftDiagramParser().parse(source: source, fileName: "Filters.swd")
        let diagram = try XCTUnwrap(parseResult.diagram)
        let original = diagram
        let options = RenderOptions(
            declarationAccessLevels: [.public],
            memberAccessLevels: [.private],
            excludedElements: ["*Preview"],
            excludedRelationshipTargets: ["Session"]
        )

        _ = try MermaidRenderer().render(diagram, options: options)
        _ = try PlantUMLRenderer().render(diagram, options: options)

        XCTAssertEqual(diagram, original)
    }

    func testGlobMatcherSupportsSegmentAndRecursiveWildcards() {
        XCTAssertTrue(GlobPatternMatcher.matches("Domain/Models.swd", pattern: "**/*.swd"))
        XCTAssertTrue(GlobPatternMatcher.matches("Domain/Models.swd", pattern: "Domain/Model?.swd"))
        XCTAssertTrue(GlobPatternMatcher.matches("UserPreview", pattern: "*Preview"))
        XCTAssertFalse(GlobPatternMatcher.matches("Domain/Nested/Models.swd", pattern: "Domain/*.swd"))
    }

    func testInferredRelationshipFilterOmitsOnlyInferredEdges() throws {
        let diagram = Diagram(
            declarations: [
                TypeDeclaration(kind: .struct, name: "Source"),
                TypeDeclaration(kind: .struct, name: "ExplicitTarget"),
                TypeDeclaration(kind: .struct, name: "InferredTarget")
            ],
            relationships: [
                Relationship(
                    source: "Source",
                    target: "ExplicitTarget",
                    kind: .references,
                    origin: .explicit
                ),
                Relationship(
                    source: "Source",
                    target: "InferredTarget",
                    kind: .references,
                    origin: .inferred
                )
            ]
        )
        let options = RenderOptions(includeInferredRelationships: false)

        let mermaid = try MermaidRenderer().render(diagram, options: options)
        let plantUML = try PlantUMLRenderer().render(diagram, options: options)

        XCTAssertTrue(mermaid.contains("Source --> ExplicitTarget"))
        XCTAssertFalse(mermaid.contains("Source --> InferredTarget"))
        XCTAssertTrue(plantUML.contains("Source --> ExplicitTarget"))
        XCTAssertFalse(plantUML.contains("Source --> InferredTarget"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
