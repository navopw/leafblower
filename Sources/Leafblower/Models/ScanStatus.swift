enum ScanStatus: String, Sendable {
    case queued
    case running
    case cancelling
    case complete
    case failed
    case cancelled
}
