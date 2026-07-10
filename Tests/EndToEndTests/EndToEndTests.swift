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
}
