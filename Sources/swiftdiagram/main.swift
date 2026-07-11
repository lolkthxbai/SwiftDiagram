import ArgumentParser
import Foundation
import SwiftDiagramCore
import SwiftDiagramRendering

@main
struct SwiftDiagramCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftdiagram",
        abstract: "Parse, validate, and render SwiftDiagram files.",
        subcommands: [RenderCommand.self, ValidateCommand.self, FormatCommand.self]
    )
}

struct RenderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render a SwiftDiagram file as Mermaid or PlantUML."
    )

    @Argument(help: "Path to the .swd input file.")
    var input: String

    @Option(name: .long, help: "Output format: mermaid or plantuml.")
    var format: RenderFormat = .mermaid

    @Option(name: [.short, .long], help: "Write output to this file.")
    var output: String?

    @Option(name: .long, help: "Extension display mode: separate, merged, or hidden.")
    var extensions: ExtensionMode = .merged

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
            format: format.outputFormat,
            options: RenderOptions(extensionDisplayMode: extensions.displayMode)
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

struct FormatCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "format",
        abstract: "Format a SwiftDiagram file canonically."
    )

    @Argument(help: "Path to the .swd input file.")
    var input: String

    @Flag(name: .long, help: "Fail when the file is not canonically formatted.")
    var check = false

    @Flag(name: .long, help: "Rewrite the input file in place.")
    var inPlace = false

    mutating func validate() throws {
        if check && inPlace {
            throw ValidationError("--check and --in-place cannot be used together")
        }
    }

    func run() throws {
        let source = try readSource(at: input)
        let result = SwiftDiagramService().format(source: source, fileName: input)
        writeDiagnostics(DiagnosticFormatter.format(result.diagnostics))
        guard !result.hasErrors else {
            throw ExitCode.failure
        }

        if check {
            if result.changed {
                writeDiagnostics("\(input): file is not canonically formatted\n")
                throw ExitCode.failure
            }
        } else if inPlace {
            do {
                try result.output.write(toFile: input, atomically: true, encoding: .utf8)
            } catch {
                throw ValidationError("unable to write '\(input)': \(error.localizedDescription)")
            }
        } else {
            print(result.output, terminator: "")
        }
    }
}

enum RenderFormat: String, ExpressibleByArgument {
    case mermaid
    case plantuml

    var outputFormat: OutputFormat {
        switch self {
        case .mermaid: .mermaid
        case .plantuml: .plantuml
        }
    }
}

enum ExtensionMode: String, ExpressibleByArgument {
    case separate
    case merged
    case hidden

    var displayMode: ExtensionDisplayMode {
        ExtensionDisplayMode(rawValue: rawValue)!
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
