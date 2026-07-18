import Darwin

/// Metadata captured with `lstat`, so symbolic links are identified without
/// following them. Exact equality is intentionally conservative: an item that
/// changes after a scan must be scanned again before it can be moved to Trash.
struct FileIdentity: Equatable, Sendable {
    let device: Int64
    let inode: UInt64
    let fileType: UInt16
    let size: Int64
    let linkCount: UInt64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64

    var isDirectory: Bool { fileType == UInt16(S_IFDIR) }
    var isRegularFile: Bool { fileType == UInt16(S_IFREG) }
    var isSymbolicLink: Bool { fileType == UInt16(S_IFLNK) }

    func identifiesSameItem(as other: FileIdentity) -> Bool {
        device == other.device && inode == other.inode && fileType == other.fileType
    }
}

struct FileSystemEntry: Sendable {
    let identity: FileIdentity
    let allocatedSize: Int64

    static func read(atPath path: String) -> FileSystemEntry? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }

        let blocks = max(Int64(0), Int64(info.st_blocks))
        let (byteCount, overflowed) = blocks.multipliedReportingOverflow(by: 512)
        let identity = FileIdentity(
            device: Int64(info.st_dev),
            inode: UInt64(info.st_ino),
            fileType: UInt16(info.st_mode) & UInt16(S_IFMT),
            size: Int64(info.st_size),
            linkCount: UInt64(info.st_nlink),
            modificationSeconds: Int64(info.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(info.st_mtimespec.tv_nsec)
        )

        return FileSystemEntry(
            identity: identity,
            allocatedSize: overflowed ? Int64.max : byteCount
        )
    }
}
