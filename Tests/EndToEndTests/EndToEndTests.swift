import XCTest
import SwiftDiagramCore

final class EndToEndTests: XCTestCase {
    func testSourceToValidatedMermaidPipeline() {
        let source = """
        protocol Identifiable {
            var id: UUID { get }
        }
        struct User: Identifiable {
            let id: UUID
        }
        """

        let result = SwiftDiagramService().render(source: source, fileName: "User.swd")

        XCTAssertFalse(result.hasErrors)
        XCTAssertEqual(
            result.output,
            """
            classDiagram
                class Identifiable {
                    <<protocol>>
                    UUID id
                }
                class User {
                    <<struct>>
                    UUID id
                }
                User ..|> Identifiable

            """
        )
    }

    func testInvalidSourceStopsRenderingWithLocatedDiagnostics() {
        let source = """
        struct User {
            let role Role
        }
        User references Missing
        """

        let result = SwiftDiagramService().render(source: source, fileName: "Invalid.swd")

        XCTAssertTrue(result.hasErrors)
        XCTAssertNil(result.output)
        XCTAssertTrue(result.diagnostics.count >= 2)
        XCTAssertTrue(result.diagnostics.allSatisfy { $0.range != nil })
        XCTAssertTrue(
            result.diagnostics.map(DiagnosticFormatter.format).contains {
                $0.hasPrefix("Invalid.swd:2:")
            }
        )
    }

    func testMultiSourceInputOrderDoesNotChangeModelOrOutput() {
        let models = DiagramSource(
            path: "Domain/Models.swd",
            contents: "public struct User { public let id: UUID }"
        )
        let services = DiagramSource(
            path: "Services/Team.swd",
            contents: """
            public struct Team { public var members: [User] }
            Team contains User through members
            """
        )
        let service = SwiftDiagramService()

        let forwardCompilation = service.parseAndValidate(sources: [models, services])
        let reverseCompilation = service.parseAndValidate(sources: [services, models])
        let forwardOutput = service.render(sources: [models, services]).output
        let reverseOutput = service.render(sources: [services, models]).output

        XCTAssertFalse(forwardCompilation.hasErrors)
        XCTAssertEqual(forwardCompilation.diagram, reverseCompilation.diagram)
        XCTAssertEqual(forwardOutput, reverseOutput)
    }
}
