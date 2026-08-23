import SwiftUI
import PencilKit
import UserNotifications
import FirebaseCore

@main
struct brushApp: App {
    
    @StateObject var dataModel = DataModel()
    
    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
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
                    ProfileView() // Assuming ProfileView exists
                }
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
            }
            .environmentObject(dataModel)
            .environmentObject(RevenueCatService.shared)
        }
    }
}
