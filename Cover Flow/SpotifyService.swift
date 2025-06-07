import Foundation

@MainActor
class SpotifyService: ObservableObject {
    private let clientId = "5ea14b87e5d64c969434684d846fbd35"
    private let clientSecret = "43b57509b7be40c9bc3f4273c62d7a4d"
    private var accessToken: String?
    
    @Published var albums: [Album] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var errorMessage: String?
    
    struct SpotifyAlbum: Codable {
        let id: String
        let name: String
        let artists: [Artist]
        let images: [Image]
        let releaseDate: String
        
        struct Artist: Codable {
            let name: String
        }
        
        struct Image: Codable {
            let url: String
            let height: Int
            let width: Int
        }
        
        enum CodingKeys: String, CodingKey {
            case id, name, artists, images
            case releaseDate = "release_date"
        }
    }
    
    struct SearchArtistResponse: Codable {
        let artists: Artists
        struct Artists: Codable {
            let items: [Artist]
            struct Artist: Codable {
                let id: String
                let name: String
            }
        }
    }
    
    struct ArtistAlbumsResponse: Codable {
        let items: [SpotifyAlbum]
    }
    
    func fetchIndieRockAlbums() async {
        isLoading = true
        errorMessage = nil
        albums = []
        let indieRockArtists = [
            "Arctic Monkeys", "Tame Impala", "The Strokes", "The Killers", "Florence + The Machine",
            "Vampire Weekend", "The 1975", "Foals", "The National", "Arcade Fire"
        ]
        do {
            if accessToken == nil {
                try await getAccessToken()
            }
            var allAlbums: [Album] = []
            for artistName in indieRockArtists {
                let artistId = try await fetchArtistId(for: artistName)
                print("[DEBUG] Artist: \(artistName), ID: \(artistId ?? "not found")")
                if let artistId = artistId {
                    let albums = try await fetchAlbums(for: artistId)
                    print("[DEBUG] \(artistName) albums fetched: \(albums.count)")
                    allAlbums.append(contentsOf: albums)
                }
            }
            // Shuffle and limit to 30
            allAlbums.shuffle()
            self.albums = Array(allAlbums.prefix(30))
            print("[DEBUG] Total albums loaded: \(self.albums.count)")
        } catch {
            print("Error fetching indie rock albums: \(error)")
            self.error = error
            self.errorMessage = error.localizedDescription
        }
        self.isLoading = false
    }
    
    private func fetchArtistId(for artistName: String) async throws -> String? {
        let encodedName = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://api.spotify.com/v1/search?q=\(encodedName)&type=artist&limit=1")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SearchArtistResponse.self, from: data)
        return response.artists.items.first?.id
    }
    
    private func fetchAlbums(for artistId: String) async throws -> [Album] {
        let url = URL(string: "https://api.spotify.com/v1/artists/\(artistId)/albums?include_groups=album,single&market=US&limit=20")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ArtistAlbumsResponse.self, from: data)
        return response.items.map { spotifyAlbum in
            Album(
                title: spotifyAlbum.name,
                artist: spotifyAlbum.artists.first?.name ?? "Unknown Artist",
                coverImage: spotifyAlbum.images.first?.url ?? "",
                year: Int(spotifyAlbum.releaseDate.prefix(4)) ?? 0
            )
        }
    }
    
    private func getAccessToken() async throws {
        print("Getting new access token...")
        let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        
        let credentials = "\(clientId):\(clientSecret)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "grant_type=client_credentials"
        request.httpBody = body.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("Token Response Status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("Token Error: \(errorJson)")
                }
                throw NSError(domain: "SpotifyService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to get access token"])
            }
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = tokenResponse.accessToken
        print("Successfully got new access token")
    }
    
    private struct TokenResponse: Codable {
        let accessToken: String
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }
} 
