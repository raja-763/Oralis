import Foundation

enum AgentRole: String, Codable {
    case user, assistant
}

struct AgentMessage: Identifiable, Codable {
    let id: UUID
    var role: AgentRole
    var content: String
    var date: Date
    var actionResult: AgentActionResult?

    init(id: UUID = UUID(), role: AgentRole, content: String,
         date: Date = Date(), actionResult: AgentActionResult? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.date = date
        self.actionResult = actionResult
    }
}

/// Structured result when the agent performs an email action.
struct AgentActionResult: Codable {
    enum ActionType: String, Codable {
        case deleted, archived, replied, forwarded,
             markedRead, markedUnread, starred,
             unsubscribed, calendarAccepted, calendarDeclined,
             openedLink, filledForm
    }
    var type: ActionType
    var affectedCount: Int
    var summary: String
}
