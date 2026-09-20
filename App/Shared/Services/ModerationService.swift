import Foundation
import FirebaseFirestore
import FirebaseAuth

final class ModerationService {
    static let shared = ModerationService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Report Content/User
    func report(reportedUserID: String, reportedContentID: String? = nil, reason: String) async throws {
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ModerationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        let reportData: [String: Any] = [
            "reporterID": currentUserID,
            "reportedUserID": reportedUserID,
            "reportedContentID": reportedContentID ?? "",
            "reason": reason,
            "timestamp": FieldValue.serverTimestamp(),
            "status": "pending"
        ]
        
        try await db.collection("reports").addDocument(data: reportData)
    }
    
    // MARK: - Block User
    func blockUser(blockedUserID: String) async throws {
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ModerationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        // Add to blocker's blockedUsers collection
        let blockerRef = db.collection("users").document(currentUserID).collection("blockedUsers").document(blockedUserID)
        try await blockerRef.setData([
            "timestamp": FieldValue.serverTimestamp(),
            "blockedUserID": blockedUserID
        ])
        
        // For bidirectional blocking or queries, you might also want to store in a central 'blocks' collection
        let blockRef = db.collection("blocks").document("\(currentUserID)_\(blockedUserID)")
        try await blockRef.setData([
            "blockerID": currentUserID,
            "blockedID": blockedUserID,
            "timestamp": FieldValue.serverTimestamp()
        ])
    }
}
