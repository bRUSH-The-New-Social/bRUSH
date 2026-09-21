import SwiftUI
import PencilKit
import UserNotifications
import FirebaseCore
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        
        return true
    }
    
    // Also add the application(_:open:options:) method just in case
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

@main
struct brushApp: App {
    // Register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject var dataModel = DataModel()

    init() {
        NotificationManager.shared.requestPermission()
        NotificationManager.shared.scheduleNextReminder()
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
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
            .environmentObject(dataModel)
            .environmentObject(RevenueCatService.shared)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
