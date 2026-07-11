import SwiftDiagramFormatter
import SwiftDiagramMermaid
import SwiftDiagramModel
import SwiftDiagramParser
import SwiftDiagramPlantUML
import SwiftDiagramRendering
import SwiftDiagramSyntax
import SwiftDiagramValidation

public enum OutputFormat: String, Equatable, Sendable, Codable {
    case mermaid
    case plantuml
}

public struct CompilationResult: Equatable, Sendable {
    public var diagram: Diagram?
    public var diagnostics: [Diagnostic]

    public init(diagram: Diagram?, diagnostics: [Diagnostic]) {
        self.diagram = diagram
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }
}

public struct RenderingResult: Equatable, Sendable {
    public var output: String?
    public var diagnostics: [Diagnostic]

    public init(output: String?, diagnostics: [Diagnostic]) {
        self.output = output
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }
}

public struct SourceFormattingResult: Equatable, Sendable {
    public var output: String
    public var changed: Bool
    public var diagnostics: [Diagnostic]

    public init(output: String, changed: Bool, diagnostics: [Diagnostic]) {
        self.output = output
        self.changed = changed
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }
}

public struct SwiftDiagramService: Sendable {
    private let parser: SwiftDiagramParser
    private let validator: SwiftDiagramValidator
    private let mermaidRenderer: MermaidRenderer
    private let plantUMLRenderer: PlantUMLRenderer
    private let formatter: SwiftDiagramFormatter

    public init() {
        parser = SwiftDiagramParser()
        validator = SwiftDiagramValidator()
        mermaidRenderer = MermaidRenderer()
        plantUMLRenderer = PlantUMLRenderer()
        formatter = SwiftDiagramFormatter()
    }

    public func parseAndValidate(
        source: String,
        fileName: String? = nil
    ) -> CompilationResult {
        let parseResult = parser.parse(source: source, fileName: fileName)
        guard let diagram = parseResult.diagram else {
            return CompilationResult(diagram: nil, diagnostics: parseResult.diagnostics)
        }
        let validationDiagnostics = validator.validate(diagram, fileName: fileName)
        return CompilationResult(
            diagram: diagram,
            diagnostics: sortedDiagnostics(parseResult.diagnostics + validationDiagnostics)
        )
    }

    public func render(
        source: String,
        fileName: String? = nil,
        format: OutputFormat = .mermaid,
        options: RenderOptions = RenderOptions()
    ) -> RenderingResult {
        let compilation = parseAndValidate(source: source, fileName: fileName)
        guard !compilation.hasErrors, let diagram = compilation.diagram else {
            return RenderingResult(output: nil, diagnostics: compilation.diagnostics)
        }

        do {
            let output: String
            switch format {
            case .mermaid:
                output = try mermaidRenderer.render(diagram, options: options)
            case .plantuml:
                output = try plantUMLRenderer.render(diagram, options: options)
            }
            return RenderingResult(output: output, diagnostics: compilation.diagnostics)
        } catch {
            var diagnostics = compilation.diagnostics
            diagnostics.append(
                Diagnostic(
                    severity: .error,
                    code: "SWD3001",
                    message: "rendering failed: \(error)"
                )
            )
            return RenderingResult(output: nil, diagnostics: diagnostics)
        }
    }

    public func format(source: String, fileName: String? = nil) -> SourceFormattingResult {
        let result = formatter.format(source: source, fileName: fileName)
        return SourceFormattingResult(
            output: result.text,
            changed: result.changed,
            diagnostics: result.diagnostics.map(Diagnostic.init)
        )
    }
}

public enum DiagnosticFormatter {
    public static func format(_ diagnostic: Diagnostic) -> String {
        let location: String
        if let range = diagnostic.range {
            location = "\(diagnostic.fileName ?? "<input>"):\(range.start.line):\(range.start.column)"
        } else {
            location = diagnostic.fileName ?? "<input>"
        }
        return "\(location): \(diagnostic.severity.rawValue) \(diagnostic.code.rawValue): \(diagnostic.message)"
    }

    public static func format(_ diagnostics: [Diagnostic]) -> String {
        guard !diagnostics.isEmpty else { return "" }
        return diagnostics.map(format).joined(separator: "\n") + "\n"
    }
}

private func sortedDiagnostics(_ diagnostics: [Diagnostic]) -> [Diagnostic] {
    diagnostics.sorted {
        let lhsOffset = $0.range?.start.offset ?? Int.max
        let rhsOffset = $1.range?.start.offset ?? Int.max
        if lhsOffset != rhsOffset {
            return lhsOffset < rhsOffset
        }
        return $0.code.rawValue < $1.code.rawValue
    }
}

private extension Diagnostic {
    init(_ syntax: SyntaxDiagnostic) {
        self.init(
            severity: DiagnosticSeverity(rawValue: syntax.severity.rawValue) ?? .error,
            code: DiagnosticCode(rawValue: syntax.code),
            message: syntax.message,
            fileName: syntax.fileName,
            range: SourceRange(
                start: SourcePosition(
                    line: syntax.range.start.line,
                    column: syntax.range.start.column,
                    offset: syntax.range.start.offset
                ),
                end: SourcePosition(
                    line: syntax.range.end.line,
                    column: syntax.range.end.column,
                    offset: syntax.range.end.offset
                )
            )
        )
    }
}
