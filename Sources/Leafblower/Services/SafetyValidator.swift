import Foundation

enum SafetyValidator {
    static let criticalPaths: [String] = [
        "/", "/bin", "/sbin", "/usr", "/etc", "/lib", "/lib64",
        "/boot", "/dev", "/proc", "/sys", "/run",
        "/System", "/Library", "/Applications", "/Volumes", "/private"
    ]

    static func validate(path: String, scanRoot: String, homeDir: String?) -> String? {
        let cleanPath = PathUtils.cleanPath(path)
        let cleanRoot = PathUtils.cleanPath(scanRoot)

        let pathPrefix = cleanPath == "/" ? "/" : cleanPath + "/"
        let rootPrefix = cleanRoot == "/" ? "/" : cleanRoot + "/"

        // Must be under scan root
        if cleanPath != cleanRoot && !pathPrefix.hasPrefix(rootPrefix) {
            return "path is outside scan root"
        }

        // Cannot delete the scan root itself
        if cleanPath == cleanRoot {
            return "cannot delete scan root"
        }

        // Must be under home directory (v1 safety)
        if let home = homeDir {
            let cleanHome = PathUtils.cleanPath(home)
            let homePrefix = cleanHome == "/" ? "/" : cleanHome + "/"
            if cleanPath != cleanHome && !pathPrefix.hasPrefix(homePrefix) {
                return "deletion restricted to home directory in v1"
            }
        }

        // Defense-in-depth: never delete critical system directories
        for critical in criticalPaths {
            let criticalPrefix = critical + "/"
            if cleanPath == critical || pathPrefix.hasPrefix(criticalPrefix) {
                return "deletion of critical system path is not allowed"
            }
        }

        return nil
    }
}
