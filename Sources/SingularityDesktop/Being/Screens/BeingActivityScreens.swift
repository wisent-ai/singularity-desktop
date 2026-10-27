/// The two screens about what a being holds and what it has been doing: its
/// children, and the activity it recorded.
///
/// Held apart from Life, Mind and Economy so that the window a person opens
/// first is not the file every later screen is read through.

import SwiftUI
import WisentDesignSystem

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
                WisentSignal(
                    "Children", value: state.mind.children.count.formatted(),
                    tone: state.mind.children.isEmpty ? .neutral : .brand),
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
                                        .font(.system(size: WisentDesign.Space.x5, weight: .medium))
                                        .foregroundStyle(beingStatusTone(child.status).color)
                                        .frame(width: WisentDesign.Space.x10, height: WisentDesign.Space.x10)
                                        .background(
                                            beingStatusTone(child.status).softColor,
                                            in: RoundedRectangle(
                                                cornerRadius: WisentDesign.Radius.small)
                                        )
                                    VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(child.name)
                                                .font(WisentTypeScale.section())
                                                .foregroundStyle(WisentDesign.ink)
                                            WisentStatusChip(text: child.ticker, tone: .brand)
                                            Spacer(minLength: .zero)
                                            WisentStatusChip(
                                                text: child.status.capitalized,
                                                tone: beingStatusTone(child.status))
                                        }
                                        fieldGrid([
                                            ("Created", timestamp(child.createdAt))
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
                WisentSignal(
                    "Recent actions", value: state.recentActions.count.formatted(), tone: .neutral),
                WisentSignal("Latest event", value: latestEvent, tone: .neutral),
                WisentSignal("Cycle", value: state.cycle.formatted(), tone: .neutral),
            ])

            WisentSectionBox(
                title: "Activity",
                trailing: activity.count.formatted()
            ) {
                if activity.isEmpty {
                    WisentEmptyPanel(
                        title: "No activity",
                        detail: "No activity yet.",
                        symbol: "waveform.path.ecg"
                    )
                } else {
                    WisentPanel(padding: .zero) {
                        LazyVStack(spacing: .zero) {
                            ForEach(activity) { item in
                                BeingDenseRow(
                                    title: humanized(item.type),
                                    detail: item.summary.isEmpty
                                        ? "No additional fields" : item.summary,
                                    meta: item.timestamp.map(timestamp)
                                )
                                if item.id != activity.last?.id { Divider() }
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
                    WisentPanel(padding: .zero) {
                        VStack(spacing: .zero) {
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

    /// The newest event's type, or that the being has recorded none yet.
    private var latestEvent: String {
        switch activity.first {
        case .some(let latest): humanized(latest.type)
        case .none: "No event recorded yet"
        }
    }
}

/// SwiftUI's line limit for a label kept to one line
/// (https://developer.apple.com/documentation/swiftui/view/linelimit(_:)).
private let singleLine = 1

struct TextListSection: View {
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
                WisentPanel(padding: .zero) {
                    VStack(spacing: .zero) {
                        ForEach(items.indices, id: \.self) { index in
                            HStack(alignment: .top, spacing: WisentDesign.Space.x3) {
                                // The item's place in the list as a reader counts it.
                                Text("\(items[...index].count)")
                                    .font(WisentTypeScale.identifierSmall())
                                    .foregroundStyle(WisentDesign.muted)
                                    .frame(width: WisentDesign.Space.x6, alignment: .trailing)
                                Text(items[index])
                                    .font(WisentTypeScale.body())
                                    .foregroundStyle(WisentDesign.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: .zero)
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

struct BeingDenseRow: View {
    let title: String
    let detail: String
    let meta: String?
    var tone: WisentTone = .neutral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WisentDesign.Space.x3) {
            Circle()
                .fill(tone == .neutral ? WisentDesign.muted : tone.color)
                .frame(width: WisentDesign.Space.x2, height: WisentDesign.Space.x2)
            Text(title)
                .font(WisentTypeScale.bodyStrong())
                .foregroundStyle(WisentDesign.ink)
                .frame(
                    minWidth: WisentDesign.Space.x10 + WisentDesign.Space.x10
                        + WisentDesign.Space.x8 + WisentDesign.Space.x1,
                    alignment: .leading)
            Text(detail)
                .font(WisentTypeScale.identifierSmall())
                .foregroundStyle(WisentDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: WisentDesign.Space.x3)
            if let meta {
                Text(meta)
                    .font(WisentTypeScale.identifierSmall())
                    .foregroundStyle(WisentDesign.muted)
                    .lineLimit(singleLine)
            }
        }
        .padding(.horizontal, WisentDesign.Space.x4)
        .padding(.vertical, WisentDesign.Space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
@ViewBuilder
func refreshFailure(_ issue: String?) -> some View {
    if issue != nil {
        WisentErrorBanner(
            title: "The latest refresh failed",
            detail: "Previously loaded information remains visible."
        )
    }
}

@MainActor
@ViewBuilder
func fieldGrid(_ fields: [(label: String, value: String)]) -> some View {
    LazyVGrid(
        columns: [
            GridItem(
                .adaptive(
                    minimum: WisentDesign.Space.x10 + WisentDesign.Space.x10
                        + WisentDesign.Space.x10 + WisentDesign.Space.x10
                        + WisentDesign.Space.x8 + WisentDesign.Space.x4),
                spacing: WisentDesign.Space.x5)
        ],
        alignment: .leading,
        spacing: WisentDesign.Space.x4
    ) {
        ForEach(fields, id: \.label) { field in
            WisentField(label: field.label, value: field.value)
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

func money(_ value: Decimal) -> String {
    "$" + NSDecimalNumber(decimal: value).stringValue
}

func timestamp(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}

func humanized(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
}
