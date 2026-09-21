import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

@MainActor
class FriendsViewModel: ObservableObject {
    @Published var friends: [UserProfile] = []
    @Published var searchText: String = ""
    @Published var requests: [FriendRequest] = []
    @Published var addQuery: String = ""
    @Published var addResults: [FriendSearchResult] = []
    @Published var isSearchingAdd: Bool = false
    @Published var addError: String?
    @Published var sent: [SentFriendRequest] = []
    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var isLoadingLeaderboard = false
    @Published var leaderboardError: String?
    @Published var currentUser: UserProfile?
    @Published var friendIds: Set<String> = []
    @Published var showingProfile: Bool = false
    @Published var selectedProfile: UserProfile? = nil
    @Published var selectedFriendUid: String? = nil
    @Published var medalCountsByUid: [String: (gold: Int, silver: Int, bronze: Int)] = [:]
    @Published var pendingOutgoing: Set<String> = []
    
    private var cancellables = Set<AnyCancellable>()
    private let handleService = HandleServiceFirebase()
    private let requestService = FriendRequestServiceFirebase()
    private let notificationManager = NotificationManager.shared
    private let userService = UserService.shared
    
    var meUid: String? { AuthService.shared.user?.id }
    
    private var myHandle: String { currentUser?.displayName ?? AuthService.shared.user?.displayName ?? "unknown" }
    private var myFullName: String {
        guard let user = currentUser else { return "" }
        return [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }
    
    deinit {
        requestService.stopListeningForIncoming()
    }
    
    // MARK: - Async Data Loading
    
    func refreshAllData() async {
        // Run profile and friends fetch in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadMyProfileData() }
            group.addTask { await self.refreshFriends() }
            group.addTask { await self.refreshIncoming() }
        }
        
        // Start the real-time listener for requests (Synchronous setup)
        self.refreshIncoming()
        
        // Leaderboard depends on friends data, so load it after
        loadLeaderboard()
    }
    
    func loadMyProfileData() async {
        guard let me = meUid else { return }
        do {
            let profile = try await userService.fetchProfile(uid: me)
            self.currentUser = profile
        } catch {
            print("Error loading my profile: \(error)")
        }
    }
    
    func refreshFriends() async {
        guard let me = meUid else {
            self.friendIds = []
            self.friends = []
            return
        }
        
        do {
            let snap = try await Firestore.firestore()
                .collection("friendships").document(me)
                .collection("friends").getDocuments()
            
            let newIds = Set(snap.documents.map { $0.documentID })
            
            // Always hydrate if the list is empty (first load) or if IDs changed
            if newIds != self.friendIds || self.friends.isEmpty {
                self.friendIds = newIds
                await hydrateFriendsFromIds()
            }
        } catch {
            print("Error refreshing friends: \(error)")
        }
    }
    
    private func hydrateFriendsFromIds() async {
        let ids = Array(self.friendIds)
        guard !ids.isEmpty else {
            self.friends = []
            return
        }
        
        var loadedProfiles: [UserProfile] = []
        
        // Fetch profiles
        for uid in ids {
            do {
                let profile = try await userService.fetchProfile(uid: uid)
                loadedProfiles.append(profile)
            } catch {
                print("Failed to load profile for \(uid)")
            }
        }
        
        self.friends = loadedProfiles.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
    
    // MARK: - Real-time Incoming Requests
    
    func refreshIncoming() {
        guard let me = meUid else {
            requestService.stopListeningForIncoming()
            self.requests = []
            return
        }
        
        // Start the real-time listener
        requestService.startListeningForIncoming(forUid: me) { [weak self] dtos in
            Task { @MainActor in
                guard let self = self else { return }
                
                var hydratedRequests: [FriendRequest] = []
                
                // Track UIDs for requests currently known to the ViewModel
                let existingRequestUids = Set(self.requests.map { $0.fromUid })
                var newRequestProfiles: [FriendRequest] = []

                // Hydrate profiles in parallel using TaskGroup
                await withTaskGroup(of: FriendRequest?.self) { group in
                    for dto in dtos {
                        group.addTask {
                            let cleanUid = dto.fromUid.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !cleanUid.isEmpty else { return nil }
                            
                            do {
                                let profile = try await self.userService.fetchProfile(uid: cleanUid)
                                let fullName = [profile.firstName, profile.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                                let finalName = fullName.isEmpty ? profile.displayName : fullName
                                let finalHandle = "@\(profile.displayName)"
                                
                                let request = FriendRequest(
                                    fromUid: cleanUid,
                                    fromName: finalName.isEmpty ? "Unknown" : finalName,
                                    handle: finalHandle.isEmpty ? "@unknown" : finalHandle
                                )
                                
                                // Check if this request is new
                                if !existingRequestUids.contains(cleanUid) {
                                    await MainActor.run {
                                        newRequestProfiles.append(request)
                                    }
                                }
                                
                                return request
                            } catch {
                                if let authErr = error as? AuthError, case .backend(let msg) = authErr, msg == "Profile not found." {
                                    return nil
                                }
                                
                                return FriendRequest(
                                    fromUid: cleanUid,
                                    fromName: dto.fromDisplay.isEmpty ? dto.fromHandle : dto.fromDisplay,
                                    handle: dto.fromHandle
                                )
                            }
                        }
                    }
                    
                    for await req in group {
                        if let req = req {
                            hydratedRequests.append(req)
                        }
                    }
                }
                
                self.requests = hydratedRequests.sorted { $0.fromName.localizedCaseInsensitiveCompare($1.fromName) == .orderedAscending }
                
                // Trigger notifications for newly detected requests
                for newReq in newRequestProfiles {
                    self.notificationManager.scheduleFriendRequestNotification(
                        from: newReq.fromName,
                        handle: newReq.handle
                    )
                }

                self.addError = nil
            }
        }
    }
    
    // MARK: - Standard Actions
    
    var filteredFriends: [UserProfile] {
        guard !searchText.isEmpty else { return friends }
        return friends.filter {
            let name = [$0.firstName, $0.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            return name.localizedCaseInsensitiveContains(searchText) ||
                   $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    func removeLocally(uids: [String]) {
        guard !uids.isEmpty else { return }
        let uidSet = Set(uids)
        friends.removeAll { uidSet.contains($0.uid) }
        friendIds.subtract(uidSet)
        if !addQuery.isEmpty { performAddSearch() }
    }
    
    func removeRemote(uids: [String]) async {
        guard let me = AuthService.shared.user?.id, !uids.isEmpty else { return }
        for other in uids {
            try? await requestService.removeFriend(me: me, other: other)
        }
        await refreshFriends()
    }
    
    func accept(_ req: FriendRequest) async {
        guard let me = meUid else { return }
        withAnimation { requests.removeAll { $0.id == req.id } }
        
        do {
            try await requestService.accept(me: me, other: req.fromUid)
            if let newProfile = try? await userService.fetchProfile(uid: req.fromUid) {
                withAnimation {
                    friends.append(newProfile)
                    friends.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                    friendIds.insert(newProfile.uid)
                }
            }
            // Refresh incoming to keep the listener in sync
            refreshIncoming()
        } catch {
            addError = "Failed to accept request."
            refreshIncoming()
        }
    }
    
    func decline(_ req: FriendRequest) async {
        guard let me = meUid else { return }
        withAnimation { requests.removeAll { $0.id == req.id } }
        do {
            try await requestService.decline(me: me, other: req.fromUid)
        } catch {
            addError = "Failed to decline request."
            refreshIncoming()
        }
    }
    
    // MARK: - Search & Add Logic
    
    private func searchTask(for query: String) async {
        guard let me = meUid else {
            self.addResults = []
            self.addError = "Sign in to search."
            self.isSearchingAdd = false
            return
        }
        
        let raw = query.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 1 else {
            self.addResults = []
            self.addError = nil
            self.isSearchingAdd = false
            return
        }
        
        self.addError = nil
        
        do {
            let hits = try await handleService.searchHandles(prefix: raw, limit: 20)
            var searchResults = hits.map { FriendSearchResult(uid: $0.uid, handle: $0.handle, fullName: $0.fullName) }
            
            // 🚫 Filter out blocked users
            let blockedSnapshot = try? await Firestore.firestore()
                .collection("users")
                .document(me)
                .collection("blockedUsers")
                .getDocuments()
            if let blockedDocs = blockedSnapshot?.documents {
                let blockedIDs = Set(blockedDocs.compactMap { $0.data()["blockedUserID"] as? String })
                searchResults.removeAll { blockedIDs.contains($0.uid) }
            }

            var newPending: Set<String> = []

            await withTaskGroup(of: (String, Bool, Bool).self) { group in
                for hit in searchResults {
                    group.addTask {
                        let isPending = (try? await self.requestService.hasPending(fromUid: me, toUid: hit.uid)) ?? false
                        
                        let isFriend = (try? await Firestore.firestore()
                            .collection("friendships").document(me)
                            .collection("friends").document(hit.uid)
                            .getDocument().exists) ?? false
                            
                        return (hit.uid, isPending, isFriend)
                    }
                }
                
                var newFriends: Set<String> = []
                
                for await (uid, isPending, isFriend) in group {
                    if isPending { newPending.insert(uid) }
                    if isFriend { newFriends.insert(uid) }
                }
                
                if !newFriends.isEmpty {
                    self.friendIds.formUnion(newFriends)
                }
            }

            let searchResultUids = Set(searchResults.map { $0.uid })
            self.sent.removeAll { request in
                return searchResultUids.contains(request.toUid) && !newPending.contains(request.toUid)
            }

            self.addResults = searchResults
            self.pendingOutgoing = newPending
            self.isSearchingAdd = false
            
        } catch {
            self.addResults = []
            self.addError = "Search failed."
            self.isSearchingAdd = false
        }
    }
    
    func performAddSearch() {
        Task { await searchTask(for: addQuery) }
    }
    
    init() {
        $addQuery
            .removeDuplicates()
            .map { [weak self] query -> String in
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { @MainActor in
                    self?.isSearchingAdd = !trimmed.isEmpty
                    self?.addError = nil
                    if trimmed.isEmpty { self?.addResults = [] }
                }
                return trimmed
            }
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] trimmedQuery in
                guard !trimmedQuery.isEmpty else { return }
                Task { await self?.searchTask(for: trimmedQuery) }
            }
            .store(in: &cancellables)
    }
    
    func loadLeaderboard(for date: Date = Date()) {
        isLoadingLeaderboard = true
        leaderboardError = nil
        
        var allProfiles = friends
        if let me = currentUser, !allProfiles.contains(where: { $0.uid == me.uid }) {
            allProfiles.append(me)
        }
        
        let entries = allProfiles.map { LeaderboardEntry(profile: $0) }
        self.leaderboard = entries.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            return $0.fullName < $1.fullName
        }
        
        var medalMap: [String: (gold: Int, silver: Int, bronze: Int)] = [:]
        for entry in entries {
            medalMap[entry.uid] = (entry.gold, entry.silver, entry.bronze)
        }
        self.medalCountsByUid = medalMap
        isLoadingLeaderboard = false
    }
    
    func sendFriendRequest(to user: FriendSearchResult) {
        let handleLabel = "@\(user.handle)"
        guard !sent.contains(where: { $0.toUid == user.uid }) else { return }
        
        sent.append(.init(toName: user.fullName, toUid: user.uid, handle: handleLabel))
        pendingOutgoing.insert(user.uid)
        
        guard let me = meUid else { return }
        let senderHandle = myHandle
        let senderDisplay = myFullName
        
        Task {
            do {
                try await FriendRequestServiceFirebase().sendRequest(
                    fromUid: me,
                    fromHandle: senderHandle,
                    fromDisplay: senderDisplay.isEmpty ? senderHandle : senderDisplay,
                    toUid: user.uid)
            }
            catch {
                sent.removeAll { $0.toUid == user.uid }
                pendingOutgoing.remove(user.uid)
                addError = "Failed to send friend request."
            }
        }
    }
    
    func remove(friendProfile: UserProfile) {
        guard let me = AuthService.shared.user?.id else { return }
        Task {
            if let idx = friends.firstIndex(of: friendProfile) { friends.remove(at: idx) }
            friendIds.remove(friendProfile.uid)
            try? await requestService.removeFriend(me: me, other: friendProfile.uid)
            if !addQuery.isEmpty { performAddSearch() }
            await refreshFriends()
        }
    }
    
    func openProfile(for profile: UserProfile) {
        self.selectedProfile = profile
        self.showingProfile = true
    }
    
    func openProfile(for searchResult: FriendSearchResult) {
        Task {
            self.selectedProfile = nil
            self.showingProfile = true
            if let profile = try? await userService.fetchProfile(uid: searchResult.uid) {
                self.selectedProfile = profile
            } else {
                self.showingProfile = false
            }
        }
    }
    
    func openProfile(for request: FriendRequest) {
        Task {
            self.selectedProfile = nil
            self.showingProfile = true
            if let profile = try? await userService.fetchProfile(uid: request.fromUid) {
                self.selectedProfile = profile
            } else {
                self.showingProfile = false
            }
        }
    }
    
    func isRequestPending(uid: String) -> Bool {
        pendingOutgoing.contains(uid)
    }
    
    func resetSessionData() {
        friends = []
        currentUser = nil
        requests = []
        sent = []
        pendingOutgoing = []
        addResults = []
        addQuery = ""
        requestService.stopListeningForIncoming()
    }
}
