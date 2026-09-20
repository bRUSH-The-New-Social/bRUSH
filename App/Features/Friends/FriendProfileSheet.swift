import SwiftUI

struct FriendProfileSheet: View {
    @ObservedObject var vm: FriendsViewModel
    let profile: UserProfile
    
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            
            // MARK: - Layout Logic
            // 1. Add padding for shadows/stack visibility (30 on each side = 60 total)
            let horizontalPadding: CGFloat = 60
            
            // 2. Set a maximum width constraint
            let maxStackWidth: CGFloat = 340
            
            // 3. Calculate valid width
            let targetWidth = min(screenWidth - horizontalPadding, maxStackWidth)
            
            // 4. Calculate dimensions maintaining aspect ratio
            let (finalCardWidth, finalCardHeight) = calculateCardDimensions(
                maxWidth: targetWidth,
                maxHeight: screenHeight
            )
            
            let largeMedalSize = finalCardWidth * 0.16
            
            let isCurrentUser = profile.uid == vm.meUid
            
            let avatarFrameSize: CGFloat = 225
            let ovalFrameSize = (width: CGFloat(210), height: CGFloat(180))
            let popAmount: CGFloat = 60
            
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        ZStack(alignment: .bottom) {
                            let ovalClip = Ellipse()
                            
                            Image(profile.avatarBackground ?? "background_1")
                                .resizable()
                                .scaledToFill()
                                .frame(width: ovalFrameSize.width, height: ovalFrameSize.height)
                                .clipShape(ovalClip)
                                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                            
                            PoppingAvatarView(profile: profile, layer: .body)
                                .frame(width: avatarFrameSize, height: avatarFrameSize)
                                .frame(width: ovalFrameSize.width, height: ovalFrameSize.height, alignment: .bottom)
                                .clipShape(ovalClip)
                            
                            PoppingAvatarView(profile: profile, layer: .head)
                                .frame(width: avatarFrameSize, height: avatarFrameSize, alignment: .bottom)
                                .offset(y: -popAmount)
                        }
                        .offset(y: -50)
                        .padding(.bottom, -50)
                        
                        VStack(spacing: 2) {
                            Text([profile.firstName, profile.lastName].filter { !$0.isEmpty }.joined(separator: " "))
                                .font(.title2.bold())
                                .foregroundColor(.primary)
                            
                            Text("@\(profile.displayName)")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        
                        let isFriend = vm.friendIds.contains(profile.uid)
                        let isPending = vm.isRequestPending(uid: profile.uid)
                        let incomingReq = vm.requests.first(where: { $0.fromUid == profile.uid })
                        
                        VStack {
                            if !isCurrentUser {
                                if isFriend {
                                    Button(role: .destructive) {
                                        confirmRemove = true
                                    } label: {
                                        Label("Remove Friend", systemImage: "person.fill.xmark")
                                    }
                                    .buttonStyle(.glass)
                                    .tint(.red)
                                    .confirmationDialog(
                                        "Remove \(profile.displayName) as a friend?",
                                        isPresented: $confirmRemove,
                                        titleVisibility: .visible
                                    ) {
                                        Button("Remove", role: .destructive) {
                                            vm.remove(friendProfile: profile)
                                            dismiss()
                                        }
                                        Button("Cancel", role: .cancel) {}
                                    }
                                } else if let req = incomingReq {
                                    HStack(spacing: 12) {
                                        Button {
                                            Task { await vm.accept(req) }
                                        } label: {
                                            Text("Accept")
                                        }
                                        .buttonStyle(.glassProminent)
                                        
                                        Button {
                                            Task { await vm.decline(req) }
                                        } label: {
                                            Text("Decline")
                                        }
                                        .buttonStyle(.glass)
                                    }
                                    .padding(.horizontal, 40)
                                    
                                } else if isPending {
                                    Text("Request Pending")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                        .padding(12)
                                        .glassEffect()
                                } else {
                                    Button {
                                        let userToAdd = FriendSearchResult(
                                            uid: profile.uid,
                                            handle: profile.displayName,
                                            fullName: profile.firstName
                                        )
                                        vm.sendFriendRequest(to: userToAdd)
                                        dismiss()
                                    } label: {
                                        Label("Add Friend", systemImage: "person.badge.plus")
                                    }
                                    .buttonStyle(.glassProminent)
                                }
                            }
                        }
                        
                        CardStackView(cards: [
                            CardItem(content: AnyView(
                                AwardsStackCardView(
                                    cardTypeTitle: "Awards Accumulated",
                                    firstPlaceCount: profile.goldMedalsAccumulated,
                                    secondPlaceCount: profile.silverMedalsAccumulated,
                                    thirdPlaceCount: profile.bronzeMedalsAccumulated,
                                    medalIconSize: largeMedalSize,
                                    isCurrentUser: false
                                )
                            )),
                            CardItem(content: AnyView(
                                AwardsStackCardView(
                                    cardTypeTitle: "Awarded to Friends",
                                    firstPlaceCount: profile.goldMedalsAwarded,
                                    secondPlaceCount: profile.silverMedalsAwarded,
                                    thirdPlaceCount: profile.bronzeMedalsAwarded,
                                    medalIconSize: largeMedalSize,
                                    isCurrentUser: false
                                )
                            )),
                            CardItem(content: AnyView(
                                StreakCardView(
                                    streakCount: profile.streakCount,
                                    totalDrawings: profile.totalDrawingCount,
                                    memberSince: profile.memberSince,
                                    iconSize: largeMedalSize
                                )
                            ))
                        ])
                        .frame(width: finalCardWidth, height: finalCardHeight)
                        .padding(.bottom, 30)
                    }
                    .frame(width: screenWidth) // Ensure content centers properly
                }
                .presentationDetents([.large])
                .toolbar {
                    if !isCurrentUser {
                        ToolbarItem(placement: .topBarLeading) {
                            Menu {
                                Button(role: .destructive) {
                                    Task { try? await ModerationService.shared.report(reportedUserID: profile.uid, reason: "Inappropriate Profile") }
                                    dismiss()
                                } label: {
                                    Label("Report Profile", systemImage: "exclamationmark.bubble")
                                }
                                Button(role: .destructive) {
                                    Task { try? await ModerationService.shared.blockUser(blockedUserID: profile.uid) }
                                    vm.remove(friendProfile: profile) // Removes from friend list locally too
                                    dismiss()
                                } label: {
                                    Label("Block User", systemImage: "nosign")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
    
    private func calculateCardDimensions(maxWidth: CGFloat, maxHeight: CGFloat) -> (CGFloat, CGFloat) {
        let targetRatio: CGFloat = 1.25 // Height = Width * 1.25 (4:5 ratio)
        
        let heightFromWidth = maxWidth * targetRatio
        
        if heightFromWidth <= maxHeight {
            return (maxWidth, heightFromWidth)
        } else {
            let widthFromHeight = maxHeight * 0.8
            return (widthFromHeight, maxHeight)
        }
    }
}
