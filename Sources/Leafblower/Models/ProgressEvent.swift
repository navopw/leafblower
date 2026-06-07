struct ProgressEvent: Sendable {
    let scanID: String
    let currentPath: String?
    let directoriesVisited: Int64
    let filesVisited: Int64
    let bytesSeen: Int64
    let dirsQueued: Int64
    let dirsDone: Int64
}
