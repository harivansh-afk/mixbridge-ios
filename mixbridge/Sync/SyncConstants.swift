//
//  SyncConstants.swift
//  mixbridge
//

import Foundation

enum SyncConstants {
    /// Marker stored in `PersistedPlaylist.libraryOwnerUserId` for cached (non-Library) playlists.
    /// Library playlists always store the signed-in `userId`.
    static let cachedPlaylistOwner = "__cache__"
}

