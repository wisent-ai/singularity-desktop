import SwiftUI
import WisentDesignSystem

struct EcosystemScreen: View {
    let directory: URL
    @StateObject private var store = EcosystemStore()
    @State private var recordsExpanded = false

    var body: some View {
        WisentScreen(title: "Ecosystem", scope: directory.path,
            freshness: store.status.map { "Owner observed at \($0.updatedAt)" }) {
            HStack {
                Button("Refresh") { Task { await store.refresh(directory) } }
                if let status = store.status {
                    Button(status.paused ? "Resume selection" : "Pause selection") {
                        Task { await store.setPaused(!status.paused, directory: directory) }
                    }
                }
                if store.busy { ProgressView().controlSize(.small) }
            }
            .disabled(store.busy)
            if let issue = store.issue {
                WisentEmptyPanel(title: "The operation did not complete", detail: issue, symbol: "exclamationmark.triangle")
            }
            if let status = store.status {
                WisentSignalStrip(signals: [
                    WisentSignal("Selection", value: status.paused ? "Paused" : status.lasCatalogReady ? "Enabled" : "Blocked",
                        tone: status.paused || !status.lasCatalogReady ? .warning : .brand),
                    WisentSignal("Active work", value: String(status.activeCount), tone: .neutral),
                    WisentSignal("Observations", value: String(status.observationCount), tone: .neutral)
                ])
                WisentCounterRow(counters: [
                    .init("Spent", value: "$\(status.spentUsd)", detail: "recorded model usage", tone: .neutral),
                    .init("Reserved", value: "$\(status.reservedUsd)", detail: "includes effects with unknown cost", tone: .warning),
                    .init("Limit", value: "$\(status.budgetUsd)", detail: "delegated portfolio allocation", tone: .brand)
                ])
                WisentSectionBox(title: "Delegated owner", trailing: status.owner.agentId) {
                    Text("\(status.owner.role) · \(status.owner.environment) · \(status.owner.workloadId)")
                    Text("Runtime: Singularity \(status.runtime.version)")
                    Text(status.runtime.sourceRevision ?? "No source revision was embedded in this runtime.")
                        .font(WisentTypeScale.identifierSmall()).textSelection(.enabled)
                    Text(status.lasCatalogReady
                        ? "The signed tool catalog was verified. Individual product operations still require their own evidence."
                        : "The signed tool catalog has not been verified. New selection and dispatch are blocked.")
                }
                Text("Pausing stops new selection and dispatch. Already dispatched work is reconciled, not cancelled or repeated.")
                    .font(WisentTypeScale.body())
                    .foregroundStyle(WisentDesign.secondary)
                ForEach(status.issues, id: \.operation) { issue in
                    WisentSectionBox(title: issue.operation, trailing: issue.code) {
                        Text(issue.message)
                    }
                }
            } else if !store.busy && store.issue == nil {
                WisentEmptyPanel(title: "No live owner response", detail: "Refresh to connect to the ecosystem owner in the selected folder.", symbol: "square.stack.3d.up")
            }
            EcosystemRecordsView(directory: directory, store: store, expanded: $recordsExpanded)
                .id(directory)
            if store.status != nil {
                Text("Collections are paged. Refresh returns to their newest entries.")
                    .foregroundStyle(WisentDesign.secondary)
                opportunities
                initiatives
            }
            if let explanation = store.explanation {
                WisentSectionBox(title: "Decision and delivery evidence") {
                    Text(explanation).font(.system(.body, design: .monospaced))
                }
            }
        }
        .task(id: directory) {
            recordsExpanded = false
            await store.refresh(directory)
        }
        .onDisappear { store.cancel() }
    }

    private var opportunities: some View {
        WisentSectionBox(title: "Opportunities", trailing: String(store.opportunities.count)) {
            if store.opportunities.isEmpty {
                Text("No opportunity has been recorded. An empty queue does not disable discovery.")
            }
            ForEach(store.opportunities) { opportunity in
                WisentPanel {
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                        HStack {
                            Text(opportunity.title).font(WisentTypeScale.bodyStrong())
                            Spacer()
                            WisentStatusChip(text: opportunity.status, tone: .neutral)
                        }
                        Text("\(opportunity.productId ?? "No product identity") · \(opportunity.kind) · estimated $\(opportunity.estimatedCostUsd)")
                        Text(opportunity.description)
                        Text("Why: \(opportunity.rationale)")
                        Text("Expected outcome: \(opportunity.expectedOutcome)")
                        Text("Reject when: \(opportunity.rejectionCondition)")
                        Text("Alternatives: \(opportunity.alternatives.joined(separator: "; "))")
                        Text("Uncertainty: \(opportunity.uncertainty)")
                        Text("Evidence: \(opportunity.evidenceRefs.joined(separator: ", "))")
                            .font(WisentTypeScale.identifierSmall())
                    }
                }
            }
            if store.opportunityNext != nil {
                Button("Read older opportunities") { Task { await store.olderOpportunities(directory) } }
                    .disabled(store.busy)
            }
        }
    }

    private var initiatives: some View {
        WisentSectionBox(title: "Initiatives", trailing: String(store.initiatives.count)) {
            if store.initiatives.isEmpty { Text("No initiative has passed independent selection.") }
            ForEach(store.initiatives) { initiative in
                WisentPanel {
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                        HStack {
                            Text(initiative.title).font(WisentTypeScale.bodyStrong())
                            Spacer()
                            WisentStatusChip(text: initiative.state, tone: initiative.blockedReason == nil ? .neutral : .warning)
                        }
                        Text(initiative.productId ?? "No product identity")
                        Text("Spent $\(initiative.spentUsd) · reserved $\(initiative.reservedUsd) · limit $\(initiative.budgetUsd)")
                        if let reason = initiative.blockedReason { Text(reason).foregroundStyle(WisentDesign.secondary) }
                        Button("Explain decision and delivery") {
                            Task { await store.explain(initiative.id, directory: directory) }
                        }
                        .disabled(store.busy)
                        Button("Browse execution and outcome history") {
                            recordsExpanded = true
                            Task { await store.loadRecords(directory, kind: nil, initiativeId: initiative.id) }
                        }
                        .disabled(store.busy)
                        Text(initiative.id).font(WisentTypeScale.identifierSmall())
                    }
                }
            }
            if store.initiativeNext != nil {
                Button("Read older initiatives") { Task { await store.olderInitiatives(directory) } }
                    .disabled(store.busy)
            }
        }
    }
}
