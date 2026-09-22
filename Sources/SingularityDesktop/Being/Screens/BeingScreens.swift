import SwiftUI
import WisentDesignSystem

struct BeingScreenChrome {
    let scope: String?
    let freshness: String?
    let actions: [WisentAction]
    let importOutcome: WisentMutationOutcome
    let dismissImportOutcome: () -> Void
    let issue: String?
}

struct BeingLifeScreen: View {
    let state: BeingState
    let activity: [ActivityLine]
    let chrome: BeingScreenChrome
    @ObservedObject var onboarding: BeingOnboardingController
    /// The life screen shows this many recent rows; the activity screen shows the rest.
    static let recentRowLimit = 8

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
                                ForEach(activity.prefix(Self.recentRowLimit)) { item in
                                    BeingDenseRow(
                                        title: humanized(item.type),
                                        detail: item.summary.isEmpty ? "No additional fields" : item.summary,
                                        meta: item.timestamp.map(timestamp)
                                    )
                                    if item.id != activity.prefix(Self.recentRowLimit).last?.id { Divider() }
                                }
                            } else {
                                ForEach(state.recentActions.prefix(Self.recentRowLimit)) { action in
                                    BeingDenseRow(
                                        title: action.tool,
                                        detail: "cycle \(action.cycle.formatted()) · \(action.status)",
                                        meta: timestamp(action.at),
                                        tone: beingStatusTone(action.status)
                                    )
                                    if action.id != state.recentActions.prefix(Self.recentRowLimit).last?.id { Divider() }
                                }
                            }
                        }
                    }
                }
            }

            // Last on Life, the destination the window opens on: the one
            // control that puts the first-run walkthrough back.
            BeingWalkthroughSection(onboarding: onboarding)
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
            if chrome.importOutcome != .idle {
                WisentMutationBar(outcome: chrome.importOutcome) {
                    chrome.dismissImportOutcome()
                }
            }

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
                                    meta: memory.sources?.last.map {
                                        "\($0.kind):\($0.sourceId) · \(timestamp(memory.createdAt))"
                                    } ?? timestamp(memory.createdAt)
                                )
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

