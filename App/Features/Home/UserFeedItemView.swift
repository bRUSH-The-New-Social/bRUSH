import SwiftUI
import FirebaseAuth

struct UserFeedItemView: View {
    let item: FeedItem
    let prompt: String
    let loadID: UUID

    @State private var goldCount: Int
    @State private var silverCount: Int
    @State private var bronzeCount: Int
    @State private var goldSelected = false
    @State private var silverSelected = false
    @State private var bronzeSelected = false
    @State private var showOverlays = true
    
    @State private var showAwardConfirmation = false
    @State private var pendingAwardType: AwardType?

    private var isOwnPost: Bool {
        Auth.auth().currentUser?.uid == item.userId
    }


    @Binding var hasPostedToday: Bool
    @Binding var hasAttemptedDrawing: Bool
    @Binding var isPresentingCreate: Bool
    
    @State private var isSharing = false
    @State private var rippleCounter: Int = 0
    @State private var rippleOrigin: CGPoint = .zero
    
    @Namespace private var transition
    @State private var loadedImage: UIImage? = nil
    @State private var imageLoadFailed = false
    
    @State private var isContentLoaded = false
    
    @State private var isShowingProfileSheet: Bool = false
    @ObservedObject var friendsViewModel: FriendsViewModel

    @Binding var isGoldDisabled: Bool
    @Binding var isSilverDisabled: Bool
    @Binding var isBronzeDisabled: Bool
    var onGoldTapped: ((Bool) -> Void)?
    var onSilverTapped: ((Bool) -> Void)?
    var onBronzeTapped: ((Bool) -> Void)?
    var onRefreshNeeded: (() -> Void)?

    init(
        item: FeedItem,
        prompt: String,
        loadID: UUID,
        friendsViewModel: FriendsViewModel,
        hasPostedToday: Binding<Bool>,
        hasAttemptedDrawing: Binding<Bool>,
        isPresentingCreate: Binding<Bool>,
        isGoldDisabled: Binding<Bool>,
        isSilverDisabled: Binding<Bool>,
        isBronzeDisabled: Binding<Bool>,
        onGoldTapped: ((Bool) -> Void)? = nil,
        onSilverTapped: ((Bool) -> Void)? = nil,
        onBronzeTapped: ((Bool) -> Void)? = nil,
        onRefreshNeeded: (() -> Void)? = nil
    ) {
        self.item = item
        self.prompt = prompt
        self.loadID = loadID
        self.friendsViewModel = friendsViewModel

        _goldCount = State(initialValue: item.medalGold)
        _silverCount = State(initialValue: item.medalSilver)
        _bronzeCount = State(initialValue: item.medalBronze)
        
        // Initialize state from FeedItem persistence
        _goldSelected = State(initialValue: item.didGiveGold)
        _silverSelected = State(initialValue: item.didGiveSilver)
        _bronzeSelected = State(initialValue: item.didGiveBronze)

        self._hasPostedToday = hasPostedToday
        self._hasAttemptedDrawing = hasAttemptedDrawing
        self._isPresentingCreate = isPresentingCreate

        self._isGoldDisabled = isGoldDisabled
        self._isSilverDisabled = isSilverDisabled
        self._isBronzeDisabled = isBronzeDisabled

        self.onGoldTapped = onGoldTapped
        self.onSilverTapped = onSilverTapped
        self.onBronzeTapped = onBronzeTapped
        self.onRefreshNeeded = onRefreshNeeded
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ZStack {
                    AsyncImage(url: URL(string: item.imageURL), transaction: Transaction(animation: .easeIn(duration: 0.3))) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .modifier(RippleEffect(at: rippleOrigin, trigger: rippleCounter))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 15)
                                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                        case .failure:
                            Rectangle()
                                .fill(Color(.secondarySystemBackground))
                                .overlay(Image(systemName: "photo.fill").foregroundColor(.gray))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 15)
                                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 15)
                                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                        @unknown default:
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 15)
                                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                        }
                    }

                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard hasPostedToday else { return }
                            rippleOrigin = location
                            rippleCounter += 1
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                                showOverlays.toggle()
                            }
                        }

                    VStack {
                        Text(prompt)
                            .font(.system(size: 16, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.interactive())
                            .opacity(hasPostedToday ? (showOverlays ? 1 : 0) : 0)
                            .scaleEffect(showOverlays ? 1 : 0.95)
                            .animation(.spring(response: 0.25, dampingFraction: 0.55).delay(1.00), value: showOverlays)
                            .padding(.top, 10)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .allowsHitTesting(false)

                    if hasPostedToday {
                        userOverlay
                        actionsOverlay
                    }
                }

                if !hasPostedToday {
                    noPostOverlay
                }
            }
        }
        .aspectRatio(9/16, contentMode: .fit)
        .background(Color.clear)
        .opacity(isContentLoaded ? 1 : 0)
        .animation(.easeIn(duration: 0.3), value: isContentLoaded)
        .sheet(isPresented: $isShowingProfileSheet, onDismiss: {
            // Check if the friend was removed during the sheet interaction
            // We do this by checking if the ID is still in the local view model's friend list
            let isStillFriend = friendsViewModel.friendIds.contains(item.userId)
            let isMe = item.userId == friendsViewModel.meUid
            
            if !isStillFriend && !isMe {
                // Friend was removed, request a refresh
                onRefreshNeeded?()
            }
        }) {
            let profile = UserProfile(
                uid: item.userId,
                firstName: item.firstName,
                lastName: item.lastName,
                displayName: item.displayName,
                email: item.email,
                avatarType: item.avatarType,
                avatarBackground: item.avatarBackground,
                avatarBody: item.avatarBody,
                avatarFace: item.avatarFace,
                avatarShirt: item.avatarShirt,
                avatarEyes: item.avatarEyes,
                avatarMouth: item.avatarMouth,
                avatarHair: item.avatarHair,
                avatarFacialHair: item.avatarFacialHair,
                goldMedalsAccumulated: item.goldMedalsAccumulated,
                silverMedalsAccumulated: item.silverMedalsAccumulated,
                bronzeMedalsAccumulated: item.bronzeMedalsAccumulated,
                goldMedalsAwarded: item.goldMedalsAwarded,
                silverMedalsAwarded: item.silverMedalsAwarded,
                bronzeMedalsAwarded: item.bronzeMedalsAwarded,
                totalDrawingCount: item.totalDrawingCount,
                streakCount: item.streakCount,
                memberSince: item.memberSince,
                lastCompletedDate: item.lastCompletedDate,
                lastAttemptedDate: nil
            )
            FriendProfileSheet(vm: friendsViewModel, profile: profile)
        }
        .sheet(isPresented: $isSharing) {
            ShareSheetLoaderView(item: item, cachedImage: loadedImage)
                .presentationDetents([.medium, .large])
        }
        .task(id: loadID) {
            let isFirstLoad = (loadedImage == nil)
            
            if isFirstLoad {
                self.isContentLoaded = false
                self.imageLoadFailed = false
            }

            let image = await fetchImage()
            
            if Task.isCancelled { return }

            if let image = image {
                self.loadedImage = image
                self.imageLoadFailed = false
            } else {
                if isFirstLoad {
                    self.imageLoadFailed = true
                }
            }
            
            if isFirstLoad {
                self.isContentLoaded = true
            }
        }
    }
    
    private func sendAward(for type: AwardType) {
            Task {
                do {
                    try await AwardServiceFirebase.shared.setAward(type, forPostOwner: item.userId)
                } catch {
                    print("Failed to set \(type) award for \(item.userId): \(error.localizedDescription)")
                }
            }
        }
    
    private func applyAward(type: AwardType) {
        switch type {
        case .gold:
            goldSelected = true
            goldCount += 1
            onGoldTapped?(true)

        case .silver:
            silverSelected = true
            silverCount += 1
            onSilverTapped?(true)

        case .bronze:
            bronzeSelected = true
            bronzeCount += 1
            onBronzeTapped?(true)
        }

        sendAward(for: type)
        
        Task {
            do {
                try await AwardServiceFirebase.shared.incrementUserMedalStats(
                    ownerId: item.userId,
                    giverId: Auth.auth().currentUser!.uid,
                    type: type
                )
            } catch {
                print("Failed to increment stats:", error.localizedDescription)
            }
        }
    }


    private func confirmTitle(for type: AwardType) -> String {
        switch type {
        case .gold: return "Use your gold medal for today?"
        case .silver: return "Use your silver medal for today?"
        case .bronze: return "Use your bronze medal for today?"
        }
    }

    
    private func fetchImage() async -> UIImage? {
        guard let url = URL(string: item.imageURL) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if Task.isCancelled { return nil }
            return UIImage(data: data)
        } catch {
            if !(error is CancellationError) {
                print("Error loading image: \(error.localizedDescription)")
            }
            return nil
        }
    }

    private var userOverlay: some View {
        HStack(spacing: 12) {
            AvatarView(
                avatarType: AvatarType(rawValue: item.avatarType) ?? .personal,
                background: item.avatarBackground ?? "background_1",
                avatarBody: item.avatarBody,
                shirt: item.avatarShirt,
                eyes: item.avatarEyes,
                mouth: item.avatarMouth,
                hair: item.avatarHair,
                facialHair: item.avatarFacialHair,
                includeSpacer: false
            )
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 1) {
                Text(item.firstName).font(.headline).fontWeight(.semibold)
            }
        }
        .padding(8)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { isShowingProfileSheet = true }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(10)
        .opacity(showOverlays ? 1 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.55).delay(0.9), value: showOverlays)
        .allowsHitTesting(showOverlays)
    }

    private var actionsOverlay: some View {
        VStack(spacing: 12) {
            medalButton(assetName: "gold_medal",
                        color: Color(red: 0.8, green: 0.65, blue: 0.0),
                        type: .gold,
                        count: $goldCount,
                        isSelected: $goldSelected,
                        isDisabled: isGoldDisabled || isOwnPost,
                        onTapped: onGoldTapped
                    )
                .opacity(showOverlays ? 1 : 0)
                .animation(.spring(response: 0.25, dampingFraction: 0.55).delay(0.4), value: showOverlays)
                .allowsHitTesting(showOverlays)

            medalButton(assetName: "silver_medal",
                        color: Color.gray,
                        type: .silver,
                        count: $silverCount,
                        isSelected: $silverSelected,
                        isDisabled: isSilverDisabled || isOwnPost,
                        onTapped: onSilverTapped
                    )
                .opacity(showOverlays ? 1 : 0)
                .animation(.spring(response: 0.25, dampingFraction: 0.55).delay(0.55), value: showOverlays)
                .allowsHitTesting(showOverlays)
            
            medalButton(assetName: "bronze_medal",
                        color: Color(red: 0.6, green: 0.35, blue: 0.0),
                        type: .bronze,
                        count: $bronzeCount,
                        isSelected: $bronzeSelected,
                        isDisabled: isBronzeDisabled || isOwnPost,
                        onTapped: onBronzeTapped
                    )
                .opacity(showOverlays ? 1 : 0)
                .animation(.spring(response: 0.25, dampingFraction: 0.55).delay(0.75), value: showOverlays)
                .allowsHitTesting(showOverlays)
            
            shareButton()
                .opacity(showOverlays ? 1 : 0)
                .animation(.spring(response: 0.25, dampingFraction: 0.55).delay(0.90), value: showOverlays)
                .allowsHitTesting(showOverlays)
            
            if !isOwnPost {
                Menu {
                    Button(role: .destructive) {
                        Task { 
                            try? await ModerationService.shared.report(reportedUserID: item.userId, reason: "Inappropriate Content") 
                            await MainActor.run { onRefreshNeeded?() }
                        }
                    } label: {
                        Label("Report Post", systemImage: "exclamationmark.bubble")
                    }
                    Button(role: .destructive) {
                        Task { 
                            try? await ModerationService.shared.blockUser(blockedUserID: item.userId) 
                            await MainActor.run { onRefreshNeeded?() }
                        }
                    } label: {
                        Label("Block User", systemImage: "nosign")
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(10)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
                }
                .opacity(showOverlays ? 1 : 0)
                .animation(.spring(response: 0.25, dampingFraction: 0.55).delay(1.05), value: showOverlays)
                .allowsHitTesting(showOverlays)
            }
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(10)
    }

    private var noPostOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.secondary)
            Button {
                isPresentingCreate = true
            } label: {
                Text("Create Today's Drawing").padding(.horizontal)
            }
            .buttonStyle(.glassProminent)
            .contentShape(Capsule())
            .disabled(hasAttemptedDrawing)

            if hasAttemptedDrawing {
                Text("You chose not to draw today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .zIndex(1)
    }

    @ViewBuilder
    private func medalButton(
        assetName: String,
        color: Color,
        type: AwardType,
        count: Binding<Int>,
        isSelected: Binding<Bool>,
        isDisabled: Bool,
        onTapped: ((Bool) -> Void)?
    ) -> some View {
        
        Button {
            guard !isDisabled else { return }
            pendingAwardType = type
            showAwardConfirmation = true
        } label: {
            VStack(spacing: 4) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .saturation(isDisabled && !isSelected.wrappedValue ? 0.7 : 1)

                let text = Text("\(count.wrappedValue)")
                    .font(.caption)
                    .fontWeight(.semibold)

                if isDisabled && !isSelected.wrappedValue {
                    text.foregroundColor(.primary)
                } else {
                    text.foregroundColor(.white)
                }
            }
            .padding(8)
        }
        .glassEffect(
            isSelected.wrappedValue
                ? .clear.tint(color).interactive()
            : (isDisabled ? .clear.tint(Color(UIColor.systemBackground).opacity(0.5)) : .clear.tint(color.opacity(0.5)).interactive()),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .disabled(isDisabled)
        .animation(.easeInOut, value: isSelected.wrappedValue)
        .confirmationDialog(
            confirmTitle(for: type),
            isPresented: Binding(
                get: { showAwardConfirmation && pendingAwardType == type },
                set: { showAwardConfirmation = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Use", role: .confirm) {
                applyAward(type: type)
                pendingAwardType = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                pendingAwardType = nil
            }
        }
    }

    private func shareButton() -> some View {
        Button { isSharing = true } label: {
            VStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 24, weight: .medium))
            }
            .padding(10)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .frame(minWidth: 48, minHeight: 48)
    }
}

struct ShareSheetLoaderView: View {
    let item: FeedItem
    let cachedImage: UIImage?

    @State private var image: UIImage? = nil
    @State private var isLoading = true

    var body: some View {
        Group {
            if let cached = cachedImage {
                ShareSheet(activityItems: [ImageActivityItemSource(title: "Check out this drawing from \(item.firstName)!", image: cached)])
            } else if isLoading {
                ProgressView("Preparing share item...")
                    .padding()
                    .task { await loadImage() }
            } else if let image = image {
                ShareSheet(activityItems: [ImageActivityItemSource(title: "Check out this drawing from \(item.firstName)!", image: image)])
            } else {
                Text("Failed to load image.").foregroundColor(.secondary)
            }
        }
    }

    private func loadImage() async {
        guard let url = URL(string: item.imageURL) else { isLoading = false; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let uiImage = UIImage(data: data) { image = uiImage }
        } catch { print(error) }
        isLoading = false
    }
}
