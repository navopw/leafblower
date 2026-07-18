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
        let expanded = expandPath(path)
        if (expanded as NSString).isAbsolutePath {
            return (expanded as NSString).standardizingPath
        }

        return ((FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent(expanded) as NSString).standardizingPath
    }

    /// Expands `~`, standardizes, and resolves symlinks so the path is canonical
    /// (e.g. `/tmp` → `/private/tmp`). Used for the scan root so the breadcrumb,
    /// child paths, and safety checks all reference the real location.
    ///
    /// Walks components so intermediate directory symlinks still resolve when the
    /// final path component does not exist yet.
    static func canonicalPath(_ path: String) -> String {
        let clean = cleanPath(path)
        guard clean != "/" else { return clean }

        var resolved = "/"
        let components = (clean as NSString).pathComponents.filter { $0 != "/" }
        for (index, component) in components.enumerated() {
            let candidate = (resolved as NSString).appendingPathComponent(component)
            let isLast = index == components.count - 1
            if isLast {
                // Preserve a final missing leaf, but still resolve when it exists.
                if FileManager.default.fileExists(atPath: candidate) {
                    resolved = (candidate as NSString).resolvingSymlinksInPath
                } else {
                    resolved = candidate
                }
            } else {
                resolved = (candidate as NSString).resolvingSymlinksInPath
            }
        }
        return resolved
    }

    /// Resolves every path component except the final one. Moving a symbolic link
    /// affects the link itself, not its destination, but its parent must still be
    /// inside the permitted directory.
    static func canonicalPathPreservingLastComponent(_ path: String) -> String {
        let clean = cleanPath(path)
        guard clean != "/" else { return clean }
        let name = (clean as NSString).lastPathComponent
        let parent = (clean as NSString).deletingLastPathComponent
        return (canonicalPath(parent) as NSString).appendingPathComponent(name)
    }

    static func isSameOrDescendant(_ path: String, of root: String) -> Bool {
        path == root || (root == "/" ? path.hasPrefix("/") : path.hasPrefix(root + "/"))
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
