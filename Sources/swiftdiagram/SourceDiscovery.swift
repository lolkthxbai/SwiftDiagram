import Foundation
import SwiftDiagramCore
import SwiftDiagramRendering

enum SourceDiscoveryError: LocalizedError {
    case missingPath(String)
    case unsupportedFile(String)
    case unreadableDirectory(String, String)
    case unreadableFile(String, String)
    case noMatches

    var errorDescription: String? {
        switch self {
        case .missingPath(let path):
            "input path does not exist: '\(path)'"
        case .unsupportedFile(let path):
            "input file must use the .swd extension: '\(path)'"
        case .unreadableDirectory(let path, let reason):
            "unable to enumerate '\(path)': \(reason)"
        case .unreadableFile(let path, let reason):
            "unable to read '\(path)': \(reason)"
        case .noMatches:
            "no .swd files matched the requested inputs and file filters"
        }
    }
}

func loadDiagramSources(
    inputs: [String],
    includePatterns: [String],
    excludePatterns: [String]
) throws -> [DiagramSource] {
    var candidates: [String: SourceCandidate] = [:]

    for input in inputs {
        let url = URL(fileURLWithPath: input).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw SourceDiscoveryError.missingPath(input)
        }

        if isDirectory.boolValue {
            for candidate in try sources(in: url) {
                if let existing = candidates[candidate.absolutePath] {
                    if candidate.relativePath < existing.relativePath {
                        candidates[candidate.absolutePath] = candidate
                    }
                } else {
                    candidates[candidate.absolutePath] = candidate
                }
            }
        } else {
            guard url.pathExtension.lowercased() == "swd" else {
                throw SourceDiscoveryError.unsupportedFile(input)
            }
            candidates[url.path] = SourceCandidate(
                absolutePath: url.path,
                relativePath: url.lastPathComponent
            )
        }
    }

    let selected = candidates.values
        .filter { candidate in
            let isIncluded = includePatterns.isEmpty ||
                GlobPatternMatcher.matchesAny(candidate.relativePath, patterns: includePatterns)
            return isIncluded &&
                !GlobPatternMatcher.matchesAny(candidate.relativePath, patterns: excludePatterns)
        }
        .sorted {
            ($0.relativePath, $0.absolutePath) < ($1.relativePath, $1.absolutePath)
        }

    guard !selected.isEmpty else {
        throw SourceDiscoveryError.noMatches
    }

    return try selected.map { candidate in
        do {
            return DiagramSource(
                path: candidate.absolutePath,
                contents: try String(contentsOfFile: candidate.absolutePath, encoding: .utf8)
            )
        } catch {
            throw SourceDiscoveryError.unreadableFile(candidate.absolutePath, error.localizedDescription)
        }
    }
}

private struct SourceCandidate {
    var absolutePath: String
    var relativePath: String
}

private func sources(in directory: URL) throws -> [SourceCandidate] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
    var enumerationError: Error?
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles],
        errorHandler: { _, error in
            enumerationError = error
            return false
        }
    ) else {
        throw SourceDiscoveryError.unreadableDirectory(directory.path, "enumeration could not start")
    }

    var result: [SourceCandidate] = []
    while let url = enumerator.nextObject() as? URL {
        let relativePath = path(of: url, relativeTo: directory)
        let values = try? url.resourceValues(forKeys: Set(keys))
        if values?.isDirectory == true {
            if isDefaultExcludedDirectory(relativePath) {
                enumerator.skipDescendants()
            }
            continue
        }
        guard values?.isRegularFile == true,
              url.pathExtension.lowercased() == "swd",
              !isDefaultExcludedPath(relativePath) else { continue }
        result.append(SourceCandidate(absolutePath: url.path, relativePath: relativePath))
    }

    if let enumerationError {
        throw SourceDiscoveryError.unreadableDirectory(
            directory.path,
            enumerationError.localizedDescription
        )
    }
    return result
}

private func path(of url: URL, relativeTo root: URL) -> String {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return String(url.path.dropFirst(rootPath.count)).replacingOccurrences(of: "\\", with: "/")
}

private func isDefaultExcludedDirectory(_ path: String) -> Bool {
    let name = path.split(separator: "/").last.map(String.init) ?? path
    return [".build", ".git", ".swiftpm", "DerivedData", "SourcePackages", "checkouts"]
        .contains(name)
}

private func isDefaultExcludedPath(_ path: String) -> Bool {
    path.split(separator: "/").contains { component in
        [".build", ".git", ".swiftpm", "DerivedData", "SourcePackages", "checkouts"]
            .contains(String(component))
    }
}
