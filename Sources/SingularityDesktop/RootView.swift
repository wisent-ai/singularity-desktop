import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @ObservedObject var store: BeingStore
    @State private var choosingDirectory = false

    var body: some View {
        NavigationSplitView {
            List {
                Section("Being") {
                    Label("Life", systemImage: "sparkles")
                    Label("Mind", systemImage: "brain")
                    Label("Economy", systemImage: "chart.line.uptrend.xyaxis")
                    Label("Children", systemImage: "person.2")
                    Label("Activity", systemImage: "waveform.path.ecg")
                }
            }
            .navigationTitle("Singularity")
            .frame(minWidth: 210)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let issue = store.issue { issueView(issue) }
                    if let state = store.state {
                        metrics(state)
                        mind(state)
                        recent(state)
                    } else if store.issue == nil {
                        ProgressView("Reading the being…")
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(store.state?.identity.name ?? "Digital being")
            .toolbar {
                Button("State directory") { choosingDirectory = true }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .fileImporter(isPresented: $choosingDirectory, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { store.selectDirectory(url) }
        }
        .task { await store.monitor() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.state?.identity.name ?? "Singularity").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("A persistent autonomous digital being that creates value and earns its existence.")
                .font(.title3).foregroundStyle(.secondary)
            HStack {
                Text(store.stateDirectory.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                Button("Show") { store.openDirectory() }.buttonStyle(.link)
            }
        }
    }

    private func metrics(_ state: BeingState) -> some View {
        HStack(spacing: 14) {
            metric("Status", state.status.capitalized)
            metric("Cycle", "\(state.cycle)")
            metric("Balance", money(state.budget.remaining.value))
            metric("Earned", money(state.budget.earned.value))
            metric("Net", money(state.budget.netProfit))
            metric("Model", state.mind.currentModel)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private func mind(_ state: BeingState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Persistent mind").font(.title2.bold())
            Text(state.mind.systemPrompt).lineLimit(6)
            if !state.mind.rules.isEmpty { labeled("Self-imposed rules", state.mind.rules) }
            if !state.mind.learnings.isEmpty { labeled("Learnings", state.mind.learnings) }
            if !state.mind.memories.isEmpty { labeled("Memories", state.mind.memories.suffix(8).map { "[\($0.kind)] \($0.text)" }) }
            if !state.mind.children.isEmpty { labeled("Children", state.mind.children.map { "\($0.name) · \($0.ticker) · \($0.status)" }) }
        }
    }

    private func labeled(_ title: String, _ values: some Sequence<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            ForEach(Array(values), id: \.self) { Text("• \($0)").foregroundStyle(.secondary) }
        }
    }

    private func recent(_ state: BeingState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent activity").font(.title2.bold())
            if store.activity.isEmpty && state.recentActions.isEmpty { Text("No activity recorded yet.").foregroundStyle(.secondary) }
            ForEach(store.activity.prefix(30)) { item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.type.replacingOccurrences(of: "_", with: " ")).font(.body.weight(.medium))
                    Text(item.summary).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    if let date = item.timestamp { Text(date, style: .relative).font(.caption).foregroundStyle(.tertiary) }
                }.padding(.vertical, 3)
            }
        }
    }

    private func issueView(_ issue: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No being state at this location").font(.headline)
            Text(issue).foregroundStyle(.secondary)
            Button("Choose state directory") { choosingDirectory = true }
        }.padding(18).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func money(_ value: Decimal) -> String { "$" + NSDecimalNumber(decimal: value).stringValue }
}
