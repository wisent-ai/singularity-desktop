import Foundation

enum BeingDestination: String, CaseIterable, Identifiable {
    case life
    case mind
    case economy
    case children
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .life: "Life"
        case .mind: "Mind"
        case .economy: "Economy"
        case .children: "Children"
        case .activity: "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .life: "sparkles"
        case .mind: "brain.head.profile"
        case .economy: "chart.line.uptrend.xyaxis"
        case .children: "person.2"
        case .activity: "waveform.path.ecg"
        }
    }

    var rationale: String {
        switch self {
        case .life: "View the being's status and host."
        case .mind: "View the prompt, rules, learnings, and memories."
        case .economy: "View balances, costs, and token use."
        case .children: "View child beings."
        case .activity: "View recent activity and actions."
        }
    }
}

enum BeingDestinationGroup: String, CaseIterable, Identifiable {
    case existence = "Existence"
    case continuity = "Continuity"
    case history = "History"

    var id: String { rawValue }

    var destinations: [BeingDestination] {
        switch self {
        case .existence: [.life, .economy]
        case .continuity: [.mind, .children]
        case .history: [.activity]
        }
    }
}
