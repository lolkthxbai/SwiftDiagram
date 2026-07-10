import ArgumentParser
import Foundation
import SwiftDiagramCore

@main
struct SwiftDiagramCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftdiagram",
        abstract: "Parse, validate, and render SwiftDiagram files.",
        subcommands: [RenderCommand.self, ValidateCommand.self]
    )
}

struct RenderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render a SwiftDiagram file as Mermaid."
    )

    @Argument(help: "Path to the .swd input file.")
    var input: String

    @Option(name: .long, help: "Output format. Milestone 1 supports mermaid.")
    var format: RenderFormat = .mermaid

    @Option(name: [.short, .long], help: "Write output to this file.")
    var output: String?

    @Flag(name: .long, help: "Write rendered output to standard output.")
    var stdout = false

    mutating func validate() throws {
        if stdout && output != nil {
            throw ValidationError("--stdout and --output cannot be used together")
        }
    }

    func run() throws {
        let source = try readSource(at: input)
        let result = SwiftDiagramService().render(
            source: source,
            fileName: input,
            format: format.outputFormat
        )
        writeDiagnostics(DiagnosticFormatter.format(result.diagnostics))
        guard !result.hasErrors, let rendered = result.output else {
            throw ExitCode.failure
        }

        if let output {
            do {
                try rendered.write(toFile: output, atomically: true, encoding: .utf8)
            } catch {
                throw ValidationError("unable to write '\(output)': \(error.localizedDescription)")
            }
        } else {
            print(rendered, terminator: "")
        }
    }
}

struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a SwiftDiagram file."
    )

    @Argument(help: "Path to the .swd input file.")
    var input: String

    func run() throws {
        let source = try readSource(at: input)
        let result = SwiftDiagramService().parseAndValidate(source: source, fileName: input)
        writeDiagnostics(DiagnosticFormatter.format(result.diagnostics))
        if result.hasErrors {
            throw ExitCode.failure
        }
    }
}

enum RenderFormat: String, ExpressibleByArgument {
    case mermaid

    var outputFormat: OutputFormat {
        .mermaid
    }
}

private func readSource(at path: String) throws -> String {
    do {
        return try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        throw ValidationError("unable to read '\(path)': \(error.localizedDescription)")
    }
}

private func writeDiagnostics(_ text: String) {
    guard !text.isEmpty else { return }
    FileHandle.standardError.write(Data(text.utf8))
}
