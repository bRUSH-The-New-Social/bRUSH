import Foundation
import Combine
import SwiftUI

@MainActor
class EditProfileViewModel: ObservableObject {
    @Published var firstName: String
    @Published var displayName: String
    @Published var firstNameError: String?
    @Published var displayNameError: String?
    @Published private(set) var isSaving = false

    // We keep this to access the UID, but we create copies when saving updates
    private let userProfile: UserProfile

    init(userProfile: UserProfile) {
        self.userProfile = userProfile
        self.firstName = userProfile.firstName
        self.displayName = userProfile.displayName
    }

    var isValid: Bool {
        validateFirstName() == nil && validateDisplayName() == nil
    }
    
    // Real-time validation properties for UI feedback
    var isFirstNameTooLong: Bool {
        return firstName.count > 10
    }
    
    var isDisplayNameTooLong: Bool {
        return displayName.count > 15
    }
    
    var isDisplayNameInvalidFormat: Bool {
        return !displayName.isEmpty && !isValidUsername(displayName)
    }
    
    // Helper function to validate username format (letters, numbers, underscores only)
    private func isValidUsername(_ username: String) -> Bool {
        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return allowedChars.isSuperset(of: CharacterSet(charactersIn: username))
    }

    /// Save changes to Firestore (Profile Info)
    func saveChanges() async -> Bool {
        // Validate before save
        firstNameError = validateFirstName()
        displayNameError = validateDisplayName()

        guard firstNameError == nil, displayNameError == nil else {
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await UserService.shared.updateProfile(
                uid: userProfile.uid,
                data: [
                    "firstName": firstName,
                    "displayName": displayName,   // ✅ match your UserProfile struct + Firestore field
                    "displayNameLower": displayName.lowercased()  // keep search index in sync
                ]
            )
            return true
        } catch {
            firstNameError = "Failed to save: \(error.localizedDescription)"
            return false
        }
    }
    
    /// Save avatar changes to Firestore
    /// ✅ FIXED: Uses updateUserAvatar to handle deletions correctly
    func saveAvatarChanges(avatarParts: AvatarParts) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        // 1. Create a mutable copy of the profile
        var updatedProfile = self.userProfile
        
        // 2. Apply the new avatar parts to the struct
        // Since 'updatedProfile' is a struct, assigning nil to these optional properties
        // keeps them as nil.
        updatedProfile.avatarType = avatarParts.avatarType.rawValue
        updatedProfile.avatarBackground = avatarParts.background
        updatedProfile.avatarBody = avatarParts.body
        updatedProfile.avatarShirt = avatarParts.shirt
        updatedProfile.avatarEyes = avatarParts.eyes
        updatedProfile.avatarMouth = avatarParts.mouth
        updatedProfile.avatarHair = avatarParts.hair
        updatedProfile.avatarFacialHair = avatarParts.facialHair

        do {
            // 3. Pass the whole struct to the new Service method
            // The Service will see the 'nil' values and send FieldValue.delete() to Firebase
            try await UserService.shared.updateUserAvatar(
                uid: updatedProfile.uid,
                profile: updatedProfile
            )
            return true
        } catch {
            firstNameError = "Failed to save avatar: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Validation
    private func validateFirstName() -> String? {
        let trimmed = firstName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "First name cannot be empty." }
        guard trimmed.count >= 3 else { return "First name must be at least 3 characters long." }
        guard trimmed.count <= 20 else { return "First name cannot be more than 20 characters long." }
        return nil
    }

    private func validateDisplayName() -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Username cannot be empty." }
        guard trimmed.count >= 3 else { return "Username must be at least 3 characters long." }
        guard trimmed.count <= 15 else { return "Username cannot be more than 15 characters long." }

        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard allowedChars.isSuperset(of: CharacterSet(charactersIn: trimmed)) else {
            return "Username can only contain letters, numbers, and underscores."
        }
        return nil
    }
}
