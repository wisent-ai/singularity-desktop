import SwiftUI
import WisentDesignSystem

struct BeingScreenChrome {
    let scope: String?
    let freshness: String?
    let actions: [WisentAction]
    let issue: String?
}

struct BeingLifeScreen: View {
    let state: BeingState
    let activity: [ActivityLine]
    let chrome: BeingScreenChrome

    var body: some View {
        WisentScreen(
            title: BeingDestination.life.title,
            scope: chrome.scope,
            freshness: chrome.freshness,
            actions: chrome.actions
        ) {
            refreshFailure(chrome.issue)

            WisentSignalStrip(signals: [
                WisentSignal("Status", value: state.status.capitalized, tone: beingStatusTone(state.status)),
                WisentSignal("Cycle", value: state.cycle.formatted(), tone: .brand),
                WisentSignal("Model", value: state.mind.currentModel, tone: .neutral),
                WisentSignal("Host", value: state.identity.host, tone: .neutral),
            ])

            WisentCounterRow(counters: [
                .init("Balance", value: money(state.budget.remaining.value), detail: "available for continued operation", tone: state.budget.remaining.value > 0 ? .success : .warning),
                .init("Earned", value: money(state.budget.earned.value), detail: "trusted credited revenue", tone: .brand),
                .init("Net", value: money(state.budget.netProfit), detail: "earned minus model and instance costs", tone: state.budget.netProfit >= 0 ? .success : .warning),
            ])

            WisentSectionBox(
                title: "Identity",
                trailing: state.identity.ticker
            ) {
                WisentPanel {
                    fieldGrid([
                        ("Agent ID", state.identity.agentID),
                        ("Type", state.identity.agentType),
                        ("Specialty", state.identity.specialty),
                        ("Role", state.identity.role),
                        ("Environment", state.identity.environment),
                        ("Workload", state.identity.workloadID),
                        ("Started", timestamp(state.startedAt)),
                        ("Updated", timestamp(state.updatedAt)),
                    ])
                }
            }

            WisentSectionBox(
                title: "Latest activity",
                trailing: activity.isEmpty ? "recent actions" : "\(min(activity.count, 8)) of \(activity.count)"
            ) {
                if activity.isEmpty && state.recentActions.isEmpty {
                    WisentEmptyPanel(
                        title: "No activity recorded yet",
                        detail: "No activity or recent actions yet.",
                        symbol: "waveform.path.ecg"
                    )
                } else {
                    WisentPanel(padding: 0) {
                        VStack(spacing: 0) {
                            if !activity.isEmpty {
                                ForEach(activity.prefix(8)) { item in
                                    BeingDenseRow(
                                        title: humanized(item.type),
                                        detail: item.summary.isEmpty ? "No additional fields" : item.summary,
                                        meta: item.timestamp.map(timestamp)
                                    )
                                    if item.id != activity.prefix(8).last?.id { Divider() }
                                }
                            } else {
                                ForEach(state.recentActions.prefix(8)) { action in
                                    BeingDenseRow(
                                        title: action.tool,
                                        detail: "cycle \(action.cycle.formatted()) · \(action.status)",
                                        meta: timestamp(action.at),
                                        tone: beingStatusTone(action.status)
                                    )
                                    if action.id != state.recentActions.prefix(8).last?.id { Divider() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct BeingMindScreen: View {
    let state: BeingState
    let chrome: BeingScreenChrome

    var body: some View {
        WisentScreen(
            title: BeingDestination.mind.title,
            scope: chrome.scope,
            freshness: chrome.freshness,
            actions: chrome.actions
        ) {
            refreshFailure(chrome.issue)

            WisentSignalStrip(signals: [
                WisentSignal("Rules", value: state.mind.rules.count.formatted(), tone: .brand),
                WisentSignal("Learnings", value: state.mind.learnings.count.formatted(), tone: .brand),
                WisentSignal("Memories", value: state.mind.memories.count.formatted(), tone: .neutral),
                WisentSignal("Model", value: state.mind.currentModel, tone: .neutral),
            ])

            WisentSectionBox(
                title: "Prompt"
            ) {
                WisentPanel {
                    Text(state.mind.systemPrompt)
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TextListSection(
                title: "Self-imposed rules",
                items: state.mind.rules,
                emptyTitle: "No self-imposed rules",
                emptyDetail: "No rules yet.",
                symbol: "checklist"
            )

            TextListSection(
                title: "Learnings",
                items: state.mind.learnings,
                emptyTitle: "No learnings recorded",
                emptyDetail: "No learnings yet.",
                symbol: "lightbulb"
            )

            WisentSectionBox(
                title: "Memories",
                trailing: state.mind.memories.count.formatted()
            ) {
                if state.mind.memories.isEmpty {
                    WisentEmptyPanel(
                        title: "No memories recorded",
                        detail: "No memories yet.",
                        symbol: "memorychip"
                    )
                } else {
                    WisentPanel(padding: 0) {
                        LazyVStack(spacing: 0) {
                            ForEach(state.mind.memories.reversed()) { memory in
                                BeingDenseRow(
                                    title: humanized(memory.kind),
                                    detail: memory.text,
                                    meta: timestamp(memory.createdAt)
                                )
                                if memory.id != state.mind.memories.first?.id { Divider() }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct BeingEconomyScreen: View {
    let state: BeingState
    let chrome: BeingScreenChrome

    var body: some View {
        WisentScreen(
            title: BeingDestination.economy.title,
            scope: chrome.scope,
            freshness: chrome.freshness,
            actions: chrome.actions
        ) {
            refreshFailure(chrome.issue)

            WisentCounterRow(counters: [
                .init("Balance", value: money(state.budget.remaining.value), detail: "remaining from \(money(state.budget.starting.value))", tone: state.budget.remaining.value > 0 ? .success : .warning),
                .init("Earned", value: money(state.budget.earned.value), detail: "credited trusted revenue", tone: .brand),
                .init("Net", value: money(state.budget.netProfit), detail: "revenue minus recorded costs", tone: state.budget.netProfit >= 0 ? .success : .warning),
            ])

            WisentSignalStrip(signals: [
                WisentSignal("Model cost", value: money(state.budget.apiSpent.value), tone: .neutral),
                WisentSignal("Instance cost", value: money(state.budget.instanceSpent.value), tone: .neutral),
                WisentSignal("Tokens", value: state.budget.totalTokens.formatted(), tone: .neutral),
                WisentSignal("Runtime", value: state.status.capitalized, tone: beingStatusTone(state.status)),
            ])

            WisentSectionBox(
                title: "Accounting",
                trailing: "cycle \(state.cycle.formatted())"
            ) {
                WisentPanel {
                    fieldGrid([
                        ("Starting balance", money(state.budget.starting.value)),
                        ("Remaining balance", money(state.budget.remaining.value)),
                        ("Model spend", money(state.budget.apiSpent.value)),
                        ("Instance spend", money(state.budget.instanceSpent.value)),
                        ("Total earned", money(state.budget.earned.value)),
                        ("Net profit", money(state.budget.netProfit)),
                        ("Total tokens", state.budget.totalTokens.formatted()),
                        ("Last accounted", timestamp(state.updatedAt)),
                    ])
                }
            }
        }
    }
}

struct BeingChildrenScreen: View {
    let state: BeingState
    let chrome: BeingScreenChrome

    var body: some View {
        WisentScreen(
            title: BeingDestination.children.title,
            scope: chrome.scope,
            freshness: chrome.freshness,
            actions: chrome.actions
        ) {
            refreshFailure(chrome.issue)

            WisentSignalStrip(signals: [
                WisentSignal("Children", value: state.mind.children.count.formatted(), tone: state.mind.children.isEmpty ? .neutral : .brand),
                WisentSignal("Parent", value: state.identity.name, tone: .neutral),
            ])

            WisentSectionBox(
                title: "Child beings",
                trailing: state.mind.children.count.formatted()
            ) {
                if state.mind.children.isEmpty {
                    WisentEmptyPanel(
                        title: "No child beings",
                        detail: "This being has not created a child.",
                        symbol: "person.2"
                    )
                } else {
                    VStack(spacing: WisentDesign.Space.x3) {
                        ForEach(state.mind.children) { child in
                            WisentPanel {
                                HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(beingStatusTone(child.status).color)
                                        .frame(width: 40, height: 40)
                                        .background(
                                            beingStatusTone(child.status).softColor,
                                            in: RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                                        )
                                    VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(child.name)
                                                .font(WisentTypeScale.section())
                                                .foregroundStyle(WisentDesign.ink)
                                            WisentStatusChip(text: child.ticker, tone: .brand)
                                            Spacer(minLength: 0)
                                            WisentStatusChip(text: child.status.capitalized, tone: beingStatusTone(child.status))
                                        }
                                        fieldGrid([
                                            ("Created", timestamp(child.createdAt)),
                                        ])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct BeingActivityScreen: View {
    let state: BeingState
    let activity: [ActivityLine]
    let chrome: BeingScreenChrome

    private var shownActivity: ArraySlice<ActivityLine> { activity.prefix(250) }

    var body: some View {
        WisentScreen(
            title: BeingDestination.activity.title,
            scope: chrome.scope,
            freshness: chrome.freshness,
            actions: chrome.actions
        ) {
            refreshFailure(chrome.issue)

            WisentSignalStrip(signals: [
                WisentSignal("Events", value: activity.count.formatted(), tone: .brand),
                WisentSignal("Recent actions", value: state.recentActions.count.formatted(), tone: .neutral),
                WisentSignal("Latest event", value: activity.first.map { humanized($0.type) } ?? "None", tone: .neutral),
                WisentSignal("Cycle", value: state.cycle.formatted(), tone: .neutral),
            ])

            WisentSectionBox(
                title: "Activity",
                trailing: activity.count > shownActivity.count ? "\(shownActivity.count) of \(activity.count)" : activity.count.formatted()
            ) {
                if activity.isEmpty {
                    WisentEmptyPanel(
                        title: "No activity",
                        detail: "No activity yet.",
                        symbol: "waveform.path.ecg"
                    )
                } else {
                    WisentPanel(padding: 0) {
                        LazyVStack(spacing: 0) {
                            ForEach(shownActivity) { item in
                                BeingDenseRow(
                                    title: humanized(item.type),
                                    detail: item.summary.isEmpty ? "No additional fields" : item.summary,
                                    meta: item.timestamp.map(timestamp)
                                )
                                if item.id != shownActivity.last?.id { Divider() }
                            }
                        }
                    }
                }
            }

            if !state.recentActions.isEmpty {
                WisentSectionBox(
                    title: "Recent actions",
                    trailing: state.recentActions.count.formatted()
                ) {
                    WisentPanel(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(state.recentActions) { action in
                                BeingDenseRow(
                                    title: action.tool,
                                    detail: "cycle \(action.cycle.formatted()) · \(action.status)",
                                    meta: timestamp(action.at),
                                    tone: beingStatusTone(action.status)
                                )
                                if action.id != state.recentActions.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TextListSection: View {
    let title: String
    let items: [String]
    let emptyTitle: String
    let emptyDetail: String
    let symbol: String

    var body: some View {
        WisentSectionBox(title: title, trailing: items.count.formatted()) {
            if items.isEmpty {
                WisentEmptyPanel(title: emptyTitle, detail: emptyDetail, symbol: symbol)
            } else {
                WisentPanel(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(items.indices, id: \.self) { index in
                            HStack(alignment: .top, spacing: WisentDesign.Space.x3) {
                                Text("\(index + 1)")
                                    .font(WisentTypeScale.identifierSmall())
                                    .foregroundStyle(WisentDesign.muted)
                                    .frame(width: 24, alignment: .trailing)
                                Text(items[index])
                                    .font(WisentTypeScale.body())
                                    .foregroundStyle(WisentDesign.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, WisentDesign.Space.x4)
                            .padding(.vertical, WisentDesign.Space.x3)
                            if index != items.indices.last { Divider() }
                        }
                    }
                }
            }
        }
    }
}

private struct BeingDenseRow: View {
    let title: String
    let detail: String
    let meta: String?
    var tone: WisentTone = .neutral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WisentDesign.Space.x3) {
            Circle()
                .fill(tone == .neutral ? WisentDesign.muted : tone.color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(WisentTypeScale.bodyStrong())
                .foregroundStyle(WisentDesign.ink)
                .frame(minWidth: 116, alignment: .leading)
            Text(detail)
                .font(WisentTypeScale.identifierSmall())
                .foregroundStyle(WisentDesign.secondary)
                .lineLimit(2)
            Spacer(minLength: WisentDesign.Space.x3)
            if let meta {
                Text(meta)
                    .font(WisentTypeScale.identifierSmall())
                    .foregroundStyle(WisentDesign.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, WisentDesign.Space.x4)
        .padding(.vertical, WisentDesign.Space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
@ViewBuilder
private func refreshFailure(_ issue: String?) -> some View {
    if issue != nil {
        WisentErrorBanner(
            title: "The latest refresh failed",
            detail: "Previously loaded information remains visible."
        )
    }
}

@MainActor
@ViewBuilder
private func fieldGrid(_ fields: [(String, String)]) -> some View {
    LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 210), spacing: WisentDesign.Space.x5)],
        alignment: .leading,
        spacing: WisentDesign.Space.x4
    ) {
        ForEach(fields, id: \.0) { field in
            WisentField(label: field.0, value: field.1)
        }
    }
}

func beingStatusTone(_ status: String) -> WisentTone {
    switch status.lowercased() {
    case "active", "alive", "running", "ready", "succeeded", "success", "completed": .success
    case "stopped", "paused", "depleted", "uncertain", "indeterminate": .warning
    case "failed", "error", "dead", "insolvent": .danger
    default: .neutral
    }
}

private func money(_ value: Decimal) -> String {
    "$" + NSDecimalNumber(decimal: value).stringValue
}

private func timestamp(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}

private func humanized(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
}
