import Foundation

struct DeleteService {
    let homeDir: String

    init() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.homeDir = home.path
    }

    @MainActor
    func execute(job: ScanJob, nodeIDs: [String]) -> DeleteResponse {
        guard job.status == .complete else {
            let failed = nodeIDs.map { DeleteResult(nodeID: $0, error: "scan is not complete") }
            return DeleteResponse(deleted: [], failed: failed)
        }

        var nodes: [Node] = []
        var failed: [DeleteResult] = []

        for id in nodeIDs {
            guard let node = job.nodeIndex[id] else {
                failed.append(DeleteResult(nodeID: id, error: "node not found in scan"))
                continue
            }
            nodes.append(node)
        }

        nodes = normalizeSelection(nodes)

        var deleted: [DeleteResult] = []

        for node in nodes {
            if let error = SafetyValidator.validate(path: node.path, scanRoot: job.rootPath, homeDir: homeDir) {
                failed.append(DeleteResult(nodeID: node.id, path: node.path, error: error))
                continue
            }

            do {
                try FileManager.default.removeItem(atPath: node.path)
                pruneNode(job: job, node: node)
                deleted.append(DeleteResult(nodeID: node.id, path: node.path))
            } catch {
                failed.append(DeleteResult(nodeID: node.id, path: node.path, error: error.localizedDescription))
            }
        }

        return DeleteResponse(deleted: deleted, failed: failed)
    }

    func normalizeSelection(_ nodes: [Node]) -> [Node] {
        let pathSet = Set(nodes.map(\.path))
        return nodes.filter { !hasAncestor($0.path, in: pathSet) }
    }

    private func hasAncestor(_ path: String, in set: Set<String>) -> Bool {
        var parent = (path as NSString).deletingLastPathComponent
        var current = path
        while parent != current {
            if set.contains(parent) { return true }
            let next = (parent as NSString).deletingLastPathComponent
            current = parent
            parent = next
        }
        return false
    }

    @MainActor
    private func pruneNode(job: ScanJob, node: Node) {
        if let parentID = node.parentID, let parent = job.nodeIndex[parentID] {
            parent.children?.removeAll { $0.id == node.id }
            parent.childCount = parent.children?.count ?? 0
            parent.hasChildren = parent.childCount > 0
        }

        let sizeToRemove = node.sizeBytes
        var currentID: String? = node.parentID
        while let id = currentID, let parent = job.nodeIndex[id] {
            parent.sizeBytes -= sizeToRemove
            currentID = parent.parentID
        }

        removeFromIndex(job: job, node: node)
    }

    @MainActor
    private func removeFromIndex(job: ScanJob, node: Node) {
        job.nodeIndex.removeValue(forKey: node.id)
        for child in node.children ?? [] {
            removeFromIndex(job: job, node: child)
        }
    }
}
