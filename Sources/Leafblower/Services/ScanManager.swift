import Foundation

private struct DeleteOperationOutcome: Sendable {
    let response: DeleteResponse
    let rebuiltTree: RebuiltTree?
}

@Observable @MainActor
final class ScanManager {
    private(set) var jobs: [ScanJob] = []
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private let maxScans = 1
    private var counter = 0

    var selectedNodeIDs: Set<String> = []
    var currentZoomNodeID = "root"
    private(set) var isDeleting = false

    var currentJob: ScanJob? { jobs.last }

    var isScanning: Bool {
        let status = currentJob?.status
        return status == .queued || status == .running || status == .cancelling
    }

    var canStartScan: Bool { !isScanning && !isDeleting }
    var canRescan: Bool { currentJob != nil && canStartScan }

    var selectedNodes: [Node] {
        guard let job = currentJob else { return [] }
        return selectedNodeIDs
            .compactMap { job.nodeIndex[$0] }
            .sorted { lhs, rhs in
                if lhs.sizeBytes == rhs.sizeBytes { return lhs.path < rhs.path }
                return lhs.sizeBytes > rhs.sizeBytes
            }
    }

    func startScan(rootPath: String, includeHidden: Bool) {
        guard canStartScan else { return }

        counter += 1
        let id = "scan_\(counter)"
        let expanded = PathUtils.canonicalPath(rootPath)

        selectedNodeIDs.removeAll()
        currentZoomNodeID = "root"

        let job = ScanJob(
            id: id,
            rootPath: expanded,
            includeHidden: includeHidden,
            status: .running,
            directoriesVisited: 0,
            filesVisited: 0,
            bytesSeen: 0,
            warnings: [],
            rootNode: nil,
            nodeIndex: [:],
            createdAt: Date()
        )
        jobs.append(job)

        while jobs.count > maxScans {
            let oldest = jobs.removeFirst()
            activeTasks[oldest.id]?.cancel()
            activeTasks.removeValue(forKey: oldest.id)
        }

        let scanID = id
        let path = expanded
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let walker = FileWalker(includeHidden: includeHidden) { [weak self] event in
                await self?.applyProgress(scanID: scanID, event: event)
            }

            do {
                let (root, index, warnings) = try await walker.walk(
                    scanID: scanID,
                    rootPath: path
                )
                await self?.finalizeScan(
                    id: scanID,
                    root: root,
                    index: index,
                    warnings: warnings,
                    status: .complete
                )
            } catch is CancellationError {
                await self?.finalizeScan(
                    id: scanID,
                    root: nil,
                    index: nil,
                    warnings: nil,
                    status: .cancelled
                )
            } catch {
                await self?.finalizeScan(
                    id: scanID,
                    root: nil,
                    index: nil,
                    warnings: [ScanWarning(path: path, code: error.localizedDescription)],
                    status: .failed
                )
            }
        }

        activeTasks[scanID] = task
    }

    func cancelScan(id: String) {
        if let job = jobs.first(where: { $0.id == id }), job.status == .running {
            job.status = .cancelling
        }
        activeTasks[id]?.cancel()
    }

    func toggleSelection(nodeID: String) {
        guard !isDeleting,
              let job = currentJob,
              job.status == .complete,
              let node = job.nodeIndex[nodeID],
              node.id != job.rootNode?.id else { return }

        if selectedNodeIDs.remove(nodeID) != nil { return }

        // Keep the selection non-overlapping. Selecting a child replaces its
        // selected ancestor, while selecting a folder replaces selected children.
        selectedNodeIDs = selectedNodeIDs.filter { selectedID in
            guard let selected = job.nodeIndex[selectedID] else { return false }
            let selectedContainsNode = PathUtils.isSameOrDescendant(node.path, of: selected.path)
            let nodeContainsSelected = PathUtils.isSameOrDescendant(selected.path, of: node.path)
            return !selectedContainsNode && !nodeContainsSelected
        }
        selectedNodeIDs.insert(nodeID)
    }

    func clearSelection() {
        guard !isDeleting else { return }
        selectedNodeIDs.removeAll()
    }

    func restoreSelection(_ nodeIDs: Set<String>) {
        guard !isDeleting, let job = currentJob else { return }
        selectedNodeIDs = nodeIDs.intersection(job.nodeIndex.keys)
    }

    func zoomInto(nodeID: String) {
        guard !isDeleting,
              let node = currentJob?.nodeIndex[nodeID],
              node.isDir else { return }
        currentZoomNodeID = nodeID
    }

    @discardableResult
    func deleteSelected() async -> DeleteResponse {
        guard let job = currentJob,
              job.status == .complete,
              !selectedNodeIDs.isEmpty,
              !isDeleting else {
            return DeleteResponse(deleted: [], failed: [])
        }

        isDeleting = true
        defer { isDeleting = false }

        let selectedIDs = Array(selectedNodeIDs)
        let service = DeleteService()
        let requests = selectedIDs.map {
            DeleteRequest(nodeID: $0, node: job.nodeIndex[$0])
        }
        let scanRoot = job.rootPath
        let scanRootIdentity = job.rootNode?.fileIdentity
        let root = job.rootNode

        let outcome = await Task.detached(priority: .userInitiated) {
            let plan = service.makePlan(
                scanRoot: scanRoot,
                scanRootIdentity: scanRootIdentity,
                scanIsComplete: true,
                requests: requests
            )
            let response = service.perform(plan)
            let removedIDs = Set(response.deleted.map(\.nodeID))
            let rebuilt = root.flatMap {
                service.rebuildTree(root: $0, removing: removedIDs)
            }
            return DeleteOperationOutcome(response: response, rebuiltTree: rebuilt)
        }.value

        guard currentJob?.id == job.id else { return outcome.response }
        if let rebuilt = outcome.rebuiltTree {
            job.rootNode = rebuilt.root
            job.nodeIndex = rebuilt.index
            job.treeRevision += 1
        }

        selectedNodeIDs = Set(outcome.response.failed.map(\.nodeID))
            .intersection(job.nodeIndex.keys)
        if job.nodeIndex[currentZoomNodeID] == nil {
            currentZoomNodeID = job.rootNode?.id ?? "root"
        }

        return outcome.response
    }

    func rescan() {
        guard canRescan, let job = currentJob else { return }
        startScan(rootPath: job.rootPath, includeHidden: job.includeHidden)
    }

    private func applyProgress(scanID: String, event: ProgressEvent) {
        guard event.scanID == scanID,
              let job = jobs.first(where: { $0.id == scanID }),
              job.status == .running else { return }
        job.directoriesVisited = event.directoriesVisited
        job.filesVisited = event.filesVisited
        job.bytesSeen = event.bytesSeen
        job.dirsQueued = event.dirsQueued
        job.dirsDone = event.dirsDone
        job.currentPath = event.currentPath ?? job.currentPath
    }

    private func finalizeScan(
        id: String,
        root: Node?,
        index: [String: Node]?,
        warnings: [ScanWarning]?,
        status: ScanStatus
    ) {
        activeTasks.removeValue(forKey: id)
        guard let job = jobs.first(where: { $0.id == id }) else { return }

        if let root { job.rootNode = root }
        if let index { job.nodeIndex = index }
        if let warnings { job.warnings = warnings }
        job.status = status

        if currentJob?.id == id, status == .complete, let root {
            currentZoomNodeID = root.id
        }
    }
}
