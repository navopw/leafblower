import Foundation
import os

enum FileSizeFormatter {
    private static let formatter = OSAllocatedUnfairLock(uncheckedState: {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }())

    static func string(from bytes: Int64) -> String {
        formatter.withLock { $0.string(fromByteCount: bytes) }
    }
}
