import Foundation

public enum SafePath {
    public static func components(_ path: String, directory: Bool = false) throws -> [String] {
        guard !path.isEmpty, path.utf8.count <= 1024,
              !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw EverPlayError.unsafePath(path)
        }
        let name = directory && path.hasSuffix("/") ? String(path.dropLast()) : path
        let parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 32, parts.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255
        }) else { throw EverPlayError.unsafePath(path) }
        return parts
    }

    public static func destination(_ path: String, in root: URL, directory: Bool = false) throws -> URL {
        let parts = try components(path, directory: directory)
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        var result = base
        for part in parts {
            result.appendPathComponent(part)
            // Check every existing component; never follow a link, even one pointing inside the root.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: result.path),
               attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                throw EverPlayError.unsafePath(path)
            }
        }
        guard result.standardizedFileURL.path.hasPrefix(base.path + "/") else {
            throw EverPlayError.unsafePath(path)
        }
        return result
    }
}
