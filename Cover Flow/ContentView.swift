//
//  ContentView.swift
//  Cover Flow
//
//  Created by Tamara Osseiran on 6/6/25.
//

import SwiftUI
import SwiftData
import UIImageColors

@Model
final class Album {
    var title: String
    var artist: String
    var coverImage: String
    var year: Int
    
    init(title: String, artist: String, coverImage: String, year: Int) {
        self.title = title
        self.artist = artist
        self.coverImage = coverImage
        self.year = year
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var albums: [Album]
    @StateObject private var spotifyService = SpotifyService()
    @State private var selectedAlbum: Album?
    @State private var isScrubberActive = false
    @State private var scrubberActiveTask: DispatchWorkItem?
    @State private var scrubberHighlightOffset: Int = 0
    @State private var scrubberHighlightResetTask: DispatchWorkItem?
    @State private var albumColors: [String: UIImageColors] = [:]
    @State private var animateGradient = false
    @State private var gradientAngle: Double = 0
    @State private var albumTilt: CGSize = .zero
    @State private var isRapidTransition = false
    @State private var rapidTransitionTask: DispatchWorkItem?
    @State private var flippedAlbum: Album? = nil
    @State private var flipAngle: Double = 0
    @Namespace private var flipNamespace
    @State private var dragOffset: CGFloat = 0
    @Namespace private var albumNamespace

    var body: some View {
        ZStack {
            // Dynamic background gradient
            let gradientColors: [Color] = {
                if let selected = selectedAlbum, let colors = albumColors[selected.coverImage] {
                    return [Color(colors.background), Color(colors.primary)]
                } else {
                    return [Color.black.opacity(0.8), Color.black]
                }
            }()
            // Map tilt to gradient direction and hue
            let tiltX = albumTilt.width.clamped(to: -1...1)
            let tiltY = albumTilt.height.clamped(to: -1...1)
            let startPoint = UnitPoint(x: 0.5 - tiltX * 0.18, y: 0.0 + tiltY * 0.12)
            let endPoint = UnitPoint(x: 0.5 + tiltX * 0.18, y: 1.0 - tiltY * 0.12)
            LinearGradient(
                colors: gradientColors,
                startPoint: startPoint,
                endPoint: endPoint
            )
            .hueRotation(.degrees(gradientAngle + tiltX * 10))
            .animation(.easeInOut(duration: 0.5), value: albumTilt)
            .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: animateGradient)
            .ignoresSafeArea()
            
            Color.black.opacity(0.3).ignoresSafeArea()
            
            // Add a dark gradient overlay at the bottom for contrast
            VStack {
                Spacer()
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.black.opacity(0.0), location: 0.5),
                        .init(color: Color.black.opacity(0.18), location: 0.85),
                        .init(color: Color.black.opacity(0.24), location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
            }
            
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    if spotifyService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(height: 350)
                    } else if let errorMessage = spotifyService.errorMessage {
                        Text("Error: \(errorMessage)")
                            .foregroundColor(.red)
                            .padding()
                            .frame(height: 350)
                    } else if spotifyService.albums.isEmpty {
                        Text("No albums found.")
                            .foregroundColor(.white)
                            .padding()
                            .frame(height: 350)
                    } else {
                        // Cover Flow carousel with advanced snap effect
                        CoverFlowView(
                            albums: spotifyService.albums,
                            selectedAlbum: $selectedAlbum,
                            onUserInteraction: {
                                activateScrubber()
                            },
                            onScroll: { direction in
                                updateScrubberHighlightOffset(direction)
                            },
                            onAlbumTilt: { tilt in
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    albumTilt = tilt
                                }
                            },
                            onSwipeUp: { album in
                                guard flippedAlbum == nil else { return }
                                flippedAlbum = album
                            },
                            albumNamespace: albumNamespace,
                            flippedAlbum: $flippedAlbum
                        )
                        .frame(height: 350)
                        // Album info close below the album cover
                        ZStack {
                            if let selected = selectedAlbum {
                                VStack(spacing: 8) {
                                    Text(selected.title.replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression))
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .multilineTextAlignment(.center)
                                    Text(selected.artist)
                                        .font(.title2)
                                        .foregroundColor(.white.opacity(0.7))
                                    Text(String(selected.year))
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .padding(.top, 6)
                                .id(selected.year)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: selected.year)
                                .blur(radius: isRapidTransition ? 8 : 0)
                                .opacity(isRapidTransition ? 0.2 : 1.0)
                            }
                        }
                        .frame(height: 100)
                    }
                }
                Spacer()
                HStack {
                    WaveformScrubberBar(
                        albums: spotifyService.albums,
                        selectedIndex: selectedAlbum.flatMap { album in spotifyService.albums.firstIndex(where: { $0.id == album.id }) } ?? 0,
                        onSelect: { index in
                            NotificationCenter.default.post(name: .scrubberJumpToIndex, object: index)
                            activateScrubber()
                        },
                        onUserInteraction: {
                            activateScrubber()
                        },
                        isActive: isScrubberActive,
                        isRapidTransition: isRapidTransition,
                        onRapidScrub: { handleRapidTransition() }
                    )
                    .frame(height: 24)
                    .padding(.horizontal, 24)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .onEnded { _ in activateScrubber() }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: .bottom)
            
            // Fullscreen Tracklist Overlay with matchedGeometryEffect
            if let flipped = flippedAlbum {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea().blur(radius: 8)
                    VStack(spacing: 0) {
                        // Album cover expands to fullscreen
                        AsyncImage(url: URL(string: flipped.coverImage)) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .matchedGeometryEffect(id: flipped.id, in: albumNamespace)
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.top, 48)
                        Text(flipped.title)
                            .font(.title2).fontWeight(.bold).foregroundColor(.white).padding(.top, 8)
                        Text("\(flipped.artist) • \(flipped.year)")
                            .font(.subheadline).foregroundColor(.white.opacity(0.7)).padding(.bottom, 8)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(1...10, id: \.self) { i in
                                    HStack {
                                        Text("Track \(i)")
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "play.fill").foregroundColor(.white.opacity(0.7))
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.top, 8)
                        }
                        .frame(maxHeight: 320)
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                    flippedAlbum = nil
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white.opacity(0.85))
                                    .padding()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.85).ignoresSafeArea())
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale), removal: .opacity))
                    .zIndex(100)
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if value.translation.height > 80 {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                        flippedAlbum = nil
                                    }
                                }
                            }
                    )
                }
            }
        }
        .onAppear {
            print("[DEBUG] On appear. Current album count: \(spotifyService.albums.count)")
            Task {
                await spotifyService.fetchIndieRockAlbums()
                print("[DEBUG] After fetch. Album count: \(spotifyService.albums.count)")
            }
            animateGradient = true
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: true)) {
                gradientAngle = 30
            }
        }
        .onChange(of: selectedAlbum) { _, newValue in
            guard let album = newValue else { return }
            extractColors(for: album)
            withAnimation(.easeInOut(duration: 1.2)) {
                gradientAngle += 60
            }
        }
    }
    
    // Helper to activate and auto-idle the scrubber
    private func activateScrubber() {
        if isScrubberActive { return }
        scrubberActiveTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isScrubberActive = true
        }
        let task = DispatchWorkItem {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) {
                isScrubberActive = false
            }
        }
        scrubberActiveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: task)
    }
    
    // Update highlight offset only in response to user interaction
    private func updateScrubberHighlightOffset(_ direction: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            scrubberHighlightOffset = direction.clamped(to: -5...5)
        }
    }
    
    // Extract colors from album cover image if not already cached
    private func extractColors(for album: Album) {
        guard albumColors[album.coverImage] == nil,
              let url = URL(string: album.coverImage), album.coverImage.hasPrefix("http") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            let colors = image.getColors()
            DispatchQueue.main.async {
                albumColors[album.coverImage] = colors
            }
        }.resume()
    }
    
    // Add this function near your other helper functions
    private func handleRapidTransition() {
        rapidTransitionTask?.cancel()
        withAnimation(.easeInOut(duration: 0.1)) {
            isRapidTransition = true
        }
        let task = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRapidTransition = false
            }
        }
        rapidTransitionTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: task)
    }
}

struct CoverFlowView: View {
    let albums: [Album]
    @Binding var selectedAlbum: Album?
    var onUserInteraction: (() -> Void)? = nil
    var onScroll: ((Int) -> Void)? = nil
    var onAlbumTilt: ((CGSize) -> Void)? = nil
    var onSwipeUp: ((Album) -> Void)? = nil
    var albumNamespace: Namespace.ID
    @Binding var flippedAlbum: Album?
    @State private var selectedIndex: Int = 0
    @State private var scrollOffset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0
    
    let itemWidth: CGFloat = 200
    let itemSpacing: CGFloat = 4
    let maxRotation: Double = 35 // subtle, classic effect
    let minScale: CGFloat = 0.8
    let minOpacity: Double = 0.5
    let maxTilt: Double = 12 // degrees for 3D tilt
    let maxParallax: CGFloat = 24 // px for parallax

    var body: some View {
        GeometryReader { geometry in
            let center = geometry.size.width / 2
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: itemSpacing) {
                    ForEach(albums.indices, id: \.self) { index in
                        let xPosition = CGFloat(index) * (itemWidth + itemSpacing)
                        let itemCenter = xPosition - scrollOffset + itemWidth / 2
                        let distance = (itemCenter - center) / (itemWidth + itemSpacing)
                        let rotation = -Double(distance) * maxRotation
                        let scale = selectedIndex == index ? 1.25 + 0.05 * abs(dragOffset / 100) : max(minScale, 1.0 - abs(distance) * 0.2)
                        let opacity = max(minOpacity, 1.0 - abs(distance) * 0.3)
                        let isFocused = selectedIndex == index
                        let tilt = isFocused ? Double(dragOffset / 12).clamped(to: -maxTilt...maxTilt) : rotation
                        let parallax = isFocused ? (dragOffset / 4).clamped(to: -maxParallax...maxParallax) : 0
                        let anchor: UnitPoint = .center
                        AlbumCoverView(
                            album: albums[index],
                            parallax: parallax,
                            isFocused: isFocused,
                            onTilt: { tilt in
                                if isFocused { onAlbumTilt?(tilt) }
                            }
                        )
                            .frame(width: itemWidth, height: 200)
                            .scaleEffect(scale)
                            .opacity(opacity)
                            .rotation3DEffect(
                                .degrees(tilt),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: anchor
                            )
                            .zIndex(isFocused ? 1 : 0)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                TapGesture().onEnded {
                                    print("Tapped album \(index), isFocused: \(isFocused)")
                                    if isFocused {
                                        onSwipeUp?(albums[index])
                                    } else {
                                        withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.7)) {
                                            let targetOffset = CGFloat(index) * (itemWidth + itemSpacing)
                                            scrollOffset = targetOffset
                                            selectedIndex = index
                                            if albums.indices.contains(index) {
                                                selectedAlbum = albums[index]
                                            }
                                            triggerHaptic()
                                            onUserInteraction?()
                                        }
                                    }
                                }
                            )
                    }
                }
                .padding(.horizontal, (geometry.size.width - itemWidth) / 2)
            }
            .content.offset(x: -scrollOffset + dragOffset)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.width
                    }
                    .onEnded { value in
                        let drag = -value.translation.width
                        let estimatedOffset = scrollOffset + drag
                        let item = (estimatedOffset / (itemWidth + itemSpacing)).rounded()
                        let newIndex = min(max(Int(item), 0), albums.count - 1)
                        let direction = Int((CGFloat(newIndex) - CGFloat(selectedIndex)).clamped(to: -5...5))
                        withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.7)) {
                            let targetOffset = CGFloat(newIndex) * (itemWidth + itemSpacing)
                            scrollOffset = targetOffset
                            selectedIndex = newIndex
                            if albums.indices.contains(newIndex) {
                                selectedAlbum = albums[newIndex]
                            }
                            triggerHaptic()
                            onUserInteraction?()
                        }
                        onScroll?(direction)
                    }
            )
            .onAppear {
                // Center the first album
                scrollOffset = 0
                selectedIndex = 0
                if !albums.isEmpty {
                    selectedAlbum = albums[0]
                }
                // Always add NotificationCenter observer
                NotificationCenter.default.addObserver(forName: .scrubberJumpToIndex, object: nil, queue: .main) { notif in
                    if let jumpIndex = notif.object as? Int, albums.indices.contains(jumpIndex) {
                        withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.7)) {
                            let targetOffset = CGFloat(jumpIndex) * (itemWidth + itemSpacing)
                            scrollOffset = targetOffset
                            selectedIndex = jumpIndex
                            selectedAlbum = albums[jumpIndex]
                            triggerHaptic()
                            onUserInteraction?()
                        }
                    }
                }
            }
        }
    }
    
    private func triggerHaptic() {
        #if canImport(UIKit)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           windowScene.activationState == .foregroundActive {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        #endif
    }
}

fileprivate extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

struct AlbumCoverView: View {
    let album: Album
    var parallax: CGFloat = 0
    var isFocused: Bool = false
    var onTilt: ((CGSize) -> Void)? = nil
    // For interactive tilt
    @State private var dragOffset: CGSize = .zero
    @GestureState private var isDragging: Bool = false
    @State private var viewSize: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.modelContext) private var modelContext
    @State private var dominantColor: Color = .white
    @State private var albumColors: [String: UIImageColors] = [:]
    
    var body: some View {
        let maxTilt: Double = 15
        let dragScale: CGFloat = isDragging ? 1.03 : 1.0
        let totalScale = dragScale
        // Normalize drag offset to [-1, 1] based on view size
        let normX: Double = viewSize.width > 0 ? Double((dragOffset.width / (viewSize.width / 2)).clamped(to: -1...1)) : 0
        let normY: Double = viewSize.height > 0 ? Double((dragOffset.height / (viewSize.height / 2)).clamped(to: -1...1)) : 0
        let xTilt = normX * maxTilt
        let yTilt = -normY * maxTilt
        // Dynamic shadow based on tilt
        let tiltAmount = min(1.0, sqrt(normX * normX + normY * normY))
        let dynamicShadowRadius = 32 + tiltAmount * 16
        let dynamicShadowOpacity = 0.22 + tiltAmount * 0.18
        // Calculate glow position and intensity
        let glowStrength = min(1.0, sqrt(normX * normX + normY * normY))
        let glowOffsetX = CGFloat(normX) * 60
        let glowOffsetY = CGFloat(normY) * 60
        // Use albumColors if available, else fallback to white
        let glowColor: Color = .white
        ZStack {
            // Album art only, no border/overlay
            Group {
                if album.coverImage.hasPrefix("http") {
                    AsyncImage(url: URL(string: album.coverImage)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .opacity(1.0)
                    } placeholder: {
                        ProgressView()
                    }
                } else {
                    Image(systemName: album.coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .foregroundColor(.white)
                        .opacity(1.0)
                }
            }
            // Dynamic color-matched glow overlay
            if isFocused {
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: glowColor.opacity(0.32 * glowStrength + 0.08), location: 0.0),
                        .init(color: glowColor.opacity(0.12 * glowStrength), location: 0.6),
                        .init(color: .clear, location: 1.0)
                    ]),
                    center: .center,
                    startRadius: 40,
                    endRadius: 220
                )
                .blur(radius: 16)
                .blendMode(.plusLighter)
                .offset(x: glowOffsetX, y: glowOffsetY)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)
            }
        }
        .frame(width: 240, height: 240)
        .shadow(
            color: Color.black.opacity(dynamicShadowOpacity),
            radius: dynamicShadowRadius,
            x: -xTilt * 1.2,
            y: -yTilt * 1.2 + 8
        )
        .overlay(
            LinearGradient(
                gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.18)]),
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .scaleEffect(totalScale)
        .rotation3DEffect(
            .degrees(xTilt),
            axis: (x: 0, y: 1, z: 0), anchor: .center
        )
        .rotation3DEffect(
            .degrees(yTilt),
            axis: (x: 1, y: 0, z: 0), anchor: .center
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isFocused)
        .animation(.easeOut(duration: 0.2), value: dragOffset)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in viewSize = newSize }
            }
        )
        .gesture(
            isFocused ? DragGesture(minimumDistance: 0)
                .updating($isDragging) { _, state, _ in state = true }
                .onChanged { value in
                    dragOffset = value.translation
                    // Notify parent of tilt here
                    let normX = viewSize.width > 0 ? Double((value.translation.width / (viewSize.width / 2)).clamped(to: -1...1)) : 0
                    let normY = viewSize.height > 0 ? Double((value.translation.height / (viewSize.height / 2)).clamped(to: -1...1)) : 0
                    onTilt?(CGSize(width: normX, height: normY))
                }
                .onEnded { _ in
                    withAnimation(.interpolatingSpring(stiffness: 180, damping: 18)) {
                        dragOffset = .zero
                    }
                    onTilt?(.zero)
                }
            : nil
        )
        // Move album down to avoid notch
        .padding(.top, 32)
        .onAppear {
            // Try to extract album color if not already present
            if albumColors[album.coverImage] == nil,
               let url = URL(string: album.coverImage), album.coverImage.hasPrefix("http") {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    let colors = image.getColors()
                    DispatchQueue.main.async {
                        albumColors[album.coverImage] = colors
                    }
                }.resume()
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Album.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    ContentView()
        .environment(\.modelContext, context)
}

// ScrubberBar

struct WaveformScrubberBar: View {
    let albums: [Album]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    var onUserInteraction: (() -> Void)? = nil
    var isActive: Bool = false
    var isRapidTransition: Bool = false
    var onRapidScrub: (() -> Void)? = nil
    private let barCount: Int = 28
    private let idleMinHeight: CGFloat = 16
    private let idleMaxHeight: CGFloat = 18
    private let idleMinOpacity: Double = 0.12
    private let idleMaxOpacity: Double = 0.22
    private let idleMinWidth: CGFloat = 1
    private let idleMaxWidth: CGFloat = 1
    private let activeMinHeight: CGFloat = 20
    private let activeMaxHeight: CGFloat = 22
    private let activeMinOpacity: Double = 0.22
    private let activeMaxOpacity: Double = 0.7
    private let activeMinWidth: CGFloat = 1.5
    private let activeMaxWidth: CGFloat = 1.5
    @GestureState private var dragBar: Int? = nil
    @State private var dragActiveBar: Int? = nil
    @State private var animatingToCenter = false
    @State private var showLabel = false
    @State private var isHighlightActive = false
    @Namespace private var labelNamespace
    
    var body: some View {
        let count = albums.count
        // Map each bar to a proportional album index
        let barToAlbumIndex: [Int] = (0..<barCount).map { bar in
            Int(round(Double(bar) / Double(barCount - 1) * Double(count - 1)))
        }
        // The highlight bar is the one whose mapped album index matches selectedIndex
        let highlightBar = barToAlbumIndex.firstIndex(of: selectedIndex) ?? 0
        let minHeight = isActive ? activeMinHeight : idleMinHeight
        let maxHeight = isActive ? activeMaxHeight : idleMaxHeight
        let minWidth = isActive ? activeMinWidth : idleMinWidth
        let maxWidth = isActive ? activeMaxWidth : idleMaxWidth
        GeometryReader { geo in
            let width = geo.size.width
            let barSpacing = width / CGFloat(barCount)
            ZStack(alignment: .bottomLeading) {
                ForEach(0..<barCount, id: \ .self) { bar in
                    let albumIndex = barToAlbumIndex[bar]
                    let dist = abs(bar - highlightBar)
                    let waveSpread = 6.0
                    let norm = min(Double(dist) / waveSpread, 1.0)
                    let height = minHeight + (maxHeight - minHeight) * CGFloat(1.0 - pow(norm, 2.5))
                    let isCenter = bar == highlightBar
                    let barWidth = isCenter ? maxWidth : minWidth
                    let whiteness = 1.0 - pow(norm, 2.5) // sharper falloff for color too
                    let color: Color = {
                        if isActive {
                            if isCenter {
                                return .white
                            } else {
                                return Color.gray.opacity(0.3 + 0.5 * whiteness)
                            }
                        } else {
                            return Color.gray.opacity(0.3)
                        }
                    }()
                    Rectangle()
                        .fill(color)
                        .frame(width: barWidth, height: height)
                        .cornerRadius(1)
                        .shadow(color: isCenter && isActive ? Color.white.opacity(0.8) : .clear, radius: isCenter ? 8 : 0, x: 0, y: 0)
                        .scaleEffect(isCenter && (showLabel || isHighlightActive) ? 1.2 : 1.0, anchor: .bottom)
                        .animation(.spring(response: 2.0, dampingFraction: 0.8), value: highlightBar)
                        .contentShape(Rectangle())
                        .position(x: barSpacing * CGFloat(bar) + barSpacing / 2, y: maxHeight - height / 2)
                        .onTapGesture {
                            onSelect(albumIndex)
                            onUserInteraction?()
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragBar) { value, state, _ in
                            let x = max(0, min(value.location.x, width - 1))
                            let bar = Int((x / width) * CGFloat(barCount))
                            let albumIndex = barToAlbumIndex[min(bar, barCount - 1)]
                            state = albumIndex
                        }
                        .onChanged { value in
                            let x = max(0, min(value.location.x, width - 1))
                            let bar = Int((x / width) * CGFloat(barCount))
                            let albumIndex = barToAlbumIndex[min(bar, barCount - 1)]
                            isHighlightActive = true
                            dragActiveBar = bar
                            withAnimation(.easeInOut(duration: 0.15)) { showLabel = true }
                            onSelect(albumIndex)
                            onUserInteraction?()
                            onRapidScrub?()
                        }
                        .onEnded { value in
                            let x = max(0, min(value.location.x, width - 1))
                            let bar = Int((x / width) * CGFloat(barCount))
                            let albumIndex = barToAlbumIndex[min(bar, barCount - 1)]
                            // Jump Cover Flow immediately
                            onSelect(albumIndex)
                            // Animate highlight to center
                            animatingToCenter = true
                            withAnimation(.spring(response: 2.0, dampingFraction: 0.8)) {
                                dragActiveBar = highlightBar
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                dragActiveBar = nil
                                animatingToCenter = false
                                withAnimation(.interpolatingSpring(stiffness: 200, damping: 12)) {
                                    isHighlightActive = false
                                }
                                withAnimation(.easeInOut(duration: 0.2)) { showLabel = false }
                                onUserInteraction?()
                            }
                        }
                )
                // Floating year label above the highlighted bar
                if isRapidTransition, albums.indices.contains(barToAlbumIndex[highlightBar]) {
                    let album = albums[barToAlbumIndex[highlightBar]]
                    let labelX = barSpacing * CGFloat(highlightBar) + barSpacing / 2
                    VStack(spacing: 0) {
                        Text(String(album.year))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.32), value: album.year)
                        Spacer().frame(height: 8)
                    }
                    .fixedSize()
                    .position(x: labelX, y: -20)
                    .id(album.year)
                }
            }
        }
    }
}

// Simple downward triangle for the label pointer
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

extension Notification.Name {
    static let scrubberJumpToIndex = Notification.Name("scrubberJumpToIndex")
}

#if DEBUG
struct PreviewWrapper: View {
    let dummyAlbums: [Album]
    @Namespace var previewNamespace
    var body: some View {
        CoverFlowView(
            albums: dummyAlbums,
            selectedAlbum: .constant(dummyAlbums[3]),
            onUserInteraction: {},
            onScroll: { _ in },
            onAlbumTilt: { _ in },
            onSwipeUp: { _ in },
            albumNamespace: previewNamespace,
            flippedAlbum: .constant(dummyAlbums[3])
        )
        .frame(height: 400)
        .padding()
    }
}
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let dummyAlbums = (0..<10).map { i in
            Album(title: "Album \(i+1)", artist: "Artist \(i+1)", coverImage: "music.note", year: 2000 + i)
        }
        let container = try! ModelContainer(
            for: Album.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        ContentView()
            .environment(\.modelContext, context)
        WaveformScrubberBar(albums: dummyAlbums, selectedIndex: 3, onSelect: { _ in })
            .frame(height: 56)
            .padding()
        PreviewWrapper(dummyAlbums: dummyAlbums)
    }
}
#endif
