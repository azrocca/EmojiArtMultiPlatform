//
//  EmojiArtDocumentView.swift
//  EmojiArt
//
//  Created by Rocca on 7/27/21.
//

import SwiftUI

struct EmojiArtDocumentView: View {
    @ObservedObject var document: EmojiArtDocument
    
    @Environment(\.undoManager) var undoManager
    
    @State var selectedEmojis = Set<EmojiArtModel.Emoji>()
    
    @State var shakeEmojis = false {
        didSet {
            if shakeEmojis {
                shakeRotation = -DrawingConstants.shakeRotation
                withAnimation(shakingAnimation()) {
                    shakeRotation = DrawingConstants.shakeRotation
                }
            } else {
                withAnimation(shakingAnimation()) {
                    shakeRotation = 0
                }
            }
        }
    }
    
    @ScaledMetric var defaultEmojiFontSize: CGFloat = 40
    
    var body: some View {
        VStack(spacing: 0) {
            documentBody
            PaletteChooser(emojiFontSize: defaultEmojiFontSize)
        }
    }
    
    var documentBody: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white
                OptionalImage(uiImage: document.backgroundImage)
                    .scaleEffect(zoomScale)
                    .position(convertFromEmojiCoordinates((0,0), in: geometry))
                .gesture(doubleTapToZoom(in: geometry.size).exclusively(before: tapToDeselect()))
                if document.backgroundImageFetchStatus == .fetching {
                    ProgressView().scaleEffect(2)
                } else {
                    ForEach(document.emojis) { emoji in
                        ZStack(alignment: .center) {
                            let isEmojiSelected = selectedEmojis.contains(emoji)
                            let size = fontSize(for: emoji) * (isEmojiSelected ? emojiScale : zoomScale)
                            let panningEmojis = isEmojiSelected ? selectedEmojis : Set(arrayLiteral: emoji)
                            Text(emoji.text)
                                .overlay(isEmojiSelected ? textBorder : nil)
                                .overlay(isEmojiSelected && shakeEmojis ? removeButton.gesture(clickToDelete(emoji)) : nil)
                                .shakeEffect(shake: isEmojiSelected, rotation: shakeRotation)
                                // Assignment 5: Extra credit #2
                                .animatableSystemFont(size: size)
                                .position(position(for: emoji, in: geometry))
                                // Assignment 5: Extra credit #1
                                .gesture(tapToSelect(emoji).simultaneously(with: panEmojisGesture(for: panningEmojis)).simultaneously(with: holdToShake()))
                        }
                    }
                }
            }
            .clipped()
            .onDrop(of: [.utf8PlainText, .url, .image], isTargeted: nil) { providers, location in
                return drop(providers: providers, at: location, in: geometry)
            }
            .gesture(panGesture().simultaneously(with: pinchGesture()))
            .alert(item: $alertToShow) { alertToShow in
                alertToShow.alert()
            }
            .onChange(of: document.backgroundImageFetchStatus) { status in
                switch status {
                case .failed(let url):
                    showBackgroundImageFetchFailedAlert(url)
                default:
                    break
                }
            }
            .onReceive(document.$backgroundImage) { image in
                if autozoom {
                    zoomToFit(image, in: geometry.size)
                }
            }
            .compactableToolbar {
                AnimatedActionButton(title: "Paste Background", systemImage: "doc.on.clipboard") {
                    pasteBackground()
                }
                if Camera.isAvailable {
                    AnimatedActionButton(title: "Take Photo", systemImage: "camera") {
                        backgroundPicker = .camera
                    }
                }
                if PhotoLibrary.isAvailable {
                    AnimatedActionButton(title: "Search Photos", systemImage: "photo") {
                        backgroundPicker = .library
                    }
                }
                #if os(iOS)
                if let undoManager = undoManager {
                    if undoManager.canUndo {
                        AnimatedActionButton(title: undoManager.undoActionName, systemImage: "arrow.uturn.backward") {
                            undoManager.undo()
                        }
                    }
                    if undoManager.canRedo {
                        AnimatedActionButton(title: undoManager.redoActionName, systemImage: "arrow.uturn.forward") {
                            undoManager.redo()
                        }
                    }
                }
                #endif
            }
            .sheet(item: $backgroundPicker) { pickerType in
                switch pickerType {
                case .camera: Camera(handlePickedImage: { image in handlePickedBackgroundImage(image) })
                case .library: PhotoLibrary(handlePickedImage: { image in handlePickedBackgroundImage(image) })
                }
            }
        }
    }
    
    private func handlePickedBackgroundImage(_ image: UIImage?) {
        autozoom = true
        if let imageData = image?.imageData {
            document.setBackground(.imageData(imageData), undoManager: undoManager)
        }
        backgroundPicker = nil
    }
    
    @State private var backgroundPicker: BackgroundPickerType?
    
    enum BackgroundPickerType: Identifiable {
        case camera
        case library
        var id: BackgroundPickerType { self }
    }
    
    private func pasteBackground() {
        autozoom = true
        if let imageData = Pasteboard.imageData {
            document.setBackground(.imageData(imageData), undoManager: undoManager)
        } else if let url = Pasteboard.imageURL {
            document.setBackground(.url(url), undoManager: undoManager)
        } else {
            alertToShow = IdentifiableAlert(
                title: "Paste Background",
                message: "There is no image currently on the pasteboard."
            )
        }
    }
    
    @State private var autozoom = false
    
    @State private var alertToShow: IdentifiableAlert?
    
    private func showBackgroundImageFetchFailedAlert(_ url: URL) {
        alertToShow = IdentifiableAlert(id: "fetch failed: " + url.absoluteString) {
            Alert(
                title: Text("Background Image Fetch"),
                message: Text("Could not load image from \(url)"),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    @State var shakeRotation: Double = 0
    
    var textBorder: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: DrawingConstants.selectedEmojiBorderRadius)
                .strokeBorder(style: StrokeStyle(
                    lineWidth: DrawingConstants.selectedEmojiBorderWidth,
                    dash: DrawingConstants.selectedEmojiBorderDashSequence
                ))
                .foregroundColor(DrawingConstants.selectedEmojiBorderColor)
        }
    }
    
    var removeButton: some View {
        GeometryReader { geometry in
            Image(systemName: "xmark.circle.fill")
                .scaleEffect(DrawingConstants.shakingXscaleEffect)
                .position(CGPoint(x: geometry.size.width, y: 0))
        }
    }
    
    private func drop(providers: [NSItemProvider], at location: CGPoint, in geometry: GeometryProxy) -> Bool {
        var found = providers.loadObjects(ofType: URL.self) { url in
            autozoom = true
            document.setBackground(.url(url.imageURL), undoManager: undoManager)
        }
        #if os(iOS)
        if !found {
            found = providers.loadObjects(ofType: UIImage.self) { image in
                if let data = image.jpegData(compressionQuality: 1.0) {
                    autozoom = true
                    document.setBackground(.imageData(data), undoManager: undoManager)
                }
            }
        }
        #endif
        if !found {
            found = providers.loadObjects(ofType: String.self) { string in
                if let emoji = string.first, emoji.isEmoji {
                    document.addEmoji(
                        String(emoji),
                        at: convertToEmojiCoordinates(location, in: geometry),
                        size: defaultEmojiFontSize / zoomScale,
                        undoManager: undoManager
                    )
                }
            }
        }
        return found
    }
    
    private func position(for emoji: EmojiArtModel.Emoji, in geometry: GeometryProxy) -> CGPoint {
        var covertedCoordinates = convertFromEmojiCoordinates((emoji.x, emoji.y), in: geometry)
        // Assignment 5: Extra credit #1
        let isPanningEmoji = gesturePanEmoji.emojis.contains(emoji)
        
        covertedCoordinates.x += (isPanningEmoji ? gesturePanEmoji.offset.width * zoomScale : 0)
        covertedCoordinates.y += (isPanningEmoji ? gesturePanEmoji.offset.height * zoomScale : 0)
        
        return covertedCoordinates
    }
    
    private func convertToEmojiCoordinates(_ location: CGPoint, in geometry: GeometryProxy) -> (x: Int, y: Int) {
        let center = geometry.frame(in: .local).center
        let location = CGPoint(
            x: (location.x - panOffset.width - center.x) / zoomScale,
            y: (location.y - panOffset.height - center.y) / zoomScale
        )
        return (Int(location.x), Int(location.y))
    }
    
    private func convertFromEmojiCoordinates(_ location: (x: Int, y: Int), in geometry: GeometryProxy) -> CGPoint {
        let center = geometry.frame(in: .local).center
        let offset = CGSize(
            width: panOffset.width,
            height: panOffset.height
        )
        return CGPoint(
            x: center.x + CGFloat(location.x) * zoomScale + offset.width,
            y: center.y + CGFloat(location.y) * zoomScale + offset.height
        )
    }
    
    private func fontSize(for emoji: EmojiArtModel.Emoji) -> CGFloat {
        CGFloat(emoji.size)
    }
    
    // MARK: Panning gestures
    
    @SceneStorage("EmojiArtDocumentView.steadyStatePanOffset")
    private var steadyStatePanOffset = CGSize.zero
    @GestureState private var gesturePanOffset = CGSize.zero
    // Assignment 5: Extra credit #1
    @GestureState private var gesturePanEmoji = (offset: CGSize.zero, emojis: Set<EmojiArtModel.Emoji>())
    
    private var panOffset: CGSize {
        (steadyStatePanOffset + gesturePanOffset) * zoomScale
    }
    
    private func panGesture() -> some Gesture {
        DragGesture()
            .updating($gesturePanOffset) { latestDragGestureValue, gesturePanOffset, _ in
                gesturePanOffset = latestDragGestureValue.translation / zoomScale
            }
            .onEnded { finalDragGestureValue in
                steadyStatePanOffset = steadyStatePanOffset + (finalDragGestureValue.translation / zoomScale)
            }
    }
    
    // Assignment 5: Extra credit #1
    // converted GestureState to a tuple to contain both the offset and the emojis to pan
    private func panEmojisGesture(for emojis: Set<EmojiArtModel.Emoji>) -> some Gesture {
        DragGesture()
            .updating($gesturePanEmoji) { latestDragGestureValue, gesturePanEmoji, _ in
                gesturePanEmoji.emojis = emojis
                gesturePanEmoji.offset = latestDragGestureValue.translation / zoomScale
            }
            .onEnded { finalDragGestureValue in
                let scale = finalDragGestureValue.translation / zoomScale
                for emoji in emojis {
                    document.moveEmoji(emoji, by: scale, undoManager: undoManager)
                }
                resetSelectedEmojis()
            }
    }
    
    private func resetSelectedEmojis() {
        selectedEmojis = Set(selectedEmojis.map({ document.emojis[$0] }))
    }
    
    // MARK: Pinching gestures
    
    @SceneStorage("EmojiArtDocumentView.steadyStateZoomScale")
    private var steadyStateZoomScale: CGFloat = 1
    @GestureState private var gestureZoomScale: CGFloat = 1
    @GestureState private var gestureResizeScale: CGFloat = 1
    
    private var zoomScale: CGFloat {
        steadyStateZoomScale * gestureZoomScale
    }
    
    private var emojiScale: CGFloat {
        zoomScale * gestureResizeScale
    }
    
    private func pinchGesture() -> some Gesture {
        MagnificationGesture()
            .updating(selectedEmojis.isEmpty ? $gestureZoomScale : $gestureResizeScale) { latestGestureScale, scale, _ in
                scale = latestGestureScale
            }
            .onEnded { gestureScaleAtEnd in
                if selectedEmojis.isEmpty {
                    steadyStateZoomScale *= gestureScaleAtEnd
                } else {
                    updateSizeOfSelectedEmojis(by: gestureScaleAtEnd)
                }
            }
    }
    
    private func updateSizeOfSelectedEmojis(by scale: CGFloat) {
        selectedEmojis.forEach { emoji in
            document.scaleEmoji(emoji, by: scale, undoManager: undoManager)
        }
        // update selectedEmojis to stay in sync with document emojis
        selectedEmojis = Set(selectedEmojis.map({ document.emojis[$0] }))
    }
    
    // MARK: Tap gestures
    
    private func doubleTapToZoom(in size: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded { // called when finger comes up
                withAnimation {
                    zoomToFit(document.backgroundImage, in: size)
                }
            }
    }
    
    private func tapToDeselect() -> some Gesture {
        TapGesture(count: 1)
            .onEnded {
                // stop emojis from shaking
                shakeEmojis = false
                
                // remove all emoji IDs from selectedEmojis to deselect all
                selectedEmojis = []
            }
    }
    
    private func tapToSelect(_ emoji: EmojiArtModel.Emoji) -> some Gesture {
        TapGesture(count: 1)
            .onEnded {
                shakeEmojis = false
                selectedEmojis.toggleMembership(of: emoji)
            }
    }
    
    private func holdToShake() -> some Gesture {
        // want the ability to hold on an emoji to get it to start shaking.  Once shaking an "x" could be clicked to remove the emoji
        LongPressGesture()
            .onEnded {_ in
                shakeEmojis.toggle()
            }
    }
    
    private func clickToDelete(_ emoji: EmojiArtModel.Emoji) -> some Gesture {
        TapGesture(count: 1)
            .onEnded {
                shakeEmojis = false
                document.removeEmoji(emoji, undoManager: undoManager)
                selectedEmojis.remove(emoji)
            }
    }
    
    private func shakingAnimation() -> Animation {
        Animation.easeInOut(duration: DrawingConstants.shakeDuration).repeat(while: shakeEmojis)
    }
    
    private func zoomToFit(_ image: UIImage?, in size: CGSize) {
        if let image = image, image.size.width > 0, image.size.height > 0, size.width > 0, size.height > 0 {
            let hZoom = size.width / image.size.width
            let vZoom = size.height / image.size.height
            steadyStatePanOffset = .zero
            steadyStateZoomScale = min(hZoom, vZoom)
        }
    }
}

struct DrawingConstants {
    static let selectedEmojiBorderRadius: CGFloat = 5
    static let selectedEmojiBorderWidth: CGFloat = 1
    static let selectedEmojiBorderColor = Color.black
    static let selectedEmojiBorderDashSequence: [CGFloat] = [5, 5]
    static let shakeRotation: Double = 5
    static let shakeDuration: Double = 0.2
    static let shakingXscaleEffect: CGFloat = 0.4
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        EmojiArtDocumentView(document: EmojiArtDocument())
    }
}
