import ArgumentParser

@main
struct SwiftDiagramCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftdiagram",
        abstract: "SwiftDiagram command line interface."
    )

    func run() throws {}
}
