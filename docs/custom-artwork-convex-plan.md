# Custom Playlist Artwork — Convex Persistence Plan

## Current State

### Schema (already exists)
```ts
// convex/schema.ts
customPlaylists: defineTable({
  artwork: v.optional(v.string()), // URL string - already here!
  // ...
})
```

### Problem
- `artwork` field exists but is only set from first track's `artwork_url`
- Custom uploaded images are stored locally in GRDB (`customArtworkData: Data?`)
- Not synced to Convex → lost on reinstall/new device

## Solution

### Part 1: Convex (mixbridge-web)

**1. Add file upload action** (`convex/actions/uploadPlaylistArtwork.ts`)
```ts
import { v } from "convex/values";
import { action } from "../_generated/server";

export const generateUploadUrl = action({
  args: {},
  handler: async (ctx) => {
    return await ctx.storage.generateUploadUrl();
  },
});

export const getUrl = action({
  args: { storageId: v.id("_storage") },
  handler: async (ctx, args) => {
    return await ctx.storage.getUrl(args.storageId);
  },
});
```

**2. Add setArtwork mutation** (`convex/customPlaylists.ts`)
```ts
export const setArtwork = mutation({
  args: {
    userId: v.string(),
    playlistId: v.string(),
    artworkUrl: v.optional(v.string()), // null to clear
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("customPlaylists")
      .withIndex("by_userId_playlistId", (q) =>
        q.eq("userId", args.userId).eq("playlistId", args.playlistId)
      )
      .first();

    if (!existing) return null;

    await ctx.db.patch(existing._id, {
      artwork: args.artworkUrl,
      updatedAt: Date.now(),
    });

    return existing._id;
  },
});
```

### Part 2: iOS (mixbridge-ios)

**1. Add ConvexService methods**
```swift
// mixbridge/Services/ConvexService.swift

/// Generate upload URL for playlist artwork
func generatePlaylistArtworkUploadUrl() async throws -> String {
    return try await action("uploadPlaylistArtwork:generateUploadUrl", args: [:])
}

/// Get URL for uploaded storage item
func getStorageUrl(storageId: String) async throws -> String {
    return try await action("uploadPlaylistArtwork:getUrl", args: ["storageId": storageId])
}

/// Set custom artwork URL for a playlist
func setCustomPlaylistArtwork(userId: String, playlistId: String, artworkUrl: String?) async throws {
    try await mutationVoid("customPlaylists:setArtwork", args: [
        "userId": userId,
        "playlistId": playlistId,
        "artworkUrl": artworkUrl as Any
    ])
}
```

**2. Add image upload helper**
```swift
// mixbridge/Services/ConvexService.swift or new ConvexStorageService.swift

func uploadPlaylistArtwork(imageData: Data) async throws -> String {
    // 1. Get upload URL
    let uploadUrl = try await generatePlaylistArtworkUploadUrl()
    
    // 2. Upload image data
    var request = URLRequest(url: URL(string: uploadUrl)!)
    request.httpMethod = "POST"
    request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
    request.httpBody = imageData
    
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200,
          let storageId = httpResponse.value(forHTTPHeaderField: "X-Convex-Storage-Id") else {
        throw ConvexError.uploadFailed
    }
    
    // 3. Get public URL
    return try await getStorageUrl(storageId: storageId)
}
```

**3. Update PlaylistSync.swift**
```swift
// In createUserPlaylistWithTracks - after local save:
if let artworkData = customArtworkData {
    Task {
        do {
            let artworkUrl = try await convex.uploadPlaylistArtwork(imageData: artworkData)
            try await convex.setCustomPlaylistArtwork(
                userId: userId, 
                playlistId: playlistId, 
                artworkUrl: artworkUrl
            )
        } catch {
            logError(.sync, "Failed to upload custom artwork to Convex: \(error)")
        }
    }
}

// In updateUserPlaylistArtwork:
if let artworkData = customArtworkData {
    let artworkUrl = try await convex.uploadPlaylistArtwork(imageData: artworkData)
    try await convex.setCustomPlaylistArtwork(userId: userId, playlistId: playlistId, artworkUrl: artworkUrl)
}
```

**4. Update sync to fetch artwork URL**
```swift
// When fetching playlists from Convex, map artwork URL to local model
// PersistedPlaylist should have: customArtworkUrl: String?
// Display logic: customArtworkUrl ?? customArtworkData ?? firstTrackArtwork
```

## File Changes Summary

### mixbridge-web (Convex)
| File | Change |
|------|--------|
| `convex/actions/uploadPlaylistArtwork.ts` | **NEW** - Upload URL generation |
| `convex/customPlaylists.ts` | Add `setArtwork` mutation |

### mixbridge-ios
| File | Change |
|------|--------|
| `ConvexService.swift` | Add upload + setArtwork methods |
| `PlaylistSync.swift` | Upload artwork on create/edit |
| `PersistedPlaylist.swift` | Add `customArtworkUrl: String?` |
| Display views | Prefer URL over local data |

## Migration Path

1. Deploy Convex changes first (backward compatible)
2. Update iOS to upload + sync artwork
3. Existing local-only artwork will be uploaded on next edit
4. New playlists will have artwork from creation

## Estimated Size
- Convex: ~50 lines new code
- iOS: ~100 lines new code
- Total: Small, focused change
