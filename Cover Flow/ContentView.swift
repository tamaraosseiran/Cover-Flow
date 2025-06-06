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
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack {
                if spotifyService.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if let errorMessage = spotifyService.errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                } else if spotifyService.albums.isEmpty {
                    Text("No albums found.")
                        .foregroundColor(.white)
                        .padding()
                } else {
                    // Cover Flow carousel with advanced snap effect
                    CoverFlowView(albums: spotifyService.albums, selectedAlbum: $selectedAlbum)
                        .frame(height: 400)
                }
                
                // Album info
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
                    .padding()
                }
            }
        }
        .onAppear {
            print("[DEBUG] On appear. Current album count: \(spotifyService.albums.count)")
            Task {
                await spotifyService.fetchIndieRockAlbums()
                print("[DEBUG] After fetch. Album count: \(spotifyService.albums.count)")
            }
        }
    }
}

struct CoverFlowView: View {
    let albums: [Album]
    @Binding var selectedAlbum: Album?
    @State private var selectedIndex: Int = 0
    @State private var scrollOffset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0
    
    let itemWidth: CGFloat = 200
    let itemSpacing: CGFloat = 16
    let maxRotation: Double = 15 // degrees
    let minScale: CGFloat = 0.8
    let minOpacity: Double = 0.5
    
    var body: some View {
        GeometryReader { geometry in
            let totalWidth = CGFloat(albums.count) * (itemWidth + itemSpacing)
            let center = geometry.size.width / 2
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: itemSpacing) {
                    ForEach(albums.indices, id: \.self) { index in
                        let xPosition = CGFloat(index) * (itemWidth + itemSpacing)
                        let itemCenter = xPosition - scrollOffset + itemWidth / 2 + itemSpacing * CGFloat(index)
                        let distance = (itemCenter - center) / (itemWidth + itemSpacing)
                        let rotation = max(-maxRotation, min(maxRotation, Double(distance) * maxRotation))
                        let scale = max(minScale, 1.0 - abs(distance) * 0.2)
                        let opacity = max(minOpacity, 1.0 - abs(distance) * 0.3)
                        AlbumCoverView(album: albums[index])
                            .frame(width: itemWidth, height: 200)
                            .scaleEffect(scale)
                            .opacity(opacity)
                            .rotation3DEffect(
                                .degrees(rotation),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: .center
                            )
                            .onTapGesture {
                                withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.7)) {
                                    let targetOffset = CGFloat(index) * (itemWidth + itemSpacing)
                                    scrollOffset = targetOffset
                                    selectedIndex = index
                                    selectedAlbum = albums[index]
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
                        withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.7)) {
                            let targetOffset = CGFloat(newIndex) * (itemWidth + itemSpacing)
                            scrollOffset = targetOffset
                            selectedIndex = newIndex
                            selectedAlbum = albums[newIndex]
                        }
                    }
            )
            .onAppear {
                // Center the first album
                scrollOffset = 0
                selectedIndex = 0
                if !albums.isEmpty {
                    selectedAlbum = albums[0]
                }
            }
        }
    }
}

struct AlbumCoverView: View {
    let album: Album
    
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
                } placeholder: {
                    ProgressView()
                }
                .padding()
            } else {
                Image(systemName: album.coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Album.self, inMemory: true)
}
