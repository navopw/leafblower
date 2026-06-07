import Foundation

enum PathUtils {
    static func expandPath(_ path: String) -> String {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        } else if path.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return home + path.dropFirst(1)
        }
        return path
    }

    static func cleanPath(_ path: String) -> String {
        return (path as NSString).standardizingPath
    }

    /// Expands `~`, standardizes, and resolves symlinks so the path is canonical
    /// (e.g. `/tmp` → `/private/tmp`). Used for the scan root so the breadcrumb,
    /// child paths, and safety checks all reference the real location.
    static func canonicalPath(_ path: String) -> String {
        return (expandPath(path) as NSString).resolvingSymlinksInPath
    }

    /// Path of `path` relative to the scan `root` (e.g. "Personal/p0-mail"). The
    /// root itself shows as its own folder name.
    static func relativePath(_ path: String, to root: String) -> String {
        let p = cleanPath(path)
        let r = cleanPath(root)
        if p == r { return (r as NSString).lastPathComponent }
        let prefix = r.hasSuffix("/") ? r : r + "/"
        if p.hasPrefix(prefix) { return String(p.dropFirst(prefix.count)) }
        return p
    }
}
