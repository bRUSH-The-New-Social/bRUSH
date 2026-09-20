import SwiftUI

struct SignUpAvatarView: View {
    @ObservedObject var viewModel: SignUpViewModel
    @State private var selectedAvatarType: AvatarType = .personal
    @State private var selectedBackground = "background_1"
    @State private var selectedBody: String? = nil
    @State private var selectedShirt: String? = nil
    @State private var selectedEyes: String? = nil
    @State private var selectedMouth: String? = nil
    @State private var selectedHair: String? = nil
    @State private var selectedFacialHair: String? = nil
    @State private var selectedCategory = 0
    
    @EnvironmentObject private var rcService: RevenueCatService
    @State private var showingPaywall = false

    // Undo/Redo
    @State private var history: [AvatarParts] = []
    @State private var currentHistoryIndex = -1

    private static let removeOptionId = "__REMOVE__"

    private var categories: [String] {
        switch selectedAvatarType {
        case .personal:
            return ["Body", "Shirt", "Eyes", "Mouth", "Hair", "Facial Hair", "Background"]
        case .fun:
            return ["Face", "Eyes", "Mouth", "Hair", "Background"]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let isIpad = UIDevice.current.userInterfaceIdiom == .pad

            let avatarSize = min(screenWidth * 0.6, screenHeight * 0.35)
            
            // **CRITICAL FIX: Correct math for option size**
            let horizontalPadding = screenWidth * 0.05
            let columnsCount = isIpad ? 6 : (screenWidth > 400 ? 4 : 3)
            let gridSpacing = screenWidth * 0.03
            let columns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columnsCount)
            
            // Calculate total horizontal space used by padding and spacing
            let totalPadding = horizontalPadding * 2
            let totalSpacing = gridSpacing * CGFloat(columnsCount - 1)
            
            // The remaining width is divided by the number of columns
            let availableWidth = screenWidth - totalPadding - totalSpacing
            let optionSize = availableWidth / CGFloat(columnsCount) // This is the new, correct size

            VStack(spacing: 0) {
                // --- Header Bar ---
                HStack {
                    HStack(spacing: screenWidth * 0.03) {
                        Button(action: undo) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: screenWidth * 0.04, weight: .medium))
                                .foregroundColor(canUndo ? .blue : .gray)
                        }.disabled(!canUndo)

                        Button(action: redo) {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: screenWidth * 0.04, weight: .medium))
                                .foregroundColor(canRedo ? .blue : .gray)
                        }.disabled(!canRedo)
                    }

                    Spacer()

                    Text("Create Yourself")
                        .font(.system(size: screenWidth * 0.05, weight: .bold))

                    Spacer()

                    Button {
                        saveToHistory()
                        viewModel.selectedAvatar = AvatarParts(
                            avatarType: selectedAvatarType,
                            background: selectedBackground,
                            body: selectedBody,
                            shirt: selectedShirt,
                            eyes: selectedEyes,
                            mouth: selectedMouth,
                            hair: selectedHair,
                            facialHair: selectedFacialHair
                        )
                        Task { await viewModel.submitStep3() }
                    } label: {
                        HStack(spacing: screenWidth * 0.015) {
                            Image(systemName: "checkmark")
                                .font(.system(size: screenWidth * 0.035, weight: .semibold))
                            Text("Done")
                                .font(.system(size: screenWidth * 0.04, weight: .semibold))
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.green)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, screenHeight * 0.02)
                .padding(.bottom, screenHeight * 0.01)

                HStack(spacing: 5) {
                    ForEach(AvatarType.allCases, id: \.self) { avatarType in
                        Button {
                            saveToHistory()
                            selectedAvatarType = avatarType
                            resetSelections()
                        } label: {
                            Text(avatarType.displayName)
                                .font(.system(size: screenWidth * 0.04, weight: .medium))
                                .foregroundColor(selectedAvatarType == avatarType ? .white : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, screenHeight * 0.015)
                                .background(
                                    RoundedRectangle(cornerRadius: screenWidth * 0.02)
                                        .fill(selectedAvatarType == avatarType ? Color.accentColor : Color(.systemGray6))
                                )
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, screenHeight * 0.02)
                .animation(.easeInOut(duration: 0.3), value: selectedAvatarType)

                AvatarView(
                    avatarType: selectedAvatarType,
                    background: selectedBackground,
                    avatarBody: selectedBody,
                    shirt: selectedShirt,
                    eyes: selectedEyes,
                    mouth: selectedMouth,
                    hair: selectedHair,
                    facialHair: selectedFacialHair,
                    includeSpacer: false
                )
                .frame(width: avatarSize, height: avatarSize)
                .padding(.bottom, screenHeight * 0.03)

                // --- Category Selector ---
                categorySelector(screenWidth: screenWidth, screenHeight: screenHeight, horizontalPadding: horizontalPadding)

                // --- Options Grid ---
                ScrollView {
                    LazyVGrid(columns: columns, spacing: screenWidth * 0.04) {
                        ForEach(currentOptions, id: \.self) { option in
                            improvedOptionPreview(
                                option: option,
                                isLocked: isBackgroundLocked(option),
                                optionSize: optionSize,
                                screenWidth: screenWidth,
                                screenHeight: screenHeight
                            )
                            .onTapGesture {
                                if isBackgroundLocked(option) {
                                    showingPaywall = true
                                } else {
                                    updateSelection(option)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 3)
                    .padding(.bottom, 30)
                }
            }
            .sheet(isPresented: $showingPaywall) {
                ProPaywallView()
            }
            .onAppear { initializeHistory() }
        }
    }

    // MARK: - Subviews (Unchanged)

    private func categorySelector(screenWidth: CGFloat, screenHeight: CGFloat, horizontalPadding: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(0..<categories.count, id: \.self) { index in
                        Button {
                            selectedCategory = index
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(categories[index])
                                    .font(.system(size: screenWidth * 0.04, weight: .bold))
                                    .foregroundColor(selectedCategory == index ? .accentColor : .gray)
                                    .frame(minWidth: screenWidth * 0.2)
                                Rectangle()
                                    .fill(selectedCategory == index ? Color.accentColor : Color.clear)
                                    .frame(height: 3)
                                    .frame(width: screenWidth * 0.15)
                            }
                            .padding(.horizontal, screenWidth * 0.02)
                            .padding(.vertical, screenHeight * 0.01)
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
        .padding(.bottom, screenHeight * 0.02)
    }

    @ViewBuilder
    private func improvedOptionPreview(option: String, isLocked: Bool, optionSize: CGFloat, screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        let cornerRadius = screenWidth * 0.03
        let categoryName = (selectedCategory >= 0 && selectedCategory < categories.count) ? categories[selectedCategory] : "Background"
        
        let isBackgroundCategory = categoryName.lowercased().contains("background")
        let isBodyOrFaceCategory = categoryName.lowercased().contains("body") || categoryName.lowercased().contains("face")
        let isShirtCategory = categoryName.lowercased().contains("shirt")
        let isEyesCategory = categoryName.lowercased().contains("eyes")
        let isMouthCategory = categoryName.lowercased().contains("mouth")
        let isHairCategory = categoryName.lowercased().contains("hair")
        let isFacialHairCategory = categoryName.lowercased().contains("facial hair")
        
        ZStack {
            if option == Self.removeOptionId {
                VStack {
                    Image(systemName: "circle.slash.fill")
                        .font(.system(size: optionSize * 0.5, weight: .bold))
                        .foregroundColor(.orange)
                    Text("None")
                        .font(.system(size: screenWidth * 0.035, weight: .medium))
                        .foregroundColor(.gray)
                }
                .frame(width: optionSize, height: optionSize)
                .background(Color(.systemGray6))
            } else if isBackgroundCategory {
                Image(option)
                    .resizable()
                    .scaledToFill()
                    .frame(width: optionSize, height: optionSize)
                    .clipped()
            } else {
                let baseLayer: String? = isBodyOrFaceCategory ? option : selectedBody
                let shirtLayer: String? = isShirtCategory ? option : selectedShirt
                let eyesLayer: String? = isEyesCategory ? option : selectedEyes
                let mouthLayer: String? = isMouthCategory ? option : selectedMouth
                let hairLayer: String? = isHairCategory ? option : selectedHair
                let facialHairLayer: String? = isFacialHairCategory ? option : selectedFacialHair
                
                if let base = baseLayer {
                    Image(base)
                        .resizable()
                        .scaledToFit()
                        .frame(width: optionSize, height: optionSize)
                } else {
                    Color.clear.frame(width: optionSize, height: optionSize)
                }
                
                if selectedAvatarType == .personal, let shirt = shirtLayer {
                    Image(shirt)
                        .resizable()
                        .scaledToFit()
                        .frame(width: optionSize, height: optionSize)
                }
                
                if let eyes = eyesLayer {
                    Image(eyes)
                        .resizable()
                        .scaledToFit()
                        .frame(width: optionSize, height: optionSize)
                }

                if selectedAvatarType == .personal, let facialHair = facialHairLayer {
                    Image(facialHair)
                        .resizable()
                        .scaledToFit()
                        .frame(width: optionSize, height: optionSize)
                }
                
                if let mouth = mouthLayer {
                    Image(mouth)
                        .resizable()
                        .scaledToFit()
                        .frame(width: optionSize, height: optionSize)
                }
                
                if let hair = hairLayer {
                    Image(hair)
                        .resizable()
                        .scaledToFit()
                        .frame(width: optionSize, height: optionSize)
                }
            }

            if isLocked {
                Color.black.opacity(0.42)
                Image(systemName: "lock.fill")
                    .font(.system(size: optionSize * 0.28, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: optionSize, height: optionSize)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isSelected(option) ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(isSelected(option) ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected(option) ? 3 : 1)
        )
    }

    // MARK: - Logic (Unchanged)
    
    private func isBackgroundLocked(_ option: String) -> Bool {
        guard !rcService.isPro else { return false }
        guard selectedCategory < categories.count else { return false }
        return categories[selectedCategory].lowercased().contains("background") && option != "background_1"
    }

    private var currentOptions: [String] {
        let options: [String]
        switch selectedAvatarType {
        case .personal:
            switch selectedCategory {
            case 0: options = AvatarOptions.personalBodies
            case 1: options = AvatarOptions.personalShirts
            case 2: options = AvatarOptions.personalEyes
            case 3: options = AvatarOptions.personalMouths
            case 4: options = AvatarOptions.personalHairs
            case 5: options = AvatarOptions.personalFacialHairs
            case 6: options = AvatarOptions.personalBackgrounds
            default: return []
            }
        case .fun:
            switch selectedCategory {
            case 0: options = AvatarOptions.funFaces
            case 1: options = AvatarOptions.funEyes
            case 2: options = AvatarOptions.funMouths
            case 3: options = AvatarOptions.funHairs
            case 4: options = AvatarOptions.funBackgrounds
            default: return []
            }
        }

        if categories[selectedCategory].lowercased() != "background" {
            return [Self.removeOptionId] + options
        } else {
            return options
        }
    }

    private func resetSelections() {
        selectedBody = nil
        selectedShirt = nil
        selectedEyes = nil
        selectedMouth = nil
        selectedHair = nil
        selectedFacialHair = nil
        selectedCategory = 0
    }

    private func updateSelection(_ option: String) {
        saveToHistory()
        let newValue: String? = (option == Self.removeOptionId) ? nil : option

        switch selectedAvatarType {
        case .personal:
            switch selectedCategory {
            case 0: selectedBody = newValue
            case 1: selectedShirt = newValue
            case 2: selectedEyes = newValue
            case 3: selectedMouth = newValue
            case 4: selectedHair = newValue
            case 5: selectedFacialHair = newValue
            case 6: selectedBackground = option
            default: break
            }
        case .fun:
            switch selectedCategory {
            case 0: selectedBody = newValue
            case 1: selectedEyes = newValue
            case 2: selectedMouth = newValue
            case 3: selectedHair = newValue
            case 4: selectedBackground = option
            default: break
            }
        }
    }

    private func isSelected(_ option: String) -> Bool {
        if option == Self.removeOptionId {
            switch selectedAvatarType {
            case .personal:
                switch selectedCategory {
                case 0: return selectedBody == nil
                case 1: return selectedShirt == nil
                case 2: return selectedEyes == nil
                case 3: return selectedMouth == nil
                case 4: return selectedHair == nil
                case 5: return selectedFacialHair == nil
                case 6: return false
                default: return false
                }
            case .fun:
                switch selectedCategory {
                case 0: return selectedBody == nil
                case 1: return selectedEyes == nil
                case 2: return selectedMouth == nil
                case 3: return selectedHair == nil
                case 4: return false
                default: return false
                }
            }
        }
        
        switch selectedAvatarType {
        case .personal:
            switch selectedCategory {
            case 0: return selectedBody == option
            case 1: return selectedShirt == option
            case 2: return selectedEyes == option
            case 3: return selectedMouth == option
            case 4: return selectedHair == option
            case 5: return selectedFacialHair == option
            case 6: return selectedBackground == option
            default: return false
            }
        case .fun:
            switch selectedCategory {
            case 0: return selectedBody == option
            case 1: return selectedEyes == option
            case 2: return selectedMouth == option
            case 3: return selectedHair == option
            case 4: return selectedBackground == option
            default: return false
            }
        }
    }

    // MARK: - Undo/Redo (Unchanged)
    
    private var canUndo: Bool { currentHistoryIndex > 0 }
    private var canRedo: Bool { currentHistoryIndex < history.count - 1 }

    private var currentAvatarParts: AvatarParts {
        AvatarParts(
            avatarType: selectedAvatarType,
            background: selectedBackground,
            body: selectedBody,
            shirt: selectedShirt,
            eyes: selectedEyes,
            mouth: selectedMouth,
            hair: selectedHair,
            facialHair: selectedFacialHair
        )
    }

    private func initializeHistory() {
        let initial = currentAvatarParts
        history = [initial]
        currentHistoryIndex = 0
    }

    private func saveToHistory() {
        let state = currentAvatarParts
        history = Array(history.prefix(currentHistoryIndex + 1))
        history.append(state)
        currentHistoryIndex = history.count - 1

        if history.count > 20 {
            history.removeFirst()
            currentHistoryIndex -= 1
        }
    }

    private func undo() {
        guard canUndo else { return }
        currentHistoryIndex -= 1
        applyHistoryState()
    }

    private func redo() {
        guard canRedo else { return }
        currentHistoryIndex += 1
        applyHistoryState()
    }

    private func applyHistoryState() {
        let state = history[currentHistoryIndex]
        selectedAvatarType = state.avatarType
        selectedBackground = state.background
        selectedBody = state.body
        selectedShirt = state.shirt
        selectedEyes = state.eyes
        selectedMouth = state.mouth
        selectedHair = state.hair
        selectedFacialHair = state.facialHair
    }
}
