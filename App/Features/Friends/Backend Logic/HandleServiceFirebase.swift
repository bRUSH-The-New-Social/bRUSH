import Foundation
import FirebaseFirestore
import FirebaseCore

struct HandleHit {
    let uid: String
    let handle: String
    let fullName: String
}

final class HandleServiceFirebase {
    private let db = Firestore.firestore()
    
    // Prefix search by @handle (case insensitive). Min length guard (>= 2) recommended in caller.
    //
    // NOTE: This does a client-side, case-insensitive scan of the users collection.
    // Firestore range queries are case-SENSITIVE, which is why the previous indexed
    // approach missed any username with interior capitals (e.g. "bRUSH", "JohnDoe") —
    // even when pasted exactly. Scanning in memory is fully reliable and needs no
    // pre-populated index field. For a large user base, migrate to the indexed
    // `displayNameLower` query (all docs write that field now; run the backfill first).
    func searchHandles(prefix raw: String, limit: Int = 20) async throws -> [HandleHit] {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }

        let query = raw.replacingOccurrences(of: "@", with: "").lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        // Fetch a bounded page of users and filter in memory. The cap keeps this cheap
        // while the user base is small.
        let snap = try await db.collection("users").limit(to: 500).getDocuments()

        var seen = Set<String>()
        var hits: [HandleHit] = []

        for doc in snap.documents {
            let uid = doc.documentID
            guard !seen.contains(uid) else { continue }

            let data = doc.data()
            let dn = (data["displayName"] as? String) ?? ""
            let fn = (data["firstName"] as? String) ?? ""
            let ln = (data["lastName"] as? String) ?? ""
            let fullName = [fn, ln].filter { !$0.isEmpty }.joined(separator: " ")

            // Match by username prefix, or by name substring, all case-insensitive.
            let handleLower = dn.lowercased()
            let nameLower = fullName.lowercased()
            let matches = handleLower.hasPrefix(query)
                || nameLower.contains(query)
            guard matches else { continue }

            hits.append(HandleHit(uid: uid, handle: dn, fullName: fullName.isEmpty ? dn : fullName))
            seen.insert(uid)

            if hits.count >= limit { break }
        }

        // Prefer exact/prefix handle matches at the top of the list.
        hits.sort { a, b in
            let aPrefix = a.handle.lowercased().hasPrefix(query)
            let bPrefix = b.handle.lowercased().hasPrefix(query)
            if aPrefix != bPrefix { return aPrefix }
            return a.handle.localizedCaseInsensitiveCompare(b.handle) == .orderedAscending
        }

        print("[HandleServiceFirebase] query='\(query)' -> \(hits.count) hit(s)")
        return hits
    }
}
