import Foundation
import SwiftDiagramModel

public protocol DiagramRenderer: Sendable {
    var formatName: String { get }

    func render(
        _ diagram: Diagram,
        options: RenderOptions
    ) throws -> String
}

public struct RenderOptions: Equatable, Sendable, Codable {
    public var declarationAccessLevels: [AccessLevel]?
    public var memberAccessLevels: [AccessLevel]?
    public var includeMethods: Bool
    public var includeInferredRelationships: Bool
    public var includePrivateMembers: Bool
    public var extensionDisplayMode: ExtensionDisplayMode
    public var excludedElements: [String]
    public var excludedRelationshipTargets: [String]
    public var sortDeclarations: Bool
    public var orientation: DiagramOrientation?
    public var rendererOptions: [String: String]

    public init(
        declarationAccessLevels: [AccessLevel]? = nil,
        memberAccessLevels: [AccessLevel]? = nil,
        includeMethods: Bool = true,
        includeInferredRelationships: Bool = true,
        includePrivateMembers: Bool = false,
        extensionDisplayMode: ExtensionDisplayMode = .merged,
        excludedElements: [String] = [],
        excludedRelationshipTargets: [String] = [],
        sortDeclarations: Bool = true,
        orientation: DiagramOrientation? = nil,
        rendererOptions: [String: String] = [:]
    ) {
        self.declarationAccessLevels = declarationAccessLevels
        self.memberAccessLevels = memberAccessLevels
        self.includeMethods = includeMethods
        self.includeInferredRelationships = includeInferredRelationships
        self.includePrivateMembers = includePrivateMembers
        self.extensionDisplayMode = extensionDisplayMode
        self.excludedElements = excludedElements
        self.excludedRelationshipTargets = excludedRelationshipTargets
        self.sortDeclarations = sortDeclarations
        self.orientation = orientation
        self.rendererOptions = rendererOptions
    }
}

public enum ExtensionDisplayMode: String, Equatable, Sendable, Codable {
    case separate
    case merged
    case hidden
}

public enum DiagramOrientation: String, Equatable, Sendable, Codable {
    case topToBottom
    case bottomToTop
    case leftToRight
    case rightToLeft
}

public enum GlobPatternMatcher {
    public static func matches(_ value: String, pattern: String) -> Bool {
        let normalizedValue = value.replacingOccurrences(of: "\\", with: "/")
        let normalizedPattern = pattern.replacingOccurrences(of: "\\", with: "/")
        return normalizedValue.range(
            of: regularExpression(for: normalizedPattern),
            options: .regularExpression
        ) != nil
    }

    public static func matchesAny(_ value: String, patterns: [String]) -> Bool {
        patterns.contains { matches(value, pattern: $0) }
    }

    private static func regularExpression(for pattern: String) -> String {
        let characters = Array(pattern)
        var result = "^"
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "*" {
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    index += 2
                    if index < characters.count, characters[index] == "/" {
                        result += "(?:.*/)?"
                        index += 1
                    } else {
                        result += ".*"
                    }
                    continue
                }
                result += "[^/]*"
            } else if character == "?" {
                result += "[^/]"
            } else {
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index += 1
        }
        return result + "$"
    }
}
