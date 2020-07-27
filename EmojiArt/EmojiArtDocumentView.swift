//
//  EmojiArtDocumentView.swift
//  EmojiArt
//
//  Created by James Byrne on 14/07/2020.
//  Copyright © 2020 jamesbyrne. All rights reserved.
//

import SwiftUI

struct EmojiArtDocumentView: View {
    @ObservedObject var document: EmojiArtDocument
    
    @State private var selectedEmojiIds = Set<Int>()
    
    @State private var chosenPalette: String = ""
    
    init(document: EmojiArtDocument) {
        self.document = document
        _chosenPalette = State(wrappedValue: self.document.defaultPalette)
    }
    
    var body: some View {
        VStack {
            HStack {
                PaletteChooser(document: document, chosenPalette: $chosenPalette)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(chosenPalette.map { String($0) }, id: \.self) { emoji in
                            Text(emoji)
                                .font(Font.system(size: self.defaultEmojiSize))
                                .onDrag { return NSItemProvider(object: emoji as NSString) }
                        }
                    }
                }
            }
            
            GeometryReader { geometry in
                ZStack {
                    Color.white.overlay(
                        OptionalImage(uiImage: self.document.backgroundImage)
                            .scaleEffect(self.zoomScale)
                            .offset(self.panOffset)
                    )
                        .gesture(self.doubleTapToZoom(in: geometry.size).exclusively(before: self.tapBackground()))
                    if self.isLoading {
                        Image(systemName: "hourglass").imageScale(.large).spinning()
                    } else {
                        ForEach(self.document.emojis) { emoji in
                            Text(emoji.text)
                                .font(animatableWithSize: self.emojiScale(emoji))
                                .opacity(self.selectedEmojiIds.contains(emoji.id) ? 0.5 : 1)
                                .position(self.position(for: emoji, in: geometry.size))
                                .gesture(self.tapEmoji(emoji))
                                .gesture(self.dragSelectedEmojis())
                                .gesture(self.longPressEmoji(emoji))
                        }
                    }
                    
                }
                .clipped()
                .gesture(self.panGesture())
                .gesture(self.zoomGesture())
                .edgesIgnoringSafeArea([.horizontal, .bottom])
                .onReceive(self.document.$backgroundImage) { image in
                    self.zoomToFit(image, in: geometry.size)
                }
                .onDrop(of: ["public.image", "public.text"], isTargeted: nil) { providers, location in
                    var location = geometry.convert(location, from: .global)
                    location = CGPoint(x: location.x - geometry.size.width/2, y: location.y - geometry.size.height/2)
                    location = CGPoint(x: location.x - self.panOffset.width, y: location.y - self.panOffset.height)
                    location = CGPoint(x: location.x / self.zoomScale, y: location.y / self.zoomScale)
                    return self.drop(providers: providers, at: location)
                }
                .navigationBarItems(trailing: Button(action: {
                    if let url = UIPasteboard.general.url, url != self.document.backgroundURL {
                        self.confirmBackgroundPaste = true
                    } else {
                        self.explainBackgroundPaste = true
                    }
                }, label: {
                    Image(systemName: "doc.on.clipboard").imageScale(.large)
                        .alert(isPresented: self.$explainBackgroundPaste) {
                            return Alert(
                                title: Text("Paste Background"),
                                message: Text("Copy the URL of an image to the clip board and touch this button to make it the background of your document."),
                                dismissButton: .default(Text("OK"))
                            )
                        }
                }))
            }
            .zIndex(-1)
        }
        .alert(isPresented: self.$confirmBackgroundPaste) {
            return Alert(
                title: Text("Paste Background"),
                message: Text("Replace your background with \(UIPasteboard.general.url?.absoluteString ?? "nothing")?"),
                primaryButton: .default(Text("OK")) {
                    self.document.backgroundURL = UIPasteboard.general.url
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    @State private var explainBackgroundPaste = false
    @State private var confirmBackgroundPaste = false
    
    var isLoading: Bool {
        document.backgroundURL != nil && document.backgroundImage == nil
    }
    
    private func longPressEmoji(_ emoji: EmojiArt.Emoji) -> some Gesture {
        LongPressGesture(minimumDuration: 1)
            .onEnded { _ in
                print("long press")
                withAnimation {
                    self.document.removeEmoji(emoji)
                }
            }
    }
    
    @GestureState private var gestureEmojiPanOffset: CGSize = .zero
    
    private func emojiLocation(_ emoji: EmojiArt.Emoji) -> CGPoint {
        if selectedEmojiIds.contains(emoji.id) {
            return emoji.location + gestureEmojiPanOffset
        } else {
            return emoji.location
        }
    }
    
    private func dragSelectedEmojis() -> some Gesture {
        return DragGesture()
            .updating($gestureEmojiPanOffset) { latestDrageGestureValue, gestureEmojiPanOffset, transaction in
                gestureEmojiPanOffset = latestDrageGestureValue.translation / self.zoomScale
            }
            .onEnded { finalDrageGestureValue in
                for emoji in self.document.emojis.filter({ emoji in self.selectedEmojiIds.contains(emoji.id) }) {
                    self.document.moveEmoji(emoji, by: (finalDrageGestureValue.translation / self.zoomScale))
                }
            }
    }
    
    private func tapEmoji(_ emoji: EmojiArt.Emoji) -> some Gesture {
        TapGesture()
            .onEnded {
                withAnimation {
                    if self.selectedEmojiIds.contains(emoji.id) {
                        self.selectedEmojiIds.remove(emoji.id)
                    } else {
                        self.selectedEmojiIds.insert(emoji.id)
                    }
                }
            }
    }
    
    private func tapBackground() -> some Gesture {
        TapGesture()
            .onEnded {
                withAnimation {
                    self.selectedEmojiIds = Set<Int>()
                }
            }
    }
    
    @GestureState private var gestureDocZoomScale: CGFloat = 1.0
    
    @GestureState private var gestureEmojiZoomScale: CGFloat = 1.0
    
    private func emojiScale(_ emoji: EmojiArt.Emoji) -> CGFloat {
        return emoji.fontSize * self.zoomScale * CGFloat(selectedEmojiIds.contains(emoji.id) ? gestureEmojiZoomScale : 1)
    }
    
    private var zoomScale: CGFloat {
        document.steadyStateDocZoomScale * gestureDocZoomScale
    }
    
    private func zoomGesture() -> some Gesture {
        if selectedEmojiIds.isEmpty {
            return MagnificationGesture()
                .updating($gestureDocZoomScale) { latestGestureScale, gestureStateInOut, transaction in
                    gestureStateInOut = latestGestureScale
                }
                .onEnded { finalGestureScale in
                    self.document.steadyStateDocZoomScale = finalGestureScale
                }
        } else {
            return MagnificationGesture()
                .updating($gestureEmojiZoomScale) { latestGestureScale, gestureStateInOut, transaction in
                    gestureStateInOut = latestGestureScale
                }
                .onEnded { finalGestureScale in
                    for emoji in self.document.emojis.filter({ emoji in self.selectedEmojiIds.contains(emoji.id) }) {
                        self.document.scaleEmoji(emoji, by: finalGestureScale)
                    }
                }
        }
    }
    
    @GestureState private var gesturePanOffset: CGSize = .zero
    
    private var panOffset: CGSize {
        (document.steadyStatePanOffset + gesturePanOffset) * zoomScale
    }
    
    private func panGesture() -> some Gesture {
        DragGesture()
            .updating($gesturePanOffset) { latestDragGestureValue, gesturePanOffset, transaction in
                gesturePanOffset = latestDragGestureValue.translation / self.zoomScale
            }
            .onEnded { finalDragGestureValue in
                self.document.steadyStatePanOffset = self.document.steadyStatePanOffset + (finalDragGestureValue.translation / self.zoomScale)
            }
    }
    
    private func doubleTapToZoom(in size: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation {
                    self.zoomToFit(self.document.backgroundImage, in: size)
                }
            }
    }
    
    private func zoomToFit(_ image: UIImage?, in size: CGSize) {
        if let image = image, image.size.width > 0, image.size.height > 0, size.width > 0, size.height > 0 {
            let hZoom = size.width / image.size.width
            let vZoom = size.height / image.size.height
            self.document.steadyStateDocZoomScale = min(hZoom, vZoom)
        }
    }
    
    private func position(for emoji: EmojiArt.Emoji, in size: CGSize) -> CGPoint {
        var location = emojiLocation(emoji)
        location = CGPoint(x: location.x * document.steadyStateDocZoomScale, y: location.y * document.steadyStateDocZoomScale)
        location = CGPoint(x: location.x + size.width/2, y: location.y + size.height/2)
        location = CGPoint(x: location.x + panOffset.width, y: location.y + panOffset.height)
        
        return location
    }
    
    private func drop(providers: [NSItemProvider], at location: CGPoint) -> Bool {
        var found = providers.loadFirstObject(ofType: URL.self) { url in
            self.document.backgroundURL = url
        }
        if !found {
            found = providers.loadObjects(ofType: String.self) { string in
                self.document.addEmoji(string, at: location, size: self.defaultEmojiSize / self.zoomScale)
            }
        }
        return found
    }
    
    private let defaultEmojiSize: CGFloat = 40
}
