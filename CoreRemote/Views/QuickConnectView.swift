import SwiftData
import SwiftUI

/// Spotlight-style search over all connections: type, pick with the arrow keys, Return to connect.
struct QuickConnectView: View {
    var onClose: () -> Void

    @Environment(ConnectionLauncher.self) private var launcher
    @Query(sort: \Connection.name) private var connections: [Connection]
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var results: [Connection] {
        QuickConnectSearch.results(for: query, in: connections)
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField("Connect to…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($isSearchFocused)
                    .onSubmit { connect(results) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            if results.isEmpty {
                ContentUnavailableView(
                    connections.isEmpty ? "No Connections" : "No Matches",
                    systemImage: connections.isEmpty ? "network" : "magnifyingglass"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, connection in
                                QuickConnectRow(connection: connection, isSelected: index == selectedIndex)
                                    .id(index)
                                    .contentShape(.rect)
                                    .onTapGesture {
                                        selectedIndex = index
                                        connect(results)
                                    }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) {
                        proxy.scrollTo(selectedIndex)
                    }
                }
            }
        }
        .frame(width: QuickConnectPanel.size.width, height: QuickConnectPanel.size.height)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(selectedIndex + 1, max(results.count - 1, 0))
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onChange(of: query) { selectedIndex = 0 }
        .onAppear { isSearchFocused = true }
    }

    private func connect(_ results: [Connection]) {
        guard results.indices.contains(selectedIndex) else { return }
        let connection = results[selectedIndex]
        onClose()
        Task {
            await launcher.open(connection)
            if let problem = launcher.launchProblem {
                launcher.launchProblem = nil
                LaunchProblemAlert.run(problem, launcher: launcher)
            }
        }
    }
}

private struct QuickConnectRow: View {
    var connection: Connection
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            TypeBadge(type: connection.type, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(connection.summary)
                    .font(.callout.monospaced())
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let group = connection.group {
                Text(group.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if connection.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10))
    }
}
