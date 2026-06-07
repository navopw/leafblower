final class Node: Identifiable, @unchecked Sendable {
    let id: String
    let name: String
    let path: String
    let parentID: String?
    var sizeBytes: Int64
    let isDir: Bool
    var childCount: Int
    var hasChildren: Bool
    var children: [Node]?

    init(
        id: String,
        name: String,
        path: String,
        parentID: String? = nil,
        sizeBytes: Int64,
        isDir: Bool,
        childCount: Int = 0,
        hasChildren: Bool = false,
        children: [Node]? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.parentID = parentID
        self.sizeBytes = sizeBytes
        self.isDir = isDir
        self.childCount = childCount
        self.hasChildren = hasChildren
        self.children = children
    }
}
