/// Nodes are mutable only while a background scan builds its private tree. Once
/// published in a `ScanJob`, the tree is immutable and updates replace it.
final class Node: Identifiable, @unchecked Sendable {
    let id: String
    let name: String
    let path: String
    let parentID: String?
    var sizeBytes: Int64
    let isDir: Bool
    let isSymbolicLink: Bool
    let isMountPoint: Bool
    var childCount: Int
    var hasChildren: Bool
    var children: [Node]?
    var fileIdentity: FileIdentity?
    var isScanComplete: Bool

    init(
        id: String,
        name: String,
        path: String,
        parentID: String? = nil,
        sizeBytes: Int64,
        isDir: Bool,
        isSymbolicLink: Bool = false,
        isMountPoint: Bool = false,
        childCount: Int = 0,
        hasChildren: Bool = false,
        children: [Node]? = nil,
        fileIdentity: FileIdentity? = nil,
        isScanComplete: Bool = true
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.parentID = parentID
        self.sizeBytes = sizeBytes
        self.isDir = isDir
        self.isSymbolicLink = isSymbolicLink
        self.isMountPoint = isMountPoint
        self.childCount = childCount
        self.hasChildren = hasChildren
        self.children = children
        self.fileIdentity = fileIdentity
        self.isScanComplete = isScanComplete
    }
}
