import SwiftUI

struct ConnectionRow: View {
    @Bindable var connection: Connection

    var body: some View {
        HStack(spacing: 12) {
            TypeBadge(type: connection.type)

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
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(lastConnectedAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(lastConnectedAt.formatted(date: .abbreviated, time: .shortened))
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
