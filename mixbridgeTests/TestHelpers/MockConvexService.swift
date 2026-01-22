import Foundation
@testable import mixbridge

/// A mock implementation of ConvexService for testing
/// Allows injecting predefined responses and tracking method calls
final class MockConvexService {

    // MARK: - Call Tracking

    struct MethodCall: Equatable {
        let name: String
        let args: [String: String]
    }

    private(set) var methodCalls: [MethodCall] = []

    func resetCalls() {
        methodCalls.clear()
    }

    private func recordCall(_ name: String, args: [String: String] = [:]) {
        methodCalls.append(MethodCall(name: name, args: args))
    }

    // MARK: - Stubbed Responses

    var stubbedLikedTracks: [SoundCloudTrack] = []
    var stubbedLikedPlaylists: [SoundCloudPlaylist] = []
    var stubbedPlaylists: [SoundCloudPlaylist] = []
    var stubbedPlaylistTracks: [String: [SoundCloudTrack]] = [:]
    var stubbedSearchResult: SearchResult?
    var stubbedUserProfile: SoundCloudProfile?
    var stubbedPlayHistory: [ConvexPlayHistory] = []
    var stubbedQueueTracks: [ConvexQueueTrack] = []
    var stubbedCustomPlaylists: [ConvexCustomPlaylist] = []
    var stubbedStreamResponse: ConvexStreamResponse?

    // MARK: - Error Injection

    var errorToThrow: Error?

    // MARK: - Mock Methods

    func getLikedTracks(userId: String, forceRefresh: Bool = false) async throws -> [SoundCloudTrack] {
        recordCall("getLikedTracks", args: ["userId": userId, "forceRefresh": String(forceRefresh)])
        if let error = errorToThrow { throw error }
        return stubbedLikedTracks
    }

    func getLikedPlaylists(userId: String, forceRefresh: Bool = false) async throws -> [SoundCloudPlaylist] {
        recordCall("getLikedPlaylists", args: ["userId": userId, "forceRefresh": String(forceRefresh)])
        if let error = errorToThrow { throw error }
        return stubbedLikedPlaylists
    }

    func getPlaylists(userId: String, forceRefresh: Bool = false) async throws -> [SoundCloudPlaylist] {
        recordCall("getPlaylists", args: ["userId": userId, "forceRefresh": String(forceRefresh)])
        if let error = errorToThrow { throw error }
        return stubbedPlaylists
    }

    func getPlaylistTracks(userId: String, playlistId: String, forceRefresh: Bool = false) async throws -> [SoundCloudTrack] {
        recordCall("getPlaylistTracks", args: ["userId": userId, "playlistId": playlistId])
        if let error = errorToThrow { throw error }
        return stubbedPlaylistTracks[playlistId] ?? []
    }

    func search(userId: String, query: String, limit: Int = 20, forceRefresh: Bool = false) async throws -> SearchResult {
        recordCall("search", args: ["userId": userId, "query": query, "limit": String(limit)])
        if let error = errorToThrow { throw error }
        return stubbedSearchResult ?? SearchResult(tracks: [], playlists: [], users: [])
    }

    func getUserProfile(userId: String, forceRefresh: Bool = false) async throws -> SoundCloudProfile {
        recordCall("getUserProfile", args: ["userId": userId])
        if let error = errorToThrow { throw error }
        guard let profile = stubbedUserProfile else {
            throw ConvexError.noData
        }
        return profile
    }

    func getPlayHistory(userId: String, limit: Int = 100) async throws -> [ConvexPlayHistory] {
        recordCall("getPlayHistory", args: ["userId": userId, "limit": String(limit)])
        if let error = errorToThrow { throw error }
        return stubbedPlayHistory
    }

    func getQueueTracks(userId: String) async throws -> [ConvexQueueTrack] {
        recordCall("getQueueTracks", args: ["userId": userId])
        if let error = errorToThrow { throw error }
        return stubbedQueueTracks
    }

    func addTrackToQueue(track: SoundCloudTrack) async throws -> String {
        recordCall("addTrackToQueue", args: ["trackId": String(track.id)])
        if let error = errorToThrow { throw error }
        return "mock-queue-track-id"
    }

    func removeTrackFromQueue(queueTrackId: String) async throws {
        recordCall("removeTrackFromQueue", args: ["queueTrackId": queueTrackId])
        if let error = errorToThrow { throw error }
    }

    func clearQueue() async throws {
        recordCall("clearQueue")
        if let error = errorToThrow { throw error }
    }

    func likeTrack(trackId: String) async throws {
        recordCall("likeTrack", args: ["trackId": trackId])
        if let error = errorToThrow { throw error }
    }

    func unlikeTrack(trackId: String) async throws {
        recordCall("unlikeTrack", args: ["trackId": trackId])
        if let error = errorToThrow { throw error }
    }

    func likePlaylist(playlistId: String) async throws {
        recordCall("likePlaylist", args: ["playlistId": playlistId])
        if let error = errorToThrow { throw error }
    }

    func unlikePlaylist(playlistId: String) async throws {
        recordCall("unlikePlaylist", args: ["playlistId": playlistId])
        if let error = errorToThrow { throw error }
    }

    func getCustomPlaylists(userId: String) async throws -> [ConvexCustomPlaylist] {
        recordCall("getCustomPlaylists", args: ["userId": userId])
        if let error = errorToThrow { throw error }
        return stubbedCustomPlaylists
    }

    func createCustomPlaylist(userId: String, playlistId: String, name: String, description: String?) async throws {
        recordCall("createCustomPlaylist", args: ["userId": userId, "playlistId": playlistId, "name": name])
        if let error = errorToThrow { throw error }
    }

    func deleteCustomPlaylist(userId: String, playlistId: String) async throws {
        recordCall("deleteCustomPlaylist", args: ["userId": userId, "playlistId": playlistId])
        if let error = errorToThrow { throw error }
    }

    func getDirectStreamURL(trackId: String) async throws -> ConvexStreamResponse {
        recordCall("getDirectStreamURL", args: ["trackId": trackId])
        if let error = errorToThrow { throw error }
        guard let response = stubbedStreamResponse else {
            throw ConvexError.noData
        }
        return response
    }
}

// MARK: - Helper Extensions

private extension Array where Element == MockConvexService.MethodCall {
    mutating func clear() {
        removeAll()
    }
}
