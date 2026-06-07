enum ScanStatus: String, Sendable {
    case queued
    case running
    case complete
    case failed
    case cancelled
}
