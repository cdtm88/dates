import Foundation
import Contacts
import DatesKit

/// Reads annual dates out of the user's contacts.
///
/// Contacts is where these dates actually live: a birthday field with an optional year, and
/// labelled dates of which "anniversary" is the one this app understands. Everything else on
/// a contact card is neither read nor stored — only the display name and those two dates.
enum ContactsImporter {

    enum ImportError: LocalizedError {
        case accessDenied

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Dates can't see your contacts. Allow contacts access in the Settings app to import."
            }
        }
    }

    /// Requests read access if needed, then returns one candidate per birthday and per
    /// anniversary-labelled date, soonest first. Years are kept when the contact card has
    /// them — a contact's birthday year is the birth year, so ages computed from it are real.
    static func fetchCandidates(now: Date = Date()) async throws -> [ImportCandidate] {
        let contactStore = CNContactStore()
        guard try await contactStore.requestAccess(for: .contacts) else {
            throw ImportError.accessDenied
        }

        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactDatesKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true

        var collected: [ImportCandidate] = []
        var seen = Set<String>()
        try contactStore.enumerateContacts(with: request) { contact, _ in
            for candidate in candidates(for: contact) where seen.insert(candidate.duplicateKey).inserted {
                collected.append(candidate)
            }
        }

        return collected.sorted {
            ($0.date.daysUntilNextOccurrence(from: now) ?? .max)
                < ($1.date.daysUntilNextOccurrence(from: now) ?? .max)
        }
    }

    private static func candidates(for contact: CNContact) -> [ImportCandidate] {
        guard let name = displayName(for: contact) else { return [] }

        var results: [ImportCandidate] = []
        if let birthday = contact.birthday, let date = annualDate(from: birthday) {
            results.append(ImportCandidate(name: name, type: .birthday, date: date))
        }
        for labelled in contact.dates where labelled.label == CNLabelDateAnniversary {
            guard let date = annualDate(from: labelled.value as DateComponents) else { continue }
            results.append(ImportCandidate(name: name, type: .anniversary, date: date))
        }
        return results
    }

    private static func displayName(for contact: CNContact) -> String? {
        guard let formatted = CNContactFormatter.string(from: contact, style: .fullName) else { return nil }
        let name = EventValidation.normalisedName(formatted)
        return EventValidation.isValidName(name) ? name : nil
    }

    /// Contacts store a placeholder year (1604) when the user set a birthday without one;
    /// treating it as real would show a four-century age.
    private static func annualDate(from components: DateComponents) -> AnnualDate? {
        guard let month = components.month, let day = components.day else { return nil }
        let year = components.year.flatMap { $0 > 1900 ? $0 : nil }
        return AnnualDate(month: month, day: day, year: year)
            ?? AnnualDate(month: month, day: day)
    }
}
