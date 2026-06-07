struct ProgressEvent: Sendable {
    let type: String
    let scanID: String
    let phase: String?
    let currentPath: String?
    let directoriesVisited: Int64
    let filesVisited: Int64
    let bytesSeen: Int64
    let dirsQueued: Int64
    let dirsDone: Int64
    let warningCount: Int
    let rootNodeID: String?
}
