import Foundation

@Observable @MainActor
final class ScanJob {
    let id: String
    let rootPath: String
    let includeHidden: Bool
    var status: ScanStatus
    var directoriesVisited: Int64
    var filesVisited: Int64
    var bytesSeen: Int64
    var dirsQueued: Int64
    var dirsDone: Int64
    var currentPath: String
    var warnings: [ScanWarning]
    var rootNode: Node?
    var nodeIndex: [String: Node]
    /// Bumped whenever the published tree is replaced so keyed views re-render.
    var treeRevision: Int = 0
    let createdAt: Date

    init(
        id: String,
        rootPath: String,
        includeHidden: Bool = false,
        status: ScanStatus = .queued,
        directoriesVisited: Int64 = 0,
        filesVisited: Int64 = 0,
        bytesSeen: Int64 = 0,
        dirsQueued: Int64 = 0,
        dirsDone: Int64 = 0,
        currentPath: String = "",
        warnings: [ScanWarning] = [],
        rootNode: Node? = nil,
        nodeIndex: [String: Node] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.rootPath = rootPath
        self.includeHidden = includeHidden
        self.status = status
        self.directoriesVisited = directoriesVisited
        self.filesVisited = filesVisited
        self.bytesSeen = bytesSeen
        self.dirsQueued = dirsQueued
        self.dirsDone = dirsDone
        self.currentPath = currentPath
        self.warnings = warnings
        self.rootNode = rootNode
        self.nodeIndex = nodeIndex
        self.createdAt = createdAt
    }
}
