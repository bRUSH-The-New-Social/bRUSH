import Foundation
import FirebaseFirestore
import Combine

public struct UserProfile: Codable, Equatable, Hashable {
    let uid: String
    var firstName: String
    let lastName: String
    var displayName: String
    let email: String
    var avatarType: String // "fun" or "personal"
    var avatarBackground: String?
    var avatarBody: String?
    var avatarFace: String?
    var avatarShirt: String?
    var avatarEyes: String?
    var avatarMouth: String?
    var avatarHair: String?
    var avatarFacialHair: String?
    
    // Medal and statistics fields
    var goldMedalsAccumulated: Int
    var silverMedalsAccumulated: Int
    var bronzeMedalsAccumulated: Int
    var goldMedalsAwarded: Int
    var silverMedalsAwarded: Int
    var bronzeMedalsAwarded: Int
    var totalDrawingCount: Int
    var streakCount: Int
    var memberSince: Date
    var lastCompletedDate: Date?
    var lastAttemptedDate: Date?
}

final class UserService {
    static let shared = UserService()
    private let db = Firestore.firestore()
    private let usersCollection = "users"

    private init() {}
    
    // -------------------------------------------------------
    // UPDATE LAST ATTEMPTED DATE
    // -------------------------------------------------------
    func updateLastAttemptedDate(uid: String) async throws {
        try await db.collection(usersCollection).document(uid).updateData([
            "lastAttemptedDate": FieldValue.serverTimestamp()
        ])
    }
    
    // -------------------------------------------------------
    // UPDATE STREAK + DRAW COUNT
    // -------------------------------------------------------
    func updateStreakAndTotalDrawingCount(uid: String) async throws -> Int {
        let userRef = db.collection(usersCollection).document(uid)
        let today = Calendar.current.startOfDay(for: Date())
        
        var newStreakCount = 1
        var lastCompletedDate: Date? = nil
        
        let doc = try await userRef.getDocument()
        guard let data = doc.data() else {
            throw AuthError.backend("Profile not found.")
        }
        
        let currentStreak = data["streakCount"] as? Int ?? 0
        let currentTotalDrawings = data["totalDrawingCount"] as? Int ?? 0
        let lastDateTimestamp = data["lastCompletedDate"] as? Timestamp
        let currentLastCompletedDate = lastDateTimestamp?.dateValue()
        
        if let lastCompleted = currentLastCompletedDate, lastCompleted < today {
            if Calendar.current.isDateInYesterday(lastCompleted) {
                newStreakCount = currentStreak + 1
            } else if !Calendar.current.isDateInToday(lastCompleted) {
                newStreakCount = 1
            } else {
                newStreakCount = currentStreak
            }
        } else if currentLastCompletedDate == nil {
            newStreakCount = 1
        } else {
            newStreakCount = currentStreak
        }
        
        if currentLastCompletedDate == nil || currentLastCompletedDate! < today {
            lastCompletedDate = Date()
        } else {
            lastCompletedDate = currentLastCompletedDate
        }
        
        var updateData: [String: Any] = [
            "streakCount": newStreakCount,
            "totalDrawingCount": currentTotalDrawings + 1
        ]
        
        if lastCompletedDate != currentLastCompletedDate {
            updateData["lastCompletedDate"] = lastCompletedDate
        }
        
        try await userRef.updateData(updateData)
        return newStreakCount
    }
    
    // -------------------------------------------------------
    // CREATE PROFILE
    // -------------------------------------------------------
    func createProfile(userProfile: UserProfile) async throws {
        let uid = userProfile.uid
        let userRef = db.collection(usersCollection).document(uid)
        
        var profileData: [String: Any] = [
            "uid": uid,
            "firstName": userProfile.firstName,
            "lastName": userProfile.lastName,
            "displayName": userProfile.displayName,
            "displayNameLower": userProfile.displayName.lowercased(),
            "email": userProfile.email.lowercased(),
            "avatarType": userProfile.avatarType,
            "createdAt": FieldValue.serverTimestamp(),
            
            "goldMedalsAccumulated": userProfile.goldMedalsAccumulated,
            "silverMedalsAccumulated": userProfile.silverMedalsAccumulated,
            "bronzeMedalsAccumulated": userProfile.bronzeMedalsAccumulated,
            "goldMedalsAwarded": userProfile.goldMedalsAwarded,
            "silverMedalsAwarded": userProfile.silverMedalsAwarded,
            "bronzeMedalsAwarded": userProfile.bronzeMedalsAwarded,
            "totalDrawingCount": userProfile.totalDrawingCount,
            "streakCount": userProfile.streakCount,
            "memberSince": userProfile.memberSince
        ]
        
        // Add avatar fields if they exist
        if let background = userProfile.avatarBackground { profileData["avatarBackground"] = background }
        if let body = userProfile.avatarBody { profileData["avatarBody"] = body }
        if let face = userProfile.avatarFace { profileData["avatarFace"] = face }
        if let shirt = userProfile.avatarShirt { profileData["avatarShirt"] = shirt }
        if let eyes = userProfile.avatarEyes { profileData["avatarEyes"] = eyes }
        if let mouth = userProfile.avatarMouth { profileData["avatarMouth"] = mouth }
        if let hair = userProfile.avatarHair { profileData["avatarHair"] = hair }
        if let facialHair = userProfile.avatarFacialHair { profileData["avatarFacialHair"] = facialHair }
        
        try await userRef.setData(profileData)
    }
    
    // -------------------------------------------------------
    // DELETE PROFILE
    // -------------------------------------------------------
    func deleteProfile(uid: String) async throws {
        let friendshipsRef = db.collection("friendships")
        let myFriendsCollection = friendshipsRef.document(uid).collection("friends")
        
        let friendSnapshot = try? await myFriendsCollection.getDocuments()
        let batch1 = db.batch()
        
        if let docs = friendSnapshot?.documents {
            for doc in docs {
                let friendUid = doc.documentID
                let friendRef = friendshipsRef.document(friendUid).collection("friends").document(uid)
                batch1.deleteDocument(friendRef)
                batch1.deleteDocument(doc.reference)
            }
        }
        try? await batch1.commit()
        
        let incomingRef = db.collection("friendRequests").document(uid).collection("incoming")
        let incomingSnapshot = try? await incomingRef.getDocuments()
        
        let batch2 = db.batch()
        if let docs = incomingSnapshot?.documents {
            for doc in docs {
                batch2.deleteDocument(doc.reference)
            }
        }
        try? await batch2.commit()
        
        let outgoingSnapshot = try? await db.collectionGroup("incoming")
            .whereField("fromUid", isEqualTo: uid)
            .getDocuments()
            
        let batch3 = db.batch()
        if let docs = outgoingSnapshot?.documents {
            for doc in docs {
                batch3.deleteDocument(doc.reference)
            }
        }
        try? await batch3.commit()
        
        try await db.collection(usersCollection).document(uid).delete()
        
        try? await friendshipsRef.document(uid).delete()
        try? await db.collection("friendRequests").document(uid).delete()
    }
    
    // -------------------------------------------------------
    // FETCH PROFILE
    // -------------------------------------------------------
    func fetchProfile(uid: String) async throws -> UserProfile {
        let doc = try await db.collection(usersCollection).document(uid).getDocument()

        guard let data = doc.data() else {
            throw AuthError.backend("Profile not found.")
        }

        // Backfill the lowercase search index for accounts created before it existed,
        // so existing users become findable in friend search after opening the app once.
        let displayName = data["displayName"] as? String ?? ""
        if !displayName.isEmpty {
            let expectedLower = displayName.lowercased()
            if (data["displayNameLower"] as? String) != expectedLower {
                try? await db.collection(usersCollection).document(uid).updateData([
                    "displayNameLower": expectedLower
                ])
            }
        }

        return try mapDataToProfile(data: data, uid: uid)
    }
    
    func mapDataToProfile(data: [String: Any], uid: String) throws -> UserProfile {
        let firstName = data["firstName"] as? String ?? ""
        let lastName = data["lastName"] as? String ?? ""
        let displayName = data["displayName"] as? String ?? ""
        let email = data["email"] as? String ?? ""
        
        let avatarType = data["avatarType"] as? String ?? "personal"
        let avatarBackground = data["avatarBackground"] as? String
        let avatarBody = data["avatarBody"] as? String
        let avatarFace = data["avatarFace"] as? String
        let avatarShirt = data["avatarShirt"] as? String
        let avatarEyes = data["avatarEyes"] as? String
        let avatarMouth = data["avatarMouth"] as? String
        let avatarHair = data["avatarHair"] as? String
        let avatarFacialHair = data["avatarFacialHair"] as? String
        
        let goldMedalsAccumulated = data["goldMedalsAccumulated"] as? Int ?? 0
        let silverMedalsAccumulated = data["silverMedalsAccumulated"] as? Int ?? 0
        let bronzeMedalsAccumulated = data["bronzeMedalsAccumulated"] as? Int ?? 0
        
        let goldMedalsAwarded = data["goldMedalsAwarded"] as? Int ?? 0
        let silverMedalsAwarded = data["silverMedalsAwarded"] as? Int ?? 0
        let bronzeMedalsAwarded = data["bronzeMedalsAwarded"] as? Int ?? 0
        
        let totalDrawingCount = data["totalDrawingCount"] as? Int ?? 0
        let streakCount = data["streakCount"] as? Int ?? 0
        
        let memberSince = (data["memberSince"] as? Timestamp)?.dateValue() ?? Date()
        let lastCompletedDate = (data["lastCompletedDate"] as? Timestamp)?.dateValue()
        let lastAttemptedDate = (data["lastAttemptedDate"] as? Timestamp)?.dateValue()
        
        return UserProfile(
            uid: uid,
            firstName: firstName,
            lastName: lastName,
            displayName: displayName,
            email: email,
            avatarType: avatarType,
            avatarBackground: avatarBackground,
            avatarBody: avatarBody,
            avatarFace: avatarFace,
            avatarShirt: avatarShirt,
            avatarEyes: avatarEyes,
            avatarMouth: avatarMouth,
            avatarHair: avatarHair,
            avatarFacialHair: avatarFacialHair,
            goldMedalsAccumulated: goldMedalsAccumulated,
            silverMedalsAccumulated: silverMedalsAccumulated,
            bronzeMedalsAccumulated: bronzeMedalsAccumulated,
            goldMedalsAwarded: goldMedalsAwarded,
            silverMedalsAwarded: silverMedalsAwarded,
            bronzeMedalsAwarded: bronzeMedalsAwarded,
            totalDrawingCount: totalDrawingCount,
            streakCount: streakCount,
            memberSince: memberSince,
            lastCompletedDate: lastCompletedDate,
            lastAttemptedDate: lastAttemptedDate
        )
    }
    
    // -------------------------------------------------------
    // UPDATE ANY FIELD (Generic)
    // -------------------------------------------------------
    // ⚠️ Note: Do NOT use this for saving Avatar changes if items are being removed.
    // Swift dictionaries drop nil values, so Firestore won't know to delete the field.
    func updateProfile(uid: String, data: [String: Any]) async throws {
        try await db.collection(usersCollection).document(uid).updateData(data)
    }

    // -------------------------------------------------------
    // UPDATE AVATAR SPECIFICALLY (Handles Deletions)
    // -------------------------------------------------------
    // ✅ Use THIS function for saving the avatar.
    func updateUserAvatar(uid: String, profile: UserProfile) async throws {
        var data: [String: Any] = [
            "avatarType": profile.avatarType
        ]
        
        // Helper: If value is nil, send FieldValue.delete() to remove it from Firestore
        func setValueOrDelete(_ value: String?) -> Any {
            return value ?? FieldValue.delete()
        }
        
        data["avatarBackground"] = setValueOrDelete(profile.avatarBackground)
        data["avatarBody"] = setValueOrDelete(profile.avatarBody)
        data["avatarShirt"] = setValueOrDelete(profile.avatarShirt)
        data["avatarEyes"] = setValueOrDelete(profile.avatarEyes)
        data["avatarMouth"] = setValueOrDelete(profile.avatarMouth)
        data["avatarHair"] = setValueOrDelete(profile.avatarHair)
        data["avatarFacialHair"] = setValueOrDelete(profile.avatarFacialHair)
        
        try await db.collection(usersCollection).document(uid).updateData(data)
    }
    
    static func formatMemberSinceDate(_ date: Date) -> (year: String, monthDay: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        let year = formatter.string(from: date)
        formatter.dateFormat = "MMM d"
        let monthDay = formatter.string(from: date)
        return (year, monthDay)
    }
}
