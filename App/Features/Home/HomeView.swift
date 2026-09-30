import SwiftUI
import Vortex

struct ViewOffsetKey: PreferenceKey {
    typealias Value = [Int: CGFloat]
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct HomeView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var showOnboarding: Bool = false
    @State private var showingNotifications: Bool = false
    @StateObject private var viewModel = HomeViewModel()

    @StateObject private var friendsViewModel = FriendsViewModel()

    @State private var isOnboardingPresented: Bool = false
    @State private var isPresentingCreate: Bool = false

    @Namespace private var launchAnimation
    @State private var isShowingSplash = true
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    @State private var didDismissCreate = false

    @State private var showSnow: Bool = HomeView.isWinter()
    @State private var snowSystem: VortexSystem = HomeView.createGentleSnow()
    @State private var isRefreshing: Bool = false
    @State private var isInitialLoading: Bool = true
    @State private var hasInitialLoadCompleted: Bool = false

    @State private var loadID = UUID()

    @EnvironmentObject var dataModel: DataModel
    @State private var currentFeedIndex: Int = 0

    @State private var dailyGoldAwarded: Bool = false
    @State private var dailySilverAwarded: Bool = false
    @State private var dailyBronzeAwarded: Bool = false

    @State private var didJustPost: Bool = false
    @State private var actuallyShowStreakView: Bool = false

    @State private var isReloadingWithOverlay: Bool = false

    @State private var hasUnreadNotifications: Bool = false

    private var safeAreaInsets: UIEdgeInsets {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        return keyWindow?.safeAreaInsets ?? .zero
    }

    private func reloadFeed(showOverlay: Bool) async {
        if showOverlay {
            await MainActor.run {
                isReloadingWithOverlay = true
            }
        }

        await viewModel.checkUserPostStatus()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await viewModel.loadFeed() }
            group.addTask { await friendsViewModel.refreshFriends() }
        }

        await MainActor.run {
            loadID = UUID()
            if showOverlay {
                isReloadingWithOverlay = false
            }
        }
    }

    private func updateNotificationStatus() {
        hasUnreadNotifications = !NotificationManager.shared.getNotificationHistory().isEmpty
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    AnimatedMeshGradientBackground()
                        .ignoresSafeArea()
                        .matchedGeometryEffect(id: "backgroundAnimation", in: launchAnimation)
                        .opacity(isShowingSplash ? 0 : 1)

                    VStack(spacing: 0) {
                        GeometryReader { geometry in
                            let topPadding: CGFloat = safeAreaInsetsTop() + 34 + 24 + 22
                            let bottomPadding: CGFloat = safeAreaInsetsBottom() + (UIDevice.current.userInterfaceIdiom == .pad ? 22 : 70)
                            let availableHeight = geometry.size.height - topPadding - bottomPadding

                            let sidePadding: CGFloat = (UIDevice.current.userInterfaceIdiom == .pad ? 0 : 6)
                            let cardWidth = availableHeight * (9.0 / 16.0) - sidePadding

                            ScrollViewReader { proxy in
                                ZStack(alignment: .center) {
                                    ScrollView(.vertical) {
                                        LazyVStack(spacing: 0) {
                                            ForEach(viewModel.feedItems.indices, id: \.self) { index in
                                                let item = viewModel.feedItems[index]

                                                ZStack {
                                                    UserFeedItemView(
                                                        item: item,
                                                        prompt: viewModel.dailyPrompt,
                                                        loadID: loadID,
                                                        friendsViewModel: friendsViewModel,
                                                        hasPostedToday: $viewModel.hasPostedToday,
                                                        hasAttemptedDrawing: $viewModel.hasAttemptedDrawing,
                                                        isPresentingCreate: $isPresentingCreate,
                                                        isGoldDisabled: $dailyGoldAwarded,
                                                        isSilverDisabled: $dailySilverAwarded,
                                                        isBronzeDisabled: $dailyBronzeAwarded,
                                                        onGoldTapped: { isSelected in dailyGoldAwarded = isSelected },
                                                        onSilverTapped: { isSelected in dailySilverAwarded = isSelected },
                                                        onBronzeTapped: { isSelected in dailyBronzeAwarded = isSelected },
                                                        onRefreshNeeded: {
                                                            Task {
                                                                await reloadFeed(showOverlay: true)
                                                            }
                                                        }
                                                    )
                                                    .frame(width: cardWidth, height: availableHeight)
                                                    .padding(.bottom, bottomPadding)
                                                }
                                                .containerRelativeFrame(.vertical)
                                                .scrollTransition { content, phase in
                                                    content
                                                        .opacity(phase.isIdentity ? 1 : 0.8)
                                                        .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                                }
                                                .id(index)
                                                .background(
                                                    GeometryReader { itemGeo in
                                                        Color.clear
                                                            .preference(
                                                                key: ViewOffsetKey.self,
                                                                value: [index: itemGeo.frame(in: .named("feedScroll")).midY]
                                                            )
                                                    }
                                                )
                                            }
                                        }
                                        .scrollTargetLayout()
                                    }
                                    .scrollTargetBehavior(.paging)
                                    .scrollBounceBehavior(.always)
                                    .scrollIndicators(.hidden)
                                    .ignoresSafeArea()
                                    .contentMargins(.top, topPadding, for: .scrollContent)
                                    .coordinateSpace(name: "feedScroll")
                                    .onPreferenceChange(ViewOffsetKey.self) { values in
                                        DispatchQueue.main.async {
                                            let scrollCenter = geometry.size.height / 2

                                            if let closest = values.min(by: { abs($0.value - scrollCenter) < abs($1.value - scrollCenter) }) {
                                                if currentFeedIndex != closest.key {
                                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                        currentFeedIndex = closest.key
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .refreshable {
                                        guard !viewModel.isLoadingFeed else { return }
                                        isRefreshing = true
                                        await reloadFeed(showOverlay: false)
                                        isRefreshing = false
                                        hasInitialLoadCompleted = true
                                    }

                                    if !viewModel.feedItems.isEmpty {
                                        let itemCount = viewModel.feedItems.count
                                        let capsuleWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 10 : 6
                                        let verticalSpacing: CGFloat = capsuleWidth

                                        let contentHeightBetweenBars = availableHeight

                                        let totalSpacing = CGFloat(max(0, itemCount - 1)) * verticalSpacing
                                        let availableHeightForCapsules = contentHeightBetweenBars - totalSpacing
                                        let capsuleHeight = max(4, availableHeightForCapsules / CGFloat(max(1, itemCount)))

                                        HStack {
                                            Spacer()
                                            VStack {
                                                VStack(spacing: verticalSpacing) {
                                                    ForEach(viewModel.feedItems.indices, id: \.self) { index in
                                                        Button(action: {
                                                            withAnimation(.spring()) {
                                                                proxy.scrollTo(index, anchor: .center)
                                                            }
                                                        }) {
                                                            Capsule()
                                                                .fill(
                                                                    currentFeedIndex == index
                                                                    ? (colorScheme == .dark
                                                                       ? Color(red: 0.65, green: 0.05, blue: 0.1)
                                                                       : Color.red)
                                                                    : (colorScheme == .dark
                                                                       ? Color(red: 0.6, green: 0.3, blue: 0.0)
                                                                       : Color.accentColor)
                                                                )
                                                                .frame(width: capsuleWidth, height: capsuleHeight)
                                                                .contentShape(Capsule())
                                                                .frame(minWidth: (UIDevice.current.userInterfaceIdiom == .pad ? 30 : 24), alignment: .trailing)
                                                                .padding(.trailing, 8)
                                                        }
                                                    }
                                                }
                                                .frame(maxHeight: contentHeightBetweenBars)
                                                .clipped()
                                            }
                                            .frame(height: availableHeight)
                                            .padding(.top, topPadding)
                                            .padding(.bottom, bottomPadding)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                        .zIndex(1)
                                    }
                                }
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                    .ignoresSafeArea()
                    .opacity(isShowingSplash ? 0 : 1)

                    if showSnow {
                        VortexView(snowSystem) {
                            Circle()
                                .fill(.white)
                                .frame(width: 20)
                                .blur(radius: 5)
                                .tag("circle")
                        }
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(2)
                        .opacity(isShowingSplash ? 0 : 1)
                    }

                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            if !isShowingSplash {
                                Image("brush_logo_2")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 34)
                                    .matchedGeometryEffect(id: "logoAnimation", in: launchAnimation)
                                    .padding(.leading)
                            } else {
                                Spacer().frame(height: 34)
                            }

                            Spacer()
                        }
                        .padding(.top, safeAreaInsetsTop() + 6)
                        .padding(.bottom, 18)
                        .background(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color(UIColor.systemBackground).opacity(0.85), location: 0),
                                    .init(color: Color(UIColor.systemBackground).opacity(0.0), location: 1)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .background(.ultraThinMaterial)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .zIndex(3)

                    if (viewModel.isLoadingFeed && isInitialLoading) || isReloadingWithOverlay {
                        VStack {
                            ProgressView()
                                .padding()
                            Text("Loading Feed...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                        .zIndex(1)
                        .transition(.opacity)
                    } else if viewModel.feedItems.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "scribble.variable")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundColor(Color.primary.opacity(0.4))
                            Text("Be the first one to draw today!")
                                .font(.headline)
                                .foregroundColor(Color.primary.opacity(0.4))
                            Button {
                                isPresentingCreate = true
                            } label: {
                                Text("Draw Now")
                                    .padding(.horizontal)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(viewModel.hasAttemptedDrawing)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AnimatedMeshGradientBackground().ignoresSafeArea())
                        .zIndex(1)
                        .opacity(isShowingSplash ? 0 : 1)
                    }

                    if actuallyShowStreakView {
                        StreakUpdateView(isShowing: $actuallyShowStreakView)
                            .zIndex(10)
                            .transition(.opacity)
                    }
                }
                .toolbar {
                    ToolbarSpacer(.fixed)

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { withAnimation { showingNotifications.toggle() } }) {
                            Image(systemName: "bell.fill")
                                .imageScale(.large)
                                .foregroundStyle(.accent)
                                .overlay(alignment: .topTrailing) {
                                    if hasUnreadNotifications {
                                        ZStack {
                                            Circle()
                                                .fill(Color(uiColor: UIColor { trait in
                                                    trait.userInterfaceStyle == .dark
                                                        ? UIColor.secondarySystemBackground
                                                        : UIColor.systemBackground
                                                }))
                                            Circle().fill(Color(red: 1.0, green: 0.0, blue: 0.0))
                                                .frame(width: 7, height: 7)
                                        }
                                        .frame(width: 10, height: 10)
                                        .offset(x: -1, y: 1)
                                    }
                                }
                        }
                        .popover(isPresented: $showingNotifications) {
                            NotificationsDropdown()
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
                .toolbarBackground(.hidden, for:.navigationBar)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                            isShowingSplash = false
                        }
                    }

                    updateNotificationStatus()
                    isOnboardingPresented = !hasCompletedOnboarding || showOnboarding

                    if hasInitialLoadCompleted && !isRefreshing {
                        Task { await reloadFeed(showOverlay: true) }
                    }

                    if showSnow {
                        Task {
                            try? await Task.sleep(nanoseconds: 15_000_000_000)
                            await MainActor.run {
                                withAnimation(.easeIn(duration: 2.0)) {
                                    snowSystem.birthRate = 0
                                }
                            }
                        }
                    }
                }
                .onChange(of: showingNotifications) { _, isShowing in
                    if !isShowing {
                        updateNotificationStatus()
                    }
                }
                .onChange(of: hasCompletedOnboarding) {
                    isOnboardingPresented = !hasCompletedOnboarding || showOnboarding
                }
                .onChange(of: showOnboarding) {
                    isOnboardingPresented = !hasCompletedOnboarding || showOnboarding
                }
                .onChange(of: isOnboardingPresented) {
                    if !isOnboardingPresented {
                        hasCompletedOnboarding = true
                        showOnboarding = false
                    }
                }
                .fullScreenCover(isPresented: $isPresentingCreate, onDismiss: {
                    didDismissCreate = true
                }) {
                    NavigationStack {
                        DrawingView(onSave: { newItem in
                            dataModel.addItem(newItem)
                            viewModel.hasPostedToday = true
                        }, prompt: viewModel.dailyPrompt)
                    }
                }
                .onChange(of: didDismissCreate) {
                    if didDismissCreate {
                        didDismissCreate = false

                        Task {
                            let didSavePost = viewModel.hasPostedToday

                            if !didSavePost {
                                await viewModel.markDrawingAttempted()
                            }

                            await reloadFeed(showOverlay: true)

                            if didSavePost {
                                didJustPost = true
                            }
                        }
                    }
                }
                .onChange(of: didJustPost) { _, didPost in
                    if didPost {
                         DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation(.spring) {
                                actuallyShowStreakView = true
                            }
                            didJustPost = false
                        }
                    }
                }
                .task {
                    isInitialLoading = true
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await viewModel.loadDailyPrompt() }
                        group.addTask { await friendsViewModel.refreshFriends() }
                    }
                    await reloadFeed(showOverlay: true)
                    await syncMedalUsageFromBackend()
                    isInitialLoading = false
                    hasInitialLoadCompleted = true
                }
            }

            if isShowingSplash {
                ZStack {
                    Color.clear.overlay(
                        Image("blurred_background")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .edgesIgnoringSafeArea(.all)
                    .matchedGeometryEffect(id: "backgroundAnimation", in: launchAnimation)

                    GeometryReader { geo in
                        Image("brush_shadow")
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width * (horizontalSizeClass == .regular ? 0.49 : 0.745))
                            .matchedGeometryEffect(id: "logoAnimation", in: launchAnimation)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                            .offset(y: geo.size.height * -0.022)
                    }
                }
                .zIndex(5)
            }
        }
    }


    private func syncMedalUsageFromBackend() async {
        let usage = await AwardServiceFirebase.shared.fetchTodayUsage()
        await MainActor.run {
            dailyGoldAwarded = usage.gold
            dailySilverAwarded = usage.silver
            dailyBronzeAwarded = usage.bronze
        }
    }

    private func safeAreaInsetsTop() -> CGFloat {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        return keyWindow?.safeAreaInsets.top ?? 0
    }

    private func safeAreaInsetsBottom() -> CGFloat {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        return keyWindow?.safeAreaInsets.bottom ?? 0
    }

    private static func isWinter() -> Bool {
        let month = Calendar.current.component(.month, from: Date())
        return [11, 12, 1, 2].contains(month)
    }

    private static func createGentleSnow() -> VortexSystem {
        let system = VortexSystem(tags: ["circle"])

        system.position = [0.5, 0]
        system.shape = .box(width: 1, height: 0)
        system.birthRate = 10
        system.lifespan = 40
        system.speed = 0.05
        system.speedVariation = 0.02
        system.angle = .degrees(180)
        system.angleRange = .degrees(20)
        system.size = 0.25
        system.sizeVariation = 0.5
        system.sizeMultiplierAtDeath = 1

        return system
    }
}
