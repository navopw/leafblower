import Foundation
import Darwin
import os

/// Identifies a file uniquely across volumes, for hardlink deduplication.
private struct DeviceInode: Hashable {
    let device: Int64
    let inode: UInt64
}

struct FileWalker {
    let includeHidden: Bool
    let onProgress: @Sendable (ProgressEvent) async -> Void

    func walk(scanID: String, rootPath: String) async throws -> (Node, [String: Node], [ScanWarning]) {
        let absRoot = PathUtils.cleanPath(rootPath)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: absRoot, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(domain: "Leafblower", code: 1, userInfo: [NSLocalizedDescriptionKey: "root path is not a directory: \(absRoot)"])
        }

        let rootNode = Node(
            id: "root",
            name: (absRoot as NSString).lastPathComponent,
            path: absRoot,
            sizeBytes: 0,
            isDir: true
        )

        let index = OSAllocatedUnfairLock(initialState: ["root": rootNode])
        let warnings = OSAllocatedUnfairLock(initialState: [ScanWarning]())
        let dirCount = OSAllocatedUnfairLock(initialState: Int64(0))
        let fileCount = OSAllocatedUnfairLock(initialState: Int64(0))
        let byteCount = OSAllocatedUnfairLock(initialState: Int64(0))
        let itemCount = OSAllocatedUnfairLock(initialState: Int64(0))
        let dirQueued = OSAllocatedUnfairLock(initialState: Int64(0))
        let dirDone = OSAllocatedUnfairLock(initialState: Int64(0))
        let seenInodes = OSAllocatedUnfairLock(initialState: Set<DeviceInode>())
        let idCounter = OSAllocatedUnfairLock(initialState: 0)
        let lastEmit = OSAllocatedUnfairLock(initialState: Int64(0))

        let numWorkers = min(128, max(16, ProcessInfo.processInfo.processorCount * 4))
        let sem = AsyncSemaphore(value: numWorkers)

        func nextID() -> String {
            idCounter.withLock { counter in
                counter += 1
                return "node_\(counter)"
            }
        }

        func emitProgress(currentPath: String) async {
            await onProgress(ProgressEvent(
                scanID: scanID,
                currentPath: currentPath,
                directoriesVisited: dirCount.withLock { $0 },
                filesVisited: fileCount.withLock { $0 },
                bytesSeen: byteCount.withLock { $0 },
                dirsQueued: dirQueued.withLock { $0 },
                dirsDone: dirDone.withLock { $0 }
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

        // Reads a single directory off disk (statting files, recording child
        // nodes) and returns the subdirectories to recurse into. It deliberately
        // does NOT recurse, so the caller can release its semaphore permit before
        // waiting on children. Holding a permit across the recursive wait is what
        // deadlocks the worker pool on deep trees.
        func readDirectory(path: String, dirNode: Node) -> [(String, Node)] {
            dirCount.withLock { $0 += 1 }

            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
                warnings.withLock { $0.append(ScanWarning(path: path, code: "permission_denied")) }
                return []
            }

            var children: [Node] = []
            var subdirs: [(String, Node)] = []

            for entry in entries {
                if !includeHidden && entry.hasPrefix(".") {
                    continue
                }

                let fullPath = (path as NSString).appendingPathComponent(entry)
                let url = URL(fileURLWithPath: fullPath)
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                if values?.isSymbolicLink == true {
                    continue
                }

                let isEntryDir = values?.isDirectory == true
                let node = Node(
                    id: nextID(),
                    name: entry,
                    path: fullPath,
                    parentID: dirNode.id,
                    sizeBytes: 0,
                    isDir: isEntryDir
                )
                children.append(node)

                if isEntryDir {
                    dirQueued.withLock { $0 += 1 }
                    subdirs.append((fullPath, node))
                } else {
                    var statbuf = stat()
                    if stat(fullPath, &statbuf) == 0 {
                        let diskSize = Int64(statbuf.st_blocks) * 512
                        if statbuf.st_nlink > 1 {
                            // Key on (device, inode): inode numbers are only unique
                            // within a volume, so scans crossing mount points must not
                            // dedup files that merely share an inode number.
                            let key = DeviceInode(device: Int64(statbuf.st_dev), inode: UInt64(statbuf.st_ino))
                            let alreadySeen = seenInodes.withLock { set -> Bool in
                                if set.contains(key) { return true }
                                set.insert(key)
                                return false
                            }
                            if !alreadySeen {
                                node.sizeBytes = diskSize
                                byteCount.withLock { $0 += diskSize }
                            }
                        } else {
                            node.sizeBytes = diskSize
                            byteCount.withLock { $0 += diskSize }
                        }
                    }
                    fileCount.withLock { $0 += 1 }
                }

                itemCount.withLock { $0 += 1 }
            }

            dirNode.children = children
            dirNode.childCount = children.count
            dirNode.hasChildren = !children.isEmpty

            let childrenCopy = children
            index.withLock { dict in
                for child in childrenCopy {
                    dict[child.id] = child
                }
            }

            return subdirs
        }

        func processDir(path: String, dirNode: Node) async {
            if Task.isCancelled {
                dirDone.withLock { $0 += 1 }
                return
            }

            // Hold a permit only while reading THIS directory off disk, then
            // release it before recursing so children can make progress.
            await sem.acquire()
            let subdirs = readDirectory(path: path, dirNode: dirNode)
            await sem.release()

            dirDone.withLock { $0 += 1 }
            await maybeEmit(currentPath: path)

            guard !subdirs.isEmpty, !Task.isCancelled else { return }

            await withTaskGroup(of: Void.self) { group in
                for (subPath, node) in subdirs {
                    group.addTask {
                        await processDir(path: subPath, dirNode: node)
                    }
                }
            }
        }

        dirQueued.withLock { $0 += 1 }
        await processDir(path: absRoot, dirNode: rootNode)

        if Task.isCancelled {
            throw CancellationError()
        }

        await maybeEmit(currentPath: absRoot, force: true)

        let _ = calcDirSize(rootNode)

        return (rootNode, index.withLock { $0 }, warnings.withLock { $0 })
    }

    @discardableResult
    private func calcDirSize(_ node: Node) -> Int64 {
        if !node.isDir { return node.sizeBytes }
        var total: Int64 = 0
        for child in node.children ?? [] {
            total += calcDirSize(child)
        }
        node.sizeBytes = total
        return total
    }
}
