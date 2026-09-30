import SwiftUI

struct DrawingsGridView: View {
    @EnvironmentObject var dataModel: DataModel
    @State private var isAddingNewDrawing = false
    @State private var drawingPrompt = "What does your brain look like on a happy day?"
    
    @Namespace private var namespace
    @State private var selectedItem: Item? = nil
    
    @State private var isEditing = false
    @State private var selection = Set<UUID>()
    @State private var itemToDelete: Item? = nil
    @State private var showSingleDeleteAlert = false
    @State private var showMultiDeleteAlert = false
    
    @State private var itemsAnimatingDelete = Set<UUID>()
    
    @State private var isSharing = false
    @State private var itemsToShare: [Any] = []
    @State private var shareTrigger = 0
    
    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGray6)
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(dataModel.items) { item in
                            GridItemView(
                                namespace: namespace,
                                size: 100,
                                item: item,
                                isSelected: selection.contains(item.id),
                                isDeleting: itemsAnimatingDelete.contains(item.id),
                                onDeletionFinished: {
                                    withAnimation(.spring()) {
                                        dataModel.deleteItem(with: item.id)
                                        itemsAnimatingDelete.remove(item.id)
                                    }
                                }
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if isEditing {
                                        if selection.contains(item.id) {
                                            selection.remove(item.id)
                                        } else {
                                            selection.insert(item.id)
                                        }
                                    } else {
                                        selectedItem = item
                                    }
                                }
                            }
                            .contextMenu {
                                if !isEditing {
                                    Button {
                                        if let image = item.image {
                                            let itemSource = ImageActivityItemSource(title: item.prompt, image: image)
                                            itemsToShare = [itemSource]
                                            shareTrigger += 1
                                        }
                                    } label: {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    
                                    Button(role: .destructive) {
                                        itemToDelete = item
                                        showSingleDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            } preview: {
                                if let image = item.image {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                }
                            }
                        }
                    }
                    .padding()
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .navigationTitle("Past Drawings")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if selectedItem == nil {
                        ToolbarItem(placement: .navigationBarLeading) {
                            if !dataModel.items.isEmpty {
                                Button(isEditing ? "Done" : "Edit") {
                                    withAnimation {
                                        isEditing.toggle()
                                        selection.removeAll()
                                    }
                                }
                            }
                        }
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            if isEditing && !selection.isEmpty {
                                Button {
                                    let selectedItems = dataModel.items.filter { selection.contains($0.id) }
                                    let shareItems = selectedItems.compactMap { item -> ImageActivityItemSource? in
                                        guard let image = item.image else { return nil }
                                        return ImageActivityItemSource(title: item.prompt, image: image)
                                    }
                                    
                                    if !shareItems.isEmpty {
                                        itemsToShare = shareItems
                                        shareTrigger += 1
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                
                                Button(role: .destructive) {
                                    showMultiDeleteAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .tint(.red)
                                .confirmationDialog("Delete \(selection.count) Drawings", isPresented: $showMultiDeleteAlert) {
                                    Button("Delete", role: .destructive) {
                                        showMultiDeleteAlert = false
                                        triggerShredder(for: Array(selection))
                                        selection.removeAll()
                                        isEditing = false
                                    }
                                    .keyboardShortcut(.defaultAction)
                                } message: {
                                    Text("These drawings cannot be restored.")
                                }
                            }
                            if !isEditing {
                                // The "+" creates a drawing directly, bypassing the
                                // daily prompt flow. Keep it for demos on the simulator
                                // and debug builds only; hide it in production so users
                                // draw through the intended path.
                                #if DEBUG || targetEnvironment(simulator)
                                Button {
                                    isAddingNewDrawing = true
                                } label: {
                                    Image(systemName: "plus")
                                }
                                #endif
                            }
                        }
                    }
                }
                .fullScreenCover(isPresented: $isAddingNewDrawing) {
                    NavigationStack {
                        DrawingView(onSave: { newItem in
                            dataModel.addItem(newItem)
                        }, prompt: drawingPrompt)
                    }
                }
                
                if let selectedItem = selectedItem {
                    DrawingPreviewView(
                        namespace: namespace,
                        item: selectedItem,
                        selectedItem: $selectedItem
                    )
                    .ignoresSafeArea()
                    .zIndex(1)
                }
            }
            .sheet(isPresented: $isSharing, onDismiss: { itemsToShare = [] }) {
                ShareSheet(activityItems: itemsToShare)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: shareTrigger) { _ in
                if !itemsToShare.isEmpty {
                    isSharing = true
                }
            }
            .onAppear {
                selectedItem = nil
            }
            .modifier(SingleDeleteAlert(itemToDelete: $itemToDelete,
                                        isPresented: $showSingleDeleteAlert,
                                        onDelete: { item in
                                            triggerShredder(for: [item.id])
                                            itemToDelete = nil
                                        }))
        }
    }
    
    private func triggerShredder(for itemIDs: [UUID]) {
        withAnimation {
            itemsAnimatingDelete.formUnion(itemIDs)
        }
    }
}

/// Delete confirmation for a single drawing.
///
/// iOS 27 adds an `alert(_:item:)` overload that binds the alert directly to the
/// tapped item — one optional drives both presentation and the value handed to
/// the button — which avoids stale-`presenting:` edge cases. That symbol does
/// not exist in the iOS 26 SDK, so it can't be compiled here yet (an
/// `if #available` gate still requires the symbol at build time). When this
/// project builds against the iOS 27 SDK, swap the body for the gated version
/// documented below.
///
/// iOS 27 version to adopt once the SDK is available:
/// ```
/// if #available(iOS 27, *) {
///     content.alert("Delete Drawing", item: $itemToDelete) { item in
///         Button("Delete", role: .destructive) { onDelete(item) }
///             .keyboardShortcut(.defaultAction)
///         Button("Cancel", role: .cancel) { itemToDelete = nil }
///     } message: { _ in Text("This drawing cannot be restored.") }
/// } else { /* the isPresented+presenting body below */ }
/// ```
private struct SingleDeleteAlert: ViewModifier {
    @Binding var itemToDelete: Item?
    @Binding var isPresented: Bool
    let onDelete: (Item) -> Void

    func body(content: Content) -> some View {
        content.alert("Delete Drawing", isPresented: $isPresented, presenting: itemToDelete) { item in
            Button("Delete", role: .destructive) {
                onDelete(item)
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        } message: { _ in
            Text("This drawing cannot be restored.")
        }
    }
}
