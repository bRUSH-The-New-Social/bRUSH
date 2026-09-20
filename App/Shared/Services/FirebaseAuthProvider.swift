import Foundation
import UIKit

import FirebaseAuth
import FirebaseCore
import GoogleSignIn

// NOTE: You must ensure 'AuthProviding' and 'GoogleSignInProviding' protocols
// (and 'AuthError' and 'AppUser' types) are available in the scope where this file is used.
// Assuming they are available from AuthService.swift or similar.

#if canImport(FirebaseAuth) && canImport(FirebaseCore)
final class FirebaseAuthProvider: AuthProviding, GoogleSignInProviding, AppleSignInProviding {
    var currentUser: AppUser? {
        if let u = Auth.auth().currentUser {
            // Note: u.email can be nil if signed in via phone/anonymous, using "" as fallback.
            return AppUser(id: u.uid, email: u.email ?? "", displayName: u.displayName)
        }
        return nil
    }

    init() {}

    // MARK: - AuthProviding Methods
    
    func signIn(email: String, password: String) async throws -> AppUser {
        let result = try await signInEmail(email: email, password: password)
        let u = result.user
        return AppUser(id: u.uid, email: u.email ?? email, displayName: u.displayName)
    }

    func signUp(email: String, password: String) async throws -> AppUser {
        let result = try await createUserEmail(email: email, password: password)
        let u = result.user
        return AppUser(id: u.uid, email: u.email ?? email, displayName: u.displayName)
    }

    func signOut() async throws {
        try Auth.auth().signOut()
    }
    
    func deleteUser() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }
        try await deleteCurrentUser(currentUser)
    }

    // MARK: - GoogleSignInProviding Method
    
    @MainActor
    func signInWithGoogle() async throws -> AppUser {
        #if canImport(GoogleSignIn)
        guard let presenting = Self.topViewController() else {
            throw AuthError.backend("No presenting view controller for Google Sign-In")
        }
        let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
        guard let idToken = signInResult.user.idToken?.tokenString else {
            throw AuthError.backend("Missing Google ID token")
        }
        let accessToken = signInResult.user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        let authResult = try await signInWithCredential(credential)
        let u = authResult.user
        return AppUser(id: u.uid, email: u.email ?? "", displayName: u.displayName)
        #else
        throw AuthError.backend("GoogleSignIn SDK not available")
        #endif
    }

    // MARK: - AppleSignInProviding Method
    
    @MainActor
    func signInWithApple() async throws -> AppUser {
        try await withCheckedThrowingContinuation { continuation in
            let helper = AppleSignInHelper()
            helper.startSignInWithAppleFlow { result in
                switch result {
                case .success(let credential):
                    Auth.auth().signIn(with: credential) { authResult, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let u = authResult?.user {
                            let appUser = AppUser(id: u.uid, email: u.email ?? "", displayName: u.displayName)
                            continuation.resume(returning: appUser)
                        } else {
                            continuation.resume(throwing: AuthError.backend("Unknown error signing in with Apple"))
                        }
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers
    private func signInEmail(email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { cont in
            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                if let error = error { cont.resume(throwing: error); return }
                guard let result = result else { cont.resume(throwing: AppAuthError.unknown("No result returned")); return }
                cont.resume(returning: result)
            }
        }
    }

    private func createUserEmail(email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { cont in
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                if let error = error { cont.resume(throwing: error); return }
                guard let result = result else { cont.resume(throwing: AppAuthError.unknown("No result returned")); return }
                cont.resume(returning: result)
            }
        }
    }

    private func signInWithCredential(_ credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { cont in
            Auth.auth().signIn(with: credential) { result, error in
                if let error = error { cont.resume(throwing: error); return }
                guard let result = result else { cont.resume(throwing: AppAuthError.unknown("No result returned")); return }
                cont.resume(returning: result)
            }
        }
    }
    
    private func deleteCurrentUser(_ user: User) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            user.delete { error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: ())
            }
        }
    }

    private static func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes
                                                 .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                                                 .first?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController { return topViewController(base: tab.selectedViewController) }
        if let presented = base?.presentedViewController { return topViewController(base: presented) }
        return base
    }
}
#endif // canImport(FirebaseAuth) && canImport(FirebaseCore)
