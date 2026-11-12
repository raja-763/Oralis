import Contacts

/// Finds a contact's email address by name, so the user can say "email Sarah".
enum ContactLookup {

    enum Failure: LocalizedError {
        case contactsDenied
        case noMatch(String)
        case noEmail(String)

        var errorDescription: String? {
            switch self {
            case .contactsDenied:
                return "Oralis is not allowed to read your contacts. Enable it in System Settings, Privacy and Security, Contacts, or tell me the email address."
            case .noMatch(let name):
                return "I could not find \(name) in your contacts. Tell me the email address instead."
            case .noEmail(let name):
                return "\(name) has no email address in your contacts."
            }
        }
    }

    static func email(for name: String) async throws -> (name: String, address: String) {
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else {
            throw Failure.contactsDenied
        }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
                    CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let matches = try store.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
        guard let contact = matches.first(where: { !$0.emailAddresses.isEmpty }) ?? matches.first else {
            throw Failure.noMatch(name)
        }
        let fullName = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }.joined(separator: " ")
        let spoken = fullName.isEmpty ? name : fullName
        guard let address = contact.emailAddresses.first?.value as String? else {
            throw Failure.noEmail(spoken)
        }
        return (spoken, address)
    }
}
