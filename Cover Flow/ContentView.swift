//
//  ContentView.swift
//  Cover Flow
//
//  Created by Tamara Osseiran on 6/6/25.
//

import SwiftUI
import SwiftData

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
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                if spotifyService.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(height: 400)
                        .padding(.top)
                } else if let errorMessage = spotifyService.errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                        .frame(height: 400)
                        .padding(.top)
                } else if spotifyService.albums.isEmpty {
                    Text("No albums found.")
                        .foregroundColor(.white)
                        .padding()
                        .frame(height: 400)
                        .padding(.top)
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
                        }
                    )
                        .frame(height: 400)
                        .padding(.top)
                }
                
                Spacer()
                
                // Fixed-height album info at the bottom
                Group {
                    if let selected = selectedAlbum {
                        VStack(spacing: 8) {
                            Text(selected.title)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text(selected.artist)
                                .font(.title2)
                                .foregroundColor(.gray)
                            Text("\(selected.year)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    } else {
                        VStack { Text(" ") }
                    }
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.001))
                .padding(.bottom, 8)
                
                // Scrubber bar (always visible, animates between idle and active)
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
                    highlightOffset: scrubberHighlightOffset
                )
                .frame(height: 40)
                .padding(.bottom, 18)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .onEnded { _ in activateScrubber() }
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            print("[DEBUG] On appear. Current album count: \(spotifyService.albums.count)")
            Task {
                await spotifyService.fetchIndieRockAlbums()
                print("[DEBUG] After fetch. Album count: \(spotifyService.albums.count)")
            }
        }
    }
    
    // Helper to activate and auto-idle the scrubber
    private func activateScrubber() {
        scrubberActiveTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isScrubberActive = true
        }
        let task = DispatchWorkItem {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isScrubberActive = false
            }
        }
        scrubberActiveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: task)
    }
    
    // Update highlight offset and reset after delay
    private func updateScrubberHighlightOffset(_ direction: Int) {
        scrubberHighlightResetTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            scrubberHighlightOffset = direction.clamped(to: -5...5)
        }
        let task = DispatchWorkItem {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                scrubberHighlightOffset = 0
            }
        }
        scrubberHighlightResetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: task)
    }
}

struct CoverFlowView: View {
    let albums: [Album]
    @Binding var selectedAlbum: Album?
    var onUserInteraction: (() -> Void)? = nil
    var onScroll: ((Int) -> Void)? = nil
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
                        let scale = selectedIndex == index ? 1.15 + 0.05 * abs(dragOffset / 100) : max(minScale, 1.0 - abs(distance) * 0.2)
                        let opacity = max(minOpacity, 1.0 - abs(distance) * 0.3)
                        let isFocused = selectedIndex == index
                        let tilt = isFocused ? Double(dragOffset / 12).clamped(to: -maxTilt...maxTilt) : rotation
                        let parallax = isFocused ? (dragOffset / 4).clamped(to: -maxParallax...maxParallax) : 0
                        let anchor: UnitPoint = .center
                        AlbumCoverView(album: albums[index], parallax: parallax)
                            .frame(width: itemWidth, height: 200)
                            .scaleEffect(scale)
                            .opacity(opacity)
                            .rotation3DEffect(
                                .degrees(tilt),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: anchor
                            )
                            .zIndex(-abs(distance))
                            .onTapGesture {
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
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.3))
                .shadow(radius: 10)
            
            if album.coverImage.hasPrefix("http") {
                AsyncImage(url: URL(string: album.coverImage)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .offset(x: parallax)
                        .animation(.easeOut(duration: 0.2), value: parallax)
                } placeholder: {
                    ProgressView()
                }
                .padding()
            } else {
                Image(systemName: album.coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .offset(x: parallax)
                    .animation(.easeOut(duration: 0.2), value: parallax)
                    .padding()
                    .foregroundColor(.white)
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

// MARK: - WaveformScrubberBar

struct WaveformScrubberBar: View {
    let albums: [Album]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    var onUserInteraction: (() -> Void)? = nil
    var isActive: Bool = false
    var highlightOffset: Int = 0
    private let barCount: Int = 25
    private let idleMinHeight: CGFloat = 8
    private let idleMaxHeight: CGFloat = 18
    private let idleMinOpacity: Double = 0.12
    private let idleMaxOpacity: Double = 0.22
    private let idleMinWidth: CGFloat = 1.5
    private let idleMaxWidth: CGFloat = 3.5
    private let activeMinHeight: CGFloat = 14
    private let activeMaxHeight: CGFloat = 28
    private let activeMinOpacity: Double = 0.22
    private let activeMaxOpacity: Double = 0.7
    private let activeMinWidth: CGFloat = 2.5
    private let activeMaxWidth: CGFloat = 6
    @GestureState private var dragBar: Int? = nil
    @State private var dragActiveBar: Int? = nil
    @State private var animatingToCenter = false
    @State private var showLabel = false
    @State private var isHighlightActive = false
    @Namespace private var labelNamespace
    
    var body: some View {
        let count = albums.count
        let centerBar = barCount / 2
        // During drag or animation, highlight follows dragActiveBar; otherwise, it's centered
        let highlightBar = dragActiveBar ?? (centerBar + highlightOffset)
        // Compute the first album index shown in the waveform
        let focusIndex = dragBar ?? selectedIndex
        let minFirst = 0
        let maxFirst = max(0, count - barCount)
        // If dragging or animating, shift the waveform so the highlight is under the finger/animating bar
        let firstAlbumIndex: Int = {
            if let dragBar = dragActiveBar {
                // Keep the highlighted bar under the finger or animating
                return min(max(focusIndex - dragBar, minFirst), maxFirst)
            } else {
                // Centered
                return min(max(focusIndex - centerBar, minFirst), maxFirst)
            }
        }()
        let barToAlbumIndex: [Int] = (0..<barCount).map { bar in
            let idx = firstAlbumIndex + bar
            return min(max(idx, 0), count - 1)
        }
        GeometryReader { geo in
            let width = geo.size.width
            let barSpacing = width / CGFloat(barCount)
            let minHeight = isActive ? activeMinHeight : idleMinHeight
            let maxHeight = isActive ? activeMaxHeight : idleMaxHeight
            let minOpacity = isActive ? activeMinOpacity : idleMinOpacity
            let maxOpacity = isActive ? activeMaxOpacity : idleMaxOpacity
            let minWidth = isActive ? activeMinWidth : idleMinWidth
            let maxWidth = isActive ? activeMaxWidth : idleMaxWidth
            ZStack(alignment: .bottomLeading) {
                ForEach(0..<barCount, id: \ .self) { bar in
                    let albumIndex = barToAlbumIndex[bar]
                    let dist = abs(bar - highlightBar)
                    let norm = min(Double(dist) / Double(barCount), 1.0)
                    let height = minHeight + (maxHeight - minHeight) * CGFloat(1.0 - norm * norm)
                    let opacity = minOpacity + (maxOpacity - minOpacity) * (1.0 - norm)
                    let isCenter = bar == highlightBar
                    let barWidth = isCenter ? maxWidth : minWidth
                    Rectangle()
                        .fill(isCenter ? Color.white : Color.white.opacity(opacity))
                        .frame(width: barWidth, height: height)
                        .cornerRadius(1)
                        .shadow(color: isCenter ? Color.white.opacity(0.7) : .clear, radius: isCenter ? 6 : 0, x: 0, y: 0)
                        .scaleEffect(isCenter && (showLabel || isHighlightActive) ? 1.2 : 1.0, anchor: .bottom)
                        .animation(.spring(response: 2.0, dampingFraction: 0.8), value: highlightBar)
                        .contentShape(Rectangle())
                        .position(x: barSpacing * CGFloat(bar) + barSpacing / 2, y: maxHeight - height / 2)
                        .onTapGesture {
                            onSelect(albumIndex)
                            onUserInteraction?()
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .center)
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
                            isHighlightActive = true
                            dragActiveBar = bar
                            withAnimation(.easeInOut(duration: 0.15)) { showLabel = true }
                            onUserInteraction?()
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
                                dragActiveBar = centerBar
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
                // Floating label
                if showLabel, highlightBar < barToAlbumIndex.count {
                    let albumIndex = barToAlbumIndex[highlightBar]
                    let barX = CGFloat(highlightBar) * barSpacing + barSpacing / 2
                    VStack(spacing: 0) {
                        if albumIndex < albums.count {
                            Text(albums[albumIndex].title)
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.black.opacity(0.85))
                                )
                                .matchedGeometryEffect(id: "label", in: labelNamespace)
                        }
                        Triangle()
                            .fill(Color.black.opacity(0.85))
                            .frame(width: 12, height: 6)
                    }
                    .position(x: barX, y: maxHeight - 32)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(10)
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
        CoverFlowView(albums: dummyAlbums, selectedAlbum: .constant(dummyAlbums[3]))
            .frame(height: 400)
            .padding()
    }
}
#endif
