//
//  PersistedPlaylist.swift
//  MixBridgeDomain
//
//  Base model for persisted playlists - no GRDB dependencies.
//

import Foundation

public struct PersistedPlaylist: Codable, Equatable, Identifiable, Hashable, Sendable {
	public enum CodingKeys: String, CodingKey {
		case id, name, creator, creatorId, artwork, trackCount, duration
		case description, genre, createdAt, lastUpdated, soundCloudData
		case libraryOwnerUserId, isUserCreated, sourcePlaylistId
		case customName, isHiddenFromLibrary, customArtworkData, customArtworkUrl
		case isAddedToLibrary, source
	}

    public var id: String
    public var name: String
    public var creator: String
    public var creatorId: Int
    public var artwork: String
    public var trackCount: Int
    public var duration: Int
    public var description: String?
    public var genre: String?
    public var createdAt: Date
    public var lastUpdated: Date
    public var soundCloudData: Data?

    /// If set, this playlist belongs in the signed-in user's Library UI.
    /// If nil, the playlist is cached (e.g. search/artist) and should not appear in Library lists.
    public var libraryOwnerUserId: String?

	/// True if this is a user-created playlist (not from SoundCloud)
	public var isUserCreated: Bool

	/// For shared playlist imports, stores the original playlist id.
	public var sourcePlaylistId: String?

	/// User's custom name for this playlist (overrides `name` in UI if set)
	public var customName: String?

	/// If true, this SoundCloud playlist is hidden from the user's library
	public var isHiddenFromLibrary: Bool

	/// Custom artwork image data (JPEG compressed) for user-created playlists
	public var customArtworkData: Data?

	/// URL of custom artwork synced to Convex storage
	public var customArtworkUrl: String?

	/// If true, this playlist was manually added to the local library (via "Add to Library")
	/// and should not be removed during sync even if not in the user's SoundCloud collection
	public var isAddedToLibrary: Bool
    
    /// The source platform for this playlist (soundcloud, spotify)
    /// Defaults to soundcloud for backward compatibility
    public var source: String

	/// Returns the display name (custom name if set, otherwise original name)
	public var displayName: String {
		customName ?? name
	}

	public init(
		id: String,
		name: String,
		creator: String,
		creatorId: Int,
		artwork: String,
		trackCount: Int = 0,
		duration: Int = 0,
		description: String? = nil,
		genre: String? = nil,
		createdAt: Date = Date(),
		lastUpdated: Date = Date(),
		soundCloudData: Data? = nil,
		libraryOwnerUserId: String? = nil,
		isUserCreated: Bool = false,
		sourcePlaylistId: String? = nil,
		customName: String? = nil,
		isHiddenFromLibrary: Bool = false,
		customArtworkData: Data? = nil,
		customArtworkUrl: String? = nil,
		isAddedToLibrary: Bool = false,
        source: String = "soundcloud"
	) {
        self.id = id
        self.name = name
        self.creator = creator
        self.creatorId = creatorId
        self.artwork = artwork
        self.trackCount = trackCount
        self.duration = duration
        self.description = description
        self.genre = genre
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
		self.soundCloudData = soundCloudData
		self.libraryOwnerUserId = libraryOwnerUserId
		self.isUserCreated = isUserCreated
		self.sourcePlaylistId = sourcePlaylistId
		self.customName = customName
		self.isHiddenFromLibrary = isHiddenFromLibrary
		self.customArtworkData = customArtworkData
		self.customArtworkUrl = customArtworkUrl
		self.isAddedToLibrary = isAddedToLibrary
        self.source = source
	}
}
