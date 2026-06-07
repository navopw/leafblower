import SwiftUI

/// Persistent bottom bar showing scan progress, results, or an idle hint.
struct StatusBarView: View {
    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if let job = ScanManager.shared.currentJob {
            switch job.status {
            case .queued, .running:
                scanningView(job)
            case .complete:
                completeView(job)
            case .failed:
                failedView(job)
            case .cancelled:
                Label("Scan cancelled", systemImage: "stop.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        } else {
            Text("Ready — enter a path and click Scan")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    // MARK: - States

    @ViewBuilder
    private func scanningView(_ job: ScanJob) -> some View {
        progressBar(job)
            .frame(width: 180)

        Text("Scanning…")
            .font(.callout.weight(.medium))

        if !job.currentPath.isEmpty {
            Text(abbreviate(job.currentPath))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }

        Spacer(minLength: 8)

        counters(job)

        Button {
            ScanManager.shared.cancelScan(id: job.id)
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func completeView(_ job: ScanJob) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)

        Text("Done")
            .font(.callout.weight(.medium))

        Text(FileSizeFormatter.string(from: job.rootNode?.sizeBytes ?? job.bytesSeen))
            .font(.callout.weight(.semibold))
            .monospacedDigit()

        Spacer(minLength: 8)

        counters(job)

        if !job.warnings.isEmpty {
            Label("\(job.warnings.count)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .help("\(job.warnings.count) path(s) could not be read")
        }
    }

    @ViewBuilder
    private func failedView(_ job: ScanJob) -> some View {
        Image(systemName: "xmark.octagon.fill")
            .foregroundStyle(.red)
        Text(job.warnings.first?.code ?? "Scan failed")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        Spacer(minLength: 8)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func progressBar(_ job: ScanJob) -> some View {
        if job.dirsQueued > 0 {
            ProgressView(value: min(1, Double(job.dirsDone) / Double(job.dirsQueued)))
                .progressViewStyle(.linear)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
        }
    }

    private func counters(_ job: ScanJob) -> some View {
        HStack(spacing: 10) {
            Label("\(job.directoriesVisited)", systemImage: "folder")
            Label("\(job.filesVisited)", systemImage: "doc")
            if job.status == .running || job.status == .queued {
                Text(FileSizeFormatter.string(from: job.bytesSeen))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
