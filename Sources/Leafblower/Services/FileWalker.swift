import Foundation
import os

/// Identifies a file uniquely across volumes for hard-link accounting.
private struct DeviceInode: Hashable {
    let device: Int64
    let inode: UInt64
}

private enum FileWalkerError: LocalizedError {
    case rootIsNotDirectory(String)
    case rootIsUnreadable(String)

    var errorDescription: String? {
        switch self {
        case .rootIsNotDirectory(let path):
            return "root path is not a directory: \(path)"
        case .rootIsUnreadable(let message):
            return "could not read scan root: \(message)"
        }
    }
}

private actor DirectoryWorkQueue {
    struct Item: Sendable {
        let path: String
        let node: Node
    }

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Item?, Never>
    }

    private var queue: [Item]
    private var queueIndex = 0
    private var outstandingItems = 1
    private var waiters: [Waiter] = []
    private var isFinished = false

    init(root: Item) {
        queue = [root]
    }

    func next() async -> Item? {
        if let item = dequeue() {
            return item
        }
        if isFinished { return nil }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let item = dequeue() {
                    continuation.resume(returning: item)
                    return
                }
                if isFinished {
                    continuation.resume(returning: nil)
                    return
                }
                waiters.append(Waiter(id: id, continuation: continuation))
                if isFinished, let index = waiters.firstIndex(where: { $0.id == id }) {
                    let waiter = waiters.remove(at: index)
                    waiter.continuation.resume(returning: nil)
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func finish(with children: [Item]) {
        guard !isFinished else { return }
        outstandingItems -= 1
        outstandingItems += children.count

        var childIndex = 0
        while childIndex < children.count, let waiter = waiters.popLast() {
            waiter.continuation.resume(returning: children[childIndex])
            childIndex += 1
        }
        if childIndex < children.count {
            queue.append(contentsOf: children[childIndex...])
        }

        if outstandingItems == 0 {
            finishQueue()
        }
    }

    func cancel() {
        guard !isFinished else { return }
        outstandingItems = 0
        queue.removeAll(keepingCapacity: false)
        queueIndex = 0
        finishQueue()
    }

    private func dequeue() -> Item? {
        guard queueIndex < queue.count else { return nil }
        let item = queue[queueIndex]
        queueIndex += 1
        compactQueueIfNeeded()
        return item
    }

    private func compactQueueIfNeeded() {
        if queueIndex == queue.count {
            queue.removeAll(keepingCapacity: true)
            queueIndex = 0
        } else if queueIndex > 1_024 {
            queue.removeFirst(queueIndex)
            queueIndex = 0
        }
    }

    private func finishQueue() {
        isFinished = true
        let pendingWaiters = waiters
        waiters.removeAll(keepingCapacity: false)
        for waiter in pendingWaiters {
            waiter.continuation.resume(returning: nil)
        }
    }
}

struct FileWalker: Sendable {
    let includeHidden: Bool
    let onProgress: @Sendable (ProgressEvent) async -> Void

    func walk(scanID: String, rootPath: String) async throws -> (Node, [String: Node], [ScanWarning]) {
        let absoluteRoot = PathUtils.canonicalPath(rootPath)
        guard let rootEntry = FileSystemEntry.read(atPath: absoluteRoot),
              rootEntry.identity.isDirectory else {
            throw FileWalkerError.rootIsNotDirectory(absoluteRoot)
        }

        let rootNode = Node(
            id: "root",
            name: absoluteRoot == "/" ? "/" : (absoluteRoot as NSString).lastPathComponent,
            path: absoluteRoot,
            sizeBytes: 0,
            isDir: true,
            fileIdentity: rootEntry.identity
        )

        let index = OSAllocatedUnfairLock(initialState: ["root": rootNode])
        let warnings = OSAllocatedUnfairLock(initialState: [ScanWarning]())
        let directoryCount = OSAllocatedUnfairLock(initialState: Int64(0))
        let fileCount = OSAllocatedUnfairLock(initialState: Int64(0))
        let byteCount = OSAllocatedUnfairLock(initialState: Int64(0))
        let itemCount = OSAllocatedUnfairLock(initialState: Int64(0))
        let directoriesQueued = OSAllocatedUnfairLock(initialState: Int64(1))
        let directoriesDone = OSAllocatedUnfairLock(initialState: Int64(0))
        let seenInodes = OSAllocatedUnfairLock(initialState: Set<DeviceInode>())
        let idCounter = OSAllocatedUnfairLock(initialState: 0)
        let lastEmit = OSAllocatedUnfairLock(initialState: Int64(0))
        let rootReadError = OSAllocatedUnfairLock<String?>(initialState: nil)

        func nextID() -> String {
            idCounter.withLock { counter in
                counter += 1
                return "node_\(counter)"
            }
        }

        func recordWarning(path: String, code: String) {
            warnings.withLock { recorded in
                if recorded.count < 1_000 {
                    recorded.append(ScanWarning(path: path, code: code))
                } else if recorded.count == 1_000 {
                    recorded.append(ScanWarning(
                        path: absoluteRoot,
                        code: "additional scan warnings omitted"
                    ))
                }
            }
        }

        func emitProgress(currentPath: String) async {
            await onProgress(ProgressEvent(
                scanID: scanID,
                currentPath: currentPath,
                directoriesVisited: directoryCount.withLock { $0 },
                filesVisited: fileCount.withLock { $0 },
                bytesSeen: byteCount.withLock { $0 },
                dirsQueued: directoriesQueued.withLock { $0 },
                dirsDone: directoriesDone.withLock { $0 }
            ))
        }

        func maybeEmit(currentPath: String, force: Bool = false) async {
            let total = itemCount.withLock { $0 }
            let shouldEmit = lastEmit.withLock { last -> Bool in
                if force || total - last >= 750 {
                    last = total
                    return true
                }
                return false
            }
            if shouldEmit {
                await emitProgress(currentPath: currentPath)
            }
        }

        func readDirectory(_ item: DirectoryWorkQueue.Item) -> [DirectoryWorkQueue.Item] {
            directoryCount.withLock { $0 += 1 }
            let initialIdentity = item.node.fileIdentity

            let entries: [String]
            do {
                entries = try FileManager.default.contentsOfDirectory(atPath: item.path)
            } catch {
                item.node.isScanComplete = false
                recordWarning(path: item.path, code: error.localizedDescription)
                if item.node.id == rootNode.id {
                    rootReadError.withLock { $0 = error.localizedDescription }
                }
                return []
            }

            var children: [Node] = []
            var subdirectories: [DirectoryWorkQueue.Item] = []

            for entryName in entries {
                if Task.isCancelled { break }
                if !includeHidden && entryName.hasPrefix(".") {
                    item.node.isScanComplete = false
                    continue
                }

                let fullPath = (item.path as NSString).appendingPathComponent(entryName)
                guard let entry = FileSystemEntry.read(atPath: fullPath) else {
                    item.node.isScanComplete = false
                    recordWarning(path: fullPath, code: "metadata unavailable")
                    continue
                }

                let identity = entry.identity
                guard identity.isDirectory || identity.isRegularFile || identity.isSymbolicLink else {
                    item.node.isScanComplete = false
                    recordWarning(path: fullPath, code: "unsupported file type")
                    continue
                }

                let node = Node(
                    id: nextID(),
                    name: entryName,
                    path: fullPath,
                    parentID: item.node.id,
                    sizeBytes: 0,
                    isDir: identity.isDirectory,
                    isSymbolicLink: identity.isSymbolicLink,
                    isMountPoint: identity.isDirectory
                        && item.node.fileIdentity.map { identity.device != $0.device } == true,
                    fileIdentity: identity
                )
                children.append(node)

                if identity.isDirectory {
                    subdirectories.append(DirectoryWorkQueue.Item(path: fullPath, node: node))
                } else {
                    let key = DeviceInode(device: identity.device, inode: identity.inode)
                    let shouldCountSize: Bool
                    if identity.linkCount > 1 {
                        shouldCountSize = seenInodes.withLock { seen -> Bool in
                            seen.insert(key).inserted
                        }
                    } else {
                        shouldCountSize = true
                    }

                    if shouldCountSize {
                        node.sizeBytes = entry.allocatedSize
                        byteCount.withLock { count in
                            count = Self.saturatingAdd(count, entry.allocatedSize)
                        }
                    }
                    fileCount.withLock { $0 += 1 }
                }

                itemCount.withLock { $0 += 1 }
            }

            item.node.children = children
            item.node.childCount = children.count
            item.node.hasChildren = !children.isEmpty

            let childrenToIndex = children
            index.withLock { nodeIndex in
                for child in childrenToIndex {
                    nodeIndex[child.id] = child
                }
            }
            let subdirectoryCount = Int64(subdirectories.count)
            directoriesQueued.withLock { $0 += subdirectoryCount }

            if let refreshed = FileSystemEntry.read(atPath: item.path)?.identity,
               let initialIdentity,
               refreshed.identifiesSameItem(as: initialIdentity) {
                if refreshed != initialIdentity {
                    item.node.isScanComplete = false
                    recordWarning(path: item.path, code: "directory changed during scan")
                }
                item.node.fileIdentity = refreshed
            } else {
                item.node.isScanComplete = false
                recordWarning(path: item.path, code: "directory changed during scan")
            }

            return subdirectories
        }

        let workQueue = DirectoryWorkQueue(
            root: DirectoryWorkQueue.Item(path: absoluteRoot, node: rootNode)
        )
        let workerCount = min(32, max(4, ProcessInfo.processInfo.processorCount * 2))

        await withTaskCancellationHandler(operation: {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0 ..< workerCount {
                    group.addTask {
                        while let item = await workQueue.next() {
                            if Task.isCancelled {
                                await workQueue.cancel()
                                return
                            }

                            let subdirectories = readDirectory(item)
                            directoriesDone.withLock { $0 += 1 }
                            if Task.isCancelled {
                                await workQueue.cancel()
                                return
                            }
                            await workQueue.finish(with: subdirectories)
                            await maybeEmit(currentPath: item.path)
                        }
                    }
                }
            }
        }, onCancel: {
            _ = Task { await workQueue.cancel() }
        })

        try Task.checkCancellation()
        if let message = rootReadError.withLock({ $0 }) {
            throw FileWalkerError.rootIsUnreadable(message)
        }
        await maybeEmit(currentPath: absoluteRoot, force: true)
        calculateDirectorySizes(rootNode)

        return (rootNode, index.withLock { $0 }, warnings.withLock { $0 })
    }

    private func calculateDirectorySizes(_ root: Node) {
        var stack: [(node: Node, visited: Bool)] = [(root, false)]

        while let item = stack.popLast() {
            guard item.node.isDir else { continue }
            if !item.visited {
                stack.append((item.node, true))
                for child in item.node.children ?? [] where child.isDir {
                    stack.append((child, false))
                }
                continue
            }

            var total: Int64 = 0
            for child in item.node.children ?? [] {
                total = Self.saturatingAdd(total, child.sizeBytes)
                if child.isDir && !child.isScanComplete {
                    item.node.isScanComplete = false
                }
            }
            item.node.sizeBytes = total
        }
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflowed) = lhs.addingReportingOverflow(rhs)
        return overflowed ? Int64.max : sum
    }
}
