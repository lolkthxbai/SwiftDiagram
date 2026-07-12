import ArgumentParser
import Foundation
import SwiftDiagramCore
import SwiftDiagramModel
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
        abstract: "Render SwiftDiagram files as Mermaid or PlantUML."
    )

    @Argument(help: "One or more .swd files or directories.")
    var inputs: [String]

    @Option(name: .long, help: "Output format: mermaid or plantuml.")
    var format: RenderFormat = .mermaid

    @Option(name: [.short, .long], help: "Write output to this file.")
    var output: String?

    @Option(name: .long, help: "Extension display mode: separate, merged, or hidden.")
    var extensions: ExtensionMode = .merged

    @Option(name: .long, help: "Include files matching this root-relative glob. Repeatable.")
    var includeFile: [String] = []

    @Option(name: .long, help: "Exclude files matching this root-relative glob. Repeatable.")
    var excludeFile: [String] = []

    @Option(name: .long, help: "Declaration access levels as a comma-separated list.")
    var declarationAccess: String?

    @Option(name: .long, help: "Member access levels as a comma-separated list.")
    var memberAccess: String?

    @Option(name: .long, help: "Exclude elements matching this glob. Repeatable.")
    var excludeElement: [String] = []

    @Option(name: .long, help: "Exclude relationships whose target matches this glob. Repeatable.")
    var excludeRelationshipTarget: [String] = []

    @Flag(name: .long, help: "Exclude method and initializer signatures.")
    var excludeMethods = false

    @Flag(name: .long, help: "Exclude inferred relationships.")
    var excludeInferredRelationships = false

    @Flag(name: .long, help: "Write rendered output to standard output.")
    var stdout = false

    mutating func validate() throws {
        if stdout && output != nil {
            throw ValidationError("--stdout and --output cannot be used together")
        }
    }

    func run() throws {
        let sources: [DiagramSource]
        do {
            sources = try loadDiagramSources(
                inputs: inputs,
                includePatterns: includeFile,
                excludePatterns: excludeFile
            )
        } catch {
            throw ValidationError(error.localizedDescription)
        }
        let result = SwiftDiagramService().render(
            sources: sources,
            format: format.outputFormat,
            options: try renderOptions()
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

    private func renderOptions() throws -> RenderOptions {
        RenderOptions(
            declarationAccessLevels: try parseAccessLevels(
                declarationAccess,
                option: "--declaration-access"
            ),
            memberAccessLevels: try parseAccessLevels(memberAccess, option: "--member-access"),
            includeMethods: !excludeMethods,
            includeInferredRelationships: !excludeInferredRelationships,
            extensionDisplayMode: extensions.displayMode,
            excludedElements: excludeElement,
            excludedRelationshipTargets: excludeRelationshipTarget
        )
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

private func parseAccessLevels(_ value: String?, option: String) throws -> [AccessLevel]? {
    guard let value else { return nil }
    let components = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty }) else {
        throw ValidationError("\(option) requires a comma-separated access-level list")
    }

    var result: [AccessLevel] = []
    for component in components {
        guard let accessLevel = AccessLevel(rawValue: component) else {
            throw ValidationError("invalid access level '\(component)' for \(option)")
        }
        if !result.contains(accessLevel) {
            result.append(accessLevel)
        }
    }
    return result
}

private func writeDiagnostics(_ text: String) {
    guard !text.isEmpty else { return }
    FileHandle.standardError.write(Data(text.utf8))
}
