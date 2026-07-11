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

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
