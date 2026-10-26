import SwiftUI

struct ConnectionRow: View {
    @Bindable var connection: Connection
    var status: ReachabilityMonitor.Status?

    static let visibleTagCount = 3

    var body: some View {
        HStack(spacing: 12) {
            TypeBadge(type: connection.type)
                .overlay(alignment: .bottomTrailing) {
                    if let status {
                        StatusDot(status: status)
                            .offset(x: 3, y: 3)
                    }
                }
                .help(status.map(StatusDot.description) ?? "")

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(connection.summary)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let lastConnectedAt = connection.lastConnectedAt {
                // Refreshes once a minute so "2 minutes ago" keeps counting.
                TimelineView(.everyMinute) { _ in
                    Text(lastConnectedAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(lastConnectedAt.formatted(date: .abbreviated, time: .shortened))
            }

            if !connection.notes.isEmpty {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                    .help(connection.notes)
            }

            ForEach(connection.tags.prefix(Self.visibleTagCount), id: \.self) { tag in
                Text(verbatim: "#\(tag)")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
            if connection.tags.count > Self.visibleTagCount {
                Text(verbatim: "+\(connection.tags.count - Self.visibleTagCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(connection.tags.dropFirst(Self.visibleTagCount).map { "#\($0)" }.joined(separator: " "))
            }

            if let group = connection.group {
                Text(group.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(.regular, in: .capsule)
            }

            Button {
                connection.isFavorite.toggle()
            } label: {
                Image(systemName: connection.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(connection.isFavorite ? .yellow : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help(connection.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
        .padding(.vertical, 4)
    }
}

struct TypeBadge: View {
    var type: ConnectionType
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: type.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(type.tint)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(type.tint.opacity(0.18)), in: .rect(cornerRadius: size * 0.28))
            .accessibilityLabel(type.title)
    }
}

/// Green when the server's port answers (or a serial device is plugged in), red when it doesn't,
/// gray while checking.
struct StatusDot: View {
    var status: ReachabilityMonitor.Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
            .accessibilityLabel(Self.description(status))
    }

    private var color: Color {
        switch status {
        case .checking: .gray
        case .reachable, .deviceConnected: .green
        case .unreachable: .red
        }
    }

    static func description(_ status: ReachabilityMonitor.Status) -> String {
        switch status {
        case .checking:
            String(localized: "Checking…")
        case .reachable(let latency):
            String(localized: "Reachable · \(Int(latency.timeInterval * 1000)) ms")
        case .unreachable(let reason):
            String(localized: "Unreachable: \(reason)")
        case .deviceConnected:
            String(localized: "Device connected")
        }
    }
}
