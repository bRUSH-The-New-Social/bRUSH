import Foundation
import Combine
import FirebaseAuth

// MARK: - AuthError (No changes here, keeping for context)
public enum AuthError: LocalizedError {
    case invalidCredentials
    case userAlreadyExists
    case notAuthenticated
    case backend(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Invalid username or password."
        case .userAlreadyExists: return "An account with this email already exists."
        case .notAuthenticated: return "Not authenticated."
        case .backend(let message): return message
        }
    }
}

// MARK: - AppUser (No changes here, keeping for context)
public struct AppUser: Equatable {
    public let id: String
    public let email: String
    public let displayName: String?
}

// MARK: - AuthProviding Protocol (No changes here, keeping for context)
public protocol AuthProviding {
    var currentUser: AppUser? { get }
    func signIn(email: String, password: String) async throws -> AppUser
    func signUp(email: String, password: String) async throws -> AppUser
    func signOut() async throws
    func deleteUser() async throws
}

// MARK: - InMemoryAuthProvider (No changes here, keeping for context)
final class InMemoryAuthProvider: AuthProviding {
    private var users: [String: (password: String, displayName: String?)] = [:]
    private(set) var currentUser: AppUser?

    func signIn(email: String, password: String) async throws -> AppUser {
        guard let entry = users[email.lowercased()], entry.password == password else {
            throw AuthError.invalidCredentials
        }
        let user = AppUser(id: UUID().uuidString, email: email, displayName: entry.displayName)
        currentUser = user
        return user
    }

    func signUp(email: String, password: String) async throws -> AppUser {
        let key = email.lowercased()
        guard users[key] == nil else { throw AuthError.userAlreadyExists }
        users[key] = (password, nil)
        let user = AppUser(id: UUID().uuidString, email: email, displayName: nil)
        currentUser = user
        return user
    }

    func signOut() async throws {
        currentUser = nil
    }
    
    func deleteUser() async throws {
        // In memory implementation - just clear current user
        currentUser = nil
    }
}

protocol GoogleSignInProviding {
    @MainActor
    func signInWithGoogle() async throws -> AppUser
}

protocol AppleSignInProviding {
    @MainActor
    func signInWithApple() async throws -> AppUser
}

// MARK: - AuthService (Updated signUp logic)
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var user: AppUser?
    private let provider: AuthProviding

    init(provider: AuthProviding? = nil) {
        #if canImport(FirebaseAuth)
        let chosen: AuthProviding = provider ?? FirebaseAuthProvider()
        #else
        let chosen: AuthProviding = provider ?? InMemoryAuthProvider()
        #endif
        self.provider = chosen
        self.user = chosen.currentUser
    }
    
    // 💡 HELPER: Maps cryptic system/Firebase errors to user-friendly AuthErrors.
    private func mapAuthError(_ error: Error) -> Error {
        let description = error.localizedDescription
        
        if description.contains("malformed or has expired") ||
           description.contains("wrong password") ||
           description.contains("no user record") {
            return AuthError.invalidCredentials
        }
        
        if description.contains("email address is badly formatted") {
            return AuthError.backend("Invalid email address.")
        }

        if description.contains("requires recent login") {
            return AuthError.backend("To delete your account, please sign out and sign in again to re-authenticate.")
        }
        
        if let authError = error as? AuthError {
            return authError
        }
        
        return AuthError.backend(description)
    }

    @MainActor
    func signIn(email: String, password: String) async throws {
        do {
            let u = try await provider.signIn(email: email, password: password)
            self.user = u
        } catch {
            throw mapAuthError(error)
        }
    }

    @MainActor
    func signUp(email: String, password: String) async throws -> AppUser {
        do {
            // Only perform Auth creation here.
            let u = try await provider.signUp(email: email, password: password)
            // NOTE: We don't update self.user here, only in the sign-in flow.
            // The SignUpViewModel should drive the completion.
            // In this specific refactor, we rely on the provider returning the user,
            // and the ProfileViewModel listens for changes if Auth.auth().currentUser updates.
            self.user = u // Keep this line to immediately update the main UI listener
            return u // Return the AppUser with the UID
        } catch {
            throw mapAuthError(error)
        }
    }

    @MainActor
    func signInWithGoogle() async {
        if let googleProvider = provider as? GoogleSignInProviding {
            do {
                let u = try await googleProvider.signInWithGoogle()
                self.user = u
            } catch {
                print("Auth Google signIn error: \(error)")
            }
        } else {
            print("Google Sign-In not available in current build.")
        }
    }

    @MainActor
    func signInWithApple() async {
        if let appleProvider = provider as? AppleSignInProviding {
            do {
                let u = try await appleProvider.signInWithApple()
                self.user = u
            } catch {
                print("Auth Apple signIn error: \(error)")
            }
        } else {
            print("Apple Sign-In not available in current build.")
        }
    }

    @MainActor
    func signOut() async {
        do {
            try await provider.signOut()
            self.user = nil
        } catch {
            print("Auth signOut error: \(error)")
        }
    }
    
    @MainActor
    func deleteUser() async throws {
        do {
            try await provider.deleteUser()
            self.user = nil
        } catch {
            throw mapAuthError(error)
        }
    }
}
