import Foundation

enum BeingDestination: String, CaseIterable, Identifiable {
    case life
    case mind
    case economy
    case children
    case activity
    case ecosystem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .life: "Life"
        case .mind: "Mind"
        case .economy: "Economy"
        case .children: "Children"
        case .activity: "Activity"
        case .ecosystem: "Ecosystem"
        }
    }

    var symbol: String {
        switch self {
        case .life: "sparkles"
        case .mind: "brain.head.profile"
        case .economy: "chart.line.uptrend.xyaxis"
        case .children: "person.2"
        case .activity: "waveform.path.ecg"
        case .ecosystem: "square.stack.3d.up"
        }
    }

    var rationale: String {
        switch self {
        case .life: "View the being's status and host."
        case .mind: "View the prompt, rules, learnings, and memories."
        case .economy: "View balances, costs, and token use."
        case .children: "View child beings."
        case .activity: "View recent activity and actions."
        case .ecosystem: "Review opportunities, delivery evidence, outcomes, and delegated spending."
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
        case .existence: [.ecosystem, .life, .economy]
        case .continuity: [.mind, .children]
        case .history: [.activity]
        }
    }
}
