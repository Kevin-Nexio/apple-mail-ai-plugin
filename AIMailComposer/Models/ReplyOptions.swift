import Foundation

enum ReplyAddressStyle: String, CaseIterable, Identifiable {
    case automatic
    case informal
    case formal

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .automatic: return "Auto"
        case .informal: return "Tu"
        case .formal: return "Vous"
        }
    }

    var menuLabel: String {
        switch self {
        case .automatic: return "Automatic"
        case .informal: return "Informal (tu)"
        case .formal: return "Formal (vous)"
        }
    }

    var promptInstruction: String {
        switch self {
        case .automatic:
            return "Infer the formality from the latest incoming message. If it is unclear, prefer a polite professional register."
        case .informal:
            return "Use the informal second person throughout: tu in French or Italian, du in German, and an informal tone in English. Never switch to the formal form."
        case .formal:
            return "Use the formal, polite second person throughout: vous in French, Sie in German, Lei in Italian, and a polite professional tone in English. Never switch to the informal form."
        }
    }
}

enum ReplyLanguage: String, CaseIterable, Identifiable {
    case automatic
    case french
    case english
    case german
    case italian

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .automatic: return "Auto"
        case .french: return "FR"
        case .english: return "EN"
        case .german: return "DE"
        case .italian: return "IT"
        }
    }

    var menuLabel: String {
        switch self {
        case .automatic: return "Automatic"
        case .french: return "Français"
        case .english: return "English"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        }
    }

    var promptInstruction: String {
        switch self {
        case .automatic:
            return "Write in the language of the latest incoming message. If there is no incoming message, use the language of the user's thoughts."
        case .french:
            return "Write the entire reply in French, regardless of the language used in the thread, draft, or user thoughts."
        case .english:
            return "Write the entire reply in English, regardless of the language used in the thread, draft, or user thoughts."
        case .german:
            return "Write the entire reply in German, regardless of the language used in the thread, draft, or user thoughts."
        case .italian:
            return "Write the entire reply in Italian, regardless of the language used in the thread, draft, or user thoughts."
        }
    }
}
