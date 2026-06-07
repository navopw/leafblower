import Foundation

@Observable @MainActor
class ScanManager {
    static let shared = ScanManager()

    private(set) var jobs: [ScanJob] = []
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private let maxScans = 3
    private var counter = 0

    var selectedNodeIDs: Set<String> = []
    var currentZoomNodeID: String = "root"

    var currentJob: ScanJob? { jobs.last }

    private init() {}

    func startScan(rootPath: String, includeHidden: Bool) {
        counter += 1
        let id = "scan_\(counter)"
        let expanded = PathUtils.canonicalPath(rootPath)

        let job = ScanJob(
            id: id,
            rootPath: expanded,
            includeHidden: includeHidden,
            status: .queued,
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

        job.status = .running

        let scanID = id
        let path = expanded

        let task = Task.detached { [scanID, path, includeHidden] in
            let walker = FileWalker(includeHidden: includeHidden) { event in
                await MainActor.run {
                    ScanManager.shared.applyProgress(scanID: scanID, event: event)
                }
            }

            do {
                let (root, index, warnings) = try await walker.walk(scanID: scanID, rootPath: path)
                await MainActor.run {
                    ScanManager.shared.finalizeScan(
                        id: scanID,
                        root: root,
                        index: index,
                        warnings: warnings,
                        status: .complete
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    ScanManager.shared.finalizeScan(
                        id: scanID,
                        root: nil,
                        index: nil,
                        warnings: nil,
                        status: .cancelled
                    )
                }
            } catch {
                let description = error.localizedDescription
                await MainActor.run {
                    ScanManager.shared.finalizeScan(
                        id: scanID,
                        root: nil,
                        index: nil,
                        warnings: [ScanWarning(path: path, code: description)],
                        status: .failed
                    )
                }
            }
        }

        activeTasks[scanID] = task
    }

    func cancelScan(id: String) {
        activeTasks[id]?.cancel()
    }

    func toggleSelection(nodeID: String) {
        if selectedNodeIDs.contains(nodeID) {
            selectedNodeIDs.remove(nodeID)
        } else {
            selectedNodeIDs.insert(nodeID)
        }
    }

    func clearSelection() {
        selectedNodeIDs.removeAll()
    }

    func zoomInto(nodeID: String) {
        currentZoomNodeID = nodeID
    }

    func deleteSelected() async {
        guard let job = currentJob, !selectedNodeIDs.isEmpty else { return }
        guard let service = try? DeleteService() else { return }

        // `execute` deletes from disk and prunes the deleted nodes (and their sizes)
        // from the in-memory tree, so the map updates without a rescan.
        let response = service.execute(job: job, nodeIDs: Array(selectedNodeIDs))

        // Keep only nodes that failed to delete still selected, so the user sees them.
        selectedNodeIDs = Set(response.failed.map(\.nodeID)).intersection(selectedNodeIDs)

        // If we were zoomed inside something that just got deleted, fall back to root.
        if job.nodeIndex[currentZoomNodeID] == nil {
            currentZoomNodeID = job.rootNode?.id ?? "root"
        }
        job.treeRevision += 1
    }

    /// Re-runs the current scan against the same path.
    func rescan() {
        guard let job = currentJob else { return }
        startScan(rootPath: job.rootPath, includeHidden: job.includeHidden)
    }

    // MARK: - Private

    private func applyProgress(scanID: String, event: ProgressEvent) {
        guard let job = jobs.first(where: { $0.id == scanID }) else { return }
        job.directoriesVisited = event.directoriesVisited
        job.filesVisited = event.filesVisited
        job.bytesSeen = event.bytesSeen
        job.dirsQueued = event.dirsQueued
        job.dirsDone = event.dirsDone
        job.currentPath = event.currentPath ?? job.currentPath
    }

    private func finalizeScan(id: String, root: Node?, index: [String: Node]?, warnings: [ScanWarning]?, status: ScanStatus) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        if let root = root {
            job.rootNode = root
        }
        if let index = index {
            job.nodeIndex = index
        }
        if let warnings = warnings {
            job.warnings = warnings
        }
        job.status = status
        activeTasks.removeValue(forKey: id)
        if status == .complete, let root = root {
            currentZoomNodeID = root.id
        }
    }
}
