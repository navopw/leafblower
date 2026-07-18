import Foundation

struct DeleteVerification: Sendable {
    let path: String
    let identity: FileIdentity
}

struct DeleteRequest: Sendable {
    let nodeID: String
    let node: Node?
}

struct DeleteCandidate: Sendable {
    let nodeID: String
    let path: String
    let identity: FileIdentity
    let verificationItems: [DeleteVerification]
}

struct DeletePlan: Sendable {
    let scanRoot: String
    let scanRootIdentity: FileIdentity?
    let candidates: [DeleteCandidate]
    let preflightFailures: [DeleteResult]
}

struct RebuiltTree: Sendable {
    let root: Node
    let index: [String: Node]
}

struct DeleteService: Sendable {
    let homeDir: String
    private let moveItemToTrash: @Sendable (URL) throws -> Void

    init(
        homeDir: String = FileManager.default.homeDirectoryForCurrentUser.path,
        moveItemToTrash: @escaping @Sendable (URL) throws -> Void = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        self.homeDir = PathUtils.canonicalPath(homeDir)
        self.moveItemToTrash = moveItemToTrash
    }

    @MainActor
    func makePlan(job: ScanJob, nodeIDs: [String]) -> DeletePlan {
        let uniqueIDs = Array(Set(nodeIDs))
        let requests = uniqueIDs.map {
            DeleteRequest(nodeID: $0, node: job.nodeIndex[$0])
        }
        return makePlan(
            scanRoot: job.rootPath,
            scanRootIdentity: job.rootNode?.fileIdentity,
            scanIsComplete: job.status == .complete,
            requests: requests
        )
    }

    func makePlan(
        scanRoot: String,
        scanRootIdentity: FileIdentity?,
        scanIsComplete: Bool,
        requests: [DeleteRequest]
    ) -> DeletePlan {
        guard scanIsComplete else {
            return DeletePlan(
                scanRoot: scanRoot,
                scanRootIdentity: scanRootIdentity,
                candidates: [],
                preflightFailures: requests.map {
                    DeleteResult(nodeID: $0.nodeID, error: "scan is not complete")
                }
            )
        }

        var nodes: [Node] = []
        var failed: [DeleteResult] = []
        for request in requests {
            guard let node = request.node else {
                failed.append(DeleteResult(
                    nodeID: request.nodeID,
                    error: "node not found in scan"
                ))
                continue
            }
            nodes.append(node)
        }

        var candidates: [DeleteCandidate] = []
        for node in normalizeSelection(nodes).sorted(by: { $0.path < $1.path }) {
            if let error = SafetyValidator.validate(
                path: node.path,
                scanRoot: scanRoot,
                homeDir: homeDir,
                pathIsSymbolicLink: node.isSymbolicLink
            ) {
                failed.append(DeleteResult(nodeID: node.id, path: node.path, error: error))
                continue
            }

            if node.isDir && !node.isScanComplete {
                failed.append(DeleteResult(
                    nodeID: node.id,
                    path: node.path,
                    error: "directory was not fully scanned or has changed; rescan required"
                ))
                continue
            }

            if node.isMountPoint {
                failed.append(DeleteResult(
                    nodeID: node.id,
                    path: node.path,
                    error: "mounted volume roots cannot be moved"
                ))
                continue
            }

            guard let identity = node.fileIdentity else {
                failed.append(DeleteResult(
                    nodeID: node.id,
                    path: node.path,
                    error: "file identity is unavailable; rescan required"
                ))
                continue
            }

            guard let verificationItems = verificationItems(for: node) else {
                failed.append(DeleteResult(
                    nodeID: node.id,
                    path: node.path,
                    error: "part of this item was not fully scanned; rescan required"
                ))
                continue
            }

            candidates.append(DeleteCandidate(
                nodeID: node.id,
                path: node.path,
                identity: identity,
                verificationItems: verificationItems
            ))
        }

        return DeletePlan(
            scanRoot: scanRoot,
            scanRootIdentity: scanRootIdentity,
            candidates: candidates,
            preflightFailures: failed
        )
    }

    /// Performs only filesystem work and is safe to call away from the main actor.
    /// Items are never permanently removed if Trash is unavailable.
    func perform(_ plan: DeletePlan) -> DeleteResponse {
        var failed = plan.preflightFailures
        var deleted: [DeleteResult] = []

        guard let expectedRoot = plan.scanRootIdentity,
              let currentRoot = FileSystemEntry.read(atPath: plan.scanRoot)?.identity,
              currentRoot.identifiesSameItem(as: expectedRoot) else {
            failed.append(contentsOf: plan.candidates.map {
                DeleteResult(
                    nodeID: $0.nodeID,
                    path: $0.path,
                    error: "scan root changed or is unavailable; rescan required"
                )
            })
            return DeleteResponse(deleted: [], failed: failed)
        }

        for candidate in plan.candidates {
            if let error = validate(candidate: candidate, scanRoot: plan.scanRoot) {
                failed.append(DeleteResult(
                    nodeID: candidate.nodeID,
                    path: candidate.path,
                    error: error
                ))
                continue
            }

            do {
                try moveItemToTrash(URL(fileURLWithPath: candidate.path))
                deleted.append(DeleteResult(nodeID: candidate.nodeID, path: candidate.path))
            } catch {
                failed.append(DeleteResult(
                    nodeID: candidate.nodeID,
                    path: candidate.path,
                    error: error.localizedDescription
                ))
            }
        }

        return DeleteResponse(deleted: deleted, failed: failed)
    }

    /// Convenience entry point used by synchronous callers and tests.
    @MainActor
    func execute(job: ScanJob, nodeIDs: [String]) -> DeleteResponse {
        let response = perform(makePlan(job: job, nodeIDs: nodeIDs))
        if let root = job.rootNode,
           let rebuilt = rebuildTree(root: root, removing: Set(response.deleted.map(\.nodeID))) {
            job.rootNode = rebuilt.root
            job.nodeIndex = rebuilt.index
            job.treeRevision += 1
        }
        return response
    }

    func normalizeSelection(_ nodes: [Node]) -> [Node] {
        return nodes.filter { node in
            for possibleAncestor in nodes where possibleAncestor.id != node.id {
                if PathUtils.isSameOrDescendant(node.path, of: possibleAncestor.path) {
                    return false
                }
            }
            return true
        }
    }

    /// Rebuilds instead of mutating the published tree, so any background render
    /// still holding the old tree can finish without a data race.
    func rebuildTree(root: Node, removing removedIDs: Set<String>) -> RebuiltTree? {
        guard !removedIDs.isEmpty, !removedIDs.contains(root.id) else { return nil }

        var stack: [(node: Node, visited: Bool)] = [(root, false)]
        var clones: [String: Node] = [:]

        while let item = stack.popLast() {
            if removedIDs.contains(item.node.id) { continue }

            if !item.visited {
                stack.append((item.node, true))
                for child in (item.node.children ?? []).reversed() {
                    if !removedIDs.contains(child.id) {
                        stack.append((child, false))
                    }
                }
                continue
            }

            let originalChildren = item.node.children ?? []
            let children = originalChildren.compactMap { clones[$0.id] }
            let directlyChanged = children.count != originalChildren.count
            let scanComplete = item.node.isScanComplete
                && !directlyChanged
                && children.allSatisfy(\.isScanComplete)
            let size = item.node.isDir
                ? children.reduce(Int64(0)) { Self.saturatingAdd($0, $1.sizeBytes) }
                : item.node.sizeBytes

            let clone = Node(
                id: item.node.id,
                name: item.node.name,
                path: item.node.path,
                parentID: item.node.parentID,
                sizeBytes: size,
                isDir: item.node.isDir,
                isSymbolicLink: item.node.isSymbolicLink,
                isMountPoint: item.node.isMountPoint,
                childCount: children.count,
                hasChildren: !children.isEmpty,
                children: item.node.isDir ? children : nil,
                fileIdentity: item.node.fileIdentity,
                isScanComplete: scanComplete
            )
            clones[clone.id] = clone
        }

        guard let rebuiltRoot = clones[root.id] else { return nil }
        return RebuiltTree(root: rebuiltRoot, index: clones)
    }

    private func verificationItems(for node: Node) -> [DeleteVerification]? {
        var result: [DeleteVerification] = []
        var stack = [node]

        while let current = stack.popLast() {
            if current.isDir && !current.isScanComplete { return nil }
            guard let identity = current.fileIdentity else { return nil }
            result.append(DeleteVerification(path: current.path, identity: identity))
            stack.append(contentsOf: current.children ?? [])
        }

        return result
    }

    private func validate(candidate: DeleteCandidate, scanRoot: String) -> String? {
        if let error = SafetyValidator.validate(
            path: candidate.path,
            scanRoot: scanRoot,
            homeDir: homeDir,
            pathIsSymbolicLink: candidate.identity.isSymbolicLink
        ) {
            return error
        }

        for item in candidate.verificationItems {
            guard let current = FileSystemEntry.read(atPath: item.path)?.identity,
                  current == item.identity else {
                return "item changed or is unavailable; rescan required"
            }
        }

        // Narrow the check-to-use window for the selected item itself.
        guard let current = FileSystemEntry.read(atPath: candidate.path)?.identity,
              current == candidate.identity else {
            return "item changed or is unavailable; rescan required"
        }
        return nil
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflowed) = lhs.addingReportingOverflow(rhs)
        return overflowed ? Int64.max : sum
    }
}
