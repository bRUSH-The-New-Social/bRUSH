import SwiftUI

/// App root that gates all content behind authentication.
///
/// When no user is signed in, only the sign-in screen is shown and reachable —
/// the main `TabView` (Home, Drawings, Friends, Profile) is never constructed,
/// so those screens can't load with a nil UID and surface errors (e.g. the
/// Friends tab). Once signed in, the tabs appear.
struct RootView: View {
    @StateObject private var auth = AuthService.shared
    @StateObject private var signInViewModel = ProfileViewModel()

    var body: some View {
        Group {
            if auth.isRestoringSession {
                // Hold on a neutral screen while Firebase restores any persisted
                // session, so we don't flash the sign-in screen for a user who
                // is actually already signed in.
                ZStack {
                    HomeBackground()
                        .ignoresSafeArea()
                    ProgressView()
                }
            } else if auth.user != nil {
                MainTabView()
                    .task(id: auth.user?.id) {
                        // Request notification permission in-context, only once the
                        // user is signed in, then set up the daily reminder.
                        NotificationManager.shared.requestPermission()
                        NotificationManager.shared.scheduleNextReminder()
                    }
            } else {
                NavigationStack {
                    SignInProfileView(viewModel: signInViewModel)
                }
            }
        }
    }
}

/// The signed-in experience: the four primary tabs.
struct MainTabView: View {
    var body: some View {
        TabView {
            // 1. Home Tab
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            // 2. Drawings Tab
            NavigationStack {
                DrawingsGridView()
            }
            .tabItem {
                VStack {
                    Image(systemName: "pencil.and.outline")
                        .overlay(
                            Circle()
                                .stroke(Color.accentColor, lineWidth: 2)
                                .frame(width: 32, height: 32)
                        )
                    Text("Drawings")
                }
            }

            // 3. Friends Tab
            NavigationStack {
                FriendsView()
            }
            .tabItem {
                Label("Friends", systemImage: "person.2")
            }

            // 4. Profile Tab
            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
        }
    }
}
