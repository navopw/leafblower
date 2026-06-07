struct DeleteResult: Sendable {
    let nodeID: String
    let path: String
    let error: String?

    init(nodeID: String, path: String = "", error: String? = nil) {
        self.nodeID = nodeID
        self.path = path
        self.error = error
    }
}

struct DeleteResponse: Sendable {
    let deleted: [DeleteResult]
    let failed: [DeleteResult]
}
