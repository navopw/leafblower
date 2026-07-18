import Foundation

enum SafetyValidator {
    static let criticalPaths: [String] = [
        "/", "/bin", "/sbin", "/usr", "/etc", "/lib", "/lib64",
        "/boot", "/dev", "/proc", "/sys", "/run",
        "/System", "/Library", "/Applications", "/Volumes", "/private"
    ]

    static func validate(
        path: String,
        scanRoot: String,
        homeDir: String?,
        pathIsSymbolicLink: Bool = false
    ) -> String? {
        let expandedPath = PathUtils.expandPath(path)
        guard (expandedPath as NSString).isAbsolutePath else {
            return "path is not absolute"
        }

        let cleanPath = PathUtils.cleanPath(path)
        let lexicalRoot = PathUtils.cleanPath(scanRoot)
        let cleanRoot = PathUtils.canonicalPath(scanRoot)

        // Check the recorded path before resolving links, then check the real
        // location to catch a parent directory replaced by a symbolic link.
        let isLexicallyContained = PathUtils.isSameOrDescendant(cleanPath, of: lexicalRoot)
            || PathUtils.isSameOrDescendant(cleanPath, of: cleanRoot)
        if !isLexicallyContained {
            return "path is outside scan root"
        }

        if cleanPath == lexicalRoot || cleanPath == cleanRoot {
            return "cannot move scan root"
        }

        let effectivePath = pathIsSymbolicLink
            ? PathUtils.canonicalPathPreservingLastComponent(cleanPath)
            : PathUtils.canonicalPath(cleanPath)
        if !PathUtils.isSameOrDescendant(effectivePath, of: cleanRoot) {
            return "path resolves outside scan root"
        }

        if let home = homeDir {
            let cleanHome = PathUtils.canonicalPath(home)
            if effectivePath == cleanHome {
                return "cannot move home directory"
            }
            if !PathUtils.isSameOrDescendant(effectivePath, of: cleanHome) {
                return "removal is restricted to the home directory in v1"
            }

            let trash = (cleanHome as NSString).appendingPathComponent(".Trash")
            if PathUtils.isSameOrDescendant(effectivePath, of: trash) {
                return "items already in Trash cannot be removed by Leafblower"
            }
        }

        for critical in criticalPaths {
            let canonicalCritical = PathUtils.canonicalPath(critical)
            if effectivePath == canonicalCritical
                || (canonicalCritical != "/"
                    && PathUtils.isSameOrDescendant(effectivePath, of: canonicalCritical)) {
                return "critical system paths cannot be moved"
            }
        }

        return nil
    }
}
