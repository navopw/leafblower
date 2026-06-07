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
}
