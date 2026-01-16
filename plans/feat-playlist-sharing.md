# Feature: Playlist Sharing System

**Created:** 2026-01-15
**Type:** Enhancement
**Complexity:** A LOT (Comprehensive)

---

## Overview

Implement an Apple Music-inspired playlist sharing system for MixBridge that enables users to share playlists via links that work seamlessly across web and iOS. When a user shares a playlist, recipients can preview it on the web and open it directly in the iOS app via Universal Links.

### Key Capabilities
- Generate shareable URLs with short, unique identifiers
- Public playlist preview pages on web with Open Graph metadata
- iOS Universal Links for seamless app-to-app sharing
- Privacy controls (public/private toggle)
- "Add to Library" action for shared playlists

---

## Problem Statement

Currently, MixBridge users cannot share their curated playlists with friends or on social media. The app is entirely siloed - there's no way to:
1. Generate a link to a playlist
2. View a playlist without being authenticated
3. Deep link into the app from external sources
4. Control whether a playlist is publicly accessible

This limits viral growth, social sharing, and the core music discovery experience that makes platforms like Apple Music and Spotify successful.

---

## Proposed Solution

### URL Structure
```
https://mixbridge.app/p/{shareId}
```

Example: `https://mixbridge.app/p/k3xR9mPq2nZ4`

- **shareId**: 12-character NanoID (URL-safe, ~35 years at 1000 IDs/hour before 1% collision)
- Short `/p/` prefix for brevity in social sharing
- Optional slug suffix for SEO: `/p/{shareId}/summer-vibes-2025`

### Architecture Overview

```
+------------------+     +------------------+     +------------------+
|    iOS App       |     |   Convex Backend |     |   Next.js Web    |
+------------------+     +------------------+     +------------------+
|                  |     |                  |     |                  |
| ShareButton      |---->| createShareLink  |     | /p/[shareId]     |
|                  |     | mutation         |     | page.tsx         |
|                  |     |                  |     |                  |
| DeepLinkRouter   |<----|                  |<----| generateMetadata |
| (Universal Links)|     | getPublicPlaylist|     | (Open Graph)     |
|                  |     | public query     |     |                  |
| SharedPlaylistView     |                  |     | PlaylistPreview  |
|                  |     | updateVisibility |     | component        |
+------------------+     +------------------+     +------------------+
```

---

## Technical Approach

### Phase 1: Database Schema Updates

#### Convex Schema Changes (`convex/schema.ts`)

```typescript
// Add to existing customPlaylists table or create new sharedPlaylists table
customPlaylists: defineTable({
  userId: v.string(),
  playlistId: v.string(),
  name: v.string(),
  description: v.optional(v.string()),
  artwork: v.optional(v.string()),
  trackIds: v.array(v.string()),
  trackData: v.optional(v.any()),
  createdAt: v.number(),
  updatedAt: v.number(),

  // NEW FIELDS FOR SHARING
  shareId: v.optional(v.string()),        // 12-char NanoID
  visibility: v.optional(v.string()),      // "private" | "public"
  shareCreatedAt: v.optional(v.number()),  // When share link was first generated
})
  .index("by_userId", ["userId"])
  .index("by_playlistId", ["playlistId"])
  .index("by_userId_playlistId", ["userId", "playlistId"])
  .index("by_shareId", ["shareId"]),        // NEW INDEX for public lookups
```

#### iOS Model Updates (`PersistedPlaylist`)

```swift
// MixBridgeDomain/Sources/PersistedPlaylist.swift
public struct PersistedPlaylist: Codable, Identifiable, Hashable {
    // ... existing fields ...

    // NEW FIELDS
    public var shareId: String?
    public var visibility: PlaylistVisibility
    public var shareCreatedAt: Date?

    public enum PlaylistVisibility: String, Codable {
        case `private` = "private"
        case `public` = "public"
    }
}
```

### Phase 2: Convex Backend Functions

#### Share Link Generation (`convex/sharing.ts`)

```typescript
import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { customAlphabet } from "nanoid";

const generateShareId = customAlphabet(
  "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
  12
);

export const createShareLink = mutation({
  args: { playlistId: v.string() },
  handler: async (ctx, { playlistId }) => {
    // Get authenticated user
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new Error("Not authenticated");
    const userId = identity.subject;

    // Find playlist
    const playlist = await ctx.db
      .query("customPlaylists")
      .withIndex("by_userId_playlistId", (q) =>
        q.eq("userId", userId).eq("playlistId", playlistId)
      )
      .first();

    if (!playlist) throw new Error("Playlist not found");

    // Return existing shareId if already public
    if (playlist.shareId && playlist.visibility === "public") {
      return {
        shareId: playlist.shareId,
        shareUrl: `https://mixbridge.app/p/${playlist.shareId}`,
        isNew: false,
      };
    }

    // Generate new shareId with collision check
    let shareId: string;
    let attempts = 0;
    do {
      shareId = generateShareId();
      const existing = await ctx.db
        .query("customPlaylists")
        .withIndex("by_shareId", (q) => q.eq("shareId", shareId))
        .first();
      if (!existing) break;
      attempts++;
    } while (attempts < 10);

    if (attempts >= 10) throw new Error("Failed to generate unique share ID");

    // Update playlist with share info
    await ctx.db.patch(playlist._id, {
      shareId,
      visibility: "public",
      shareCreatedAt: Date.now(),
    });

    return {
      shareId,
      shareUrl: `https://mixbridge.app/p/${shareId}`,
      isNew: true,
    };
  },
});

export const updateVisibility = mutation({
  args: {
    playlistId: v.string(),
    visibility: v.union(v.literal("public"), v.literal("private")),
  },
  handler: async (ctx, { playlistId, visibility }) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new Error("Not authenticated");
    const userId = identity.subject;

    const playlist = await ctx.db
      .query("customPlaylists")
      .withIndex("by_userId_playlistId", (q) =>
        q.eq("userId", userId).eq("playlistId", playlistId)
      )
      .first();

    if (!playlist) throw new Error("Playlist not found");

    await ctx.db.patch(playlist._id, { visibility });

    return { success: true };
  },
});
```

#### Public Playlist Query (`convex/public.ts`)

```typescript
import { query } from "./_generated/server";
import { v } from "convex/values";

// This query can be called without authentication
export const getPlaylistByShareId = query({
  args: { shareId: v.string() },
  handler: async (ctx, { shareId }) => {
    const playlist = await ctx.db
      .query("customPlaylists")
      .withIndex("by_shareId", (q) => q.eq("shareId", shareId))
      .first();

    if (!playlist) return null;
    if (playlist.visibility !== "public") return null;

    // Get owner info for display
    const ownerProfile = await ctx.db
      .query("userProfile")
      .withIndex("by_userId", (q) => q.eq("userId", playlist.userId))
      .first();

    // Return sanitized playlist data (no internal IDs)
    return {
      name: playlist.name,
      description: playlist.description,
      artwork: playlist.artwork,
      trackCount: playlist.trackIds.length,
      tracks: playlist.trackData?.slice(0, 50) ?? [], // Limit for preview
      createdAt: playlist.createdAt,
      owner: ownerProfile ? {
        username: ownerProfile.profile?.username,
        avatarUrl: ownerProfile.profile?.avatar_url,
      } : null,
    };
  },
});
```

### Phase 3: Next.js Web Routes

#### Public Share Page (`app/p/[shareId]/page.tsx`)

```typescript
import type { Metadata } from "next";
import { fetchQuery } from "convex/nextjs";
import { api } from "@/convex/_generated/api";
import { PlaylistPreview } from "@/components/PlaylistPreview";
import { notFound } from "next/navigation";

type Props = {
  params: Promise<{ shareId: string }>;
};

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { shareId } = await params;

  const playlist = await fetchQuery(api.public.getPlaylistByShareId, { shareId });

  if (!playlist) {
    return { title: "Playlist Not Found - MixBridge" };
  }

  return {
    title: `${playlist.name} - MixBridge`,
    description: playlist.description || `${playlist.trackCount} tracks curated on MixBridge`,
    openGraph: {
      title: playlist.name,
      description: playlist.description || `Listen to ${playlist.name} on MixBridge`,
      type: "music.playlist",
      url: `https://mixbridge.app/p/${shareId}`,
      images: [
        {
          url: playlist.artwork || "/og-default.png",
          width: 1200,
          height: 630,
          alt: playlist.name,
        },
      ],
      siteName: "MixBridge",
    },
    twitter: {
      card: "summary_large_image",
      title: playlist.name,
      description: playlist.description || `${playlist.trackCount} tracks on MixBridge`,
    },
    other: {
      "apple-itunes-app": `app-id=YOUR_APP_ID, app-argument=https://mixbridge.app/p/${shareId}`,
    },
  };
}

export default async function SharePage({ params }: Props) {
  const { shareId } = await params;

  const playlist = await fetchQuery(api.public.getPlaylistByShareId, { shareId });

  if (!playlist) {
    notFound();
  }

  return (
    <main className="min-h-screen bg-gradient-to-b from-gray-900 to-black">
      <PlaylistPreview playlist={playlist} shareId={shareId} />
    </main>
  );
}
```

#### Dynamic OG Image (`app/p/[shareId]/opengraph-image.tsx`)

```typescript
import { ImageResponse } from "next/og";
import { fetchQuery } from "convex/nextjs";
import { api } from "@/convex/_generated/api";

export const alt = "MixBridge Playlist";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image({
  params,
}: {
  params: Promise<{ shareId: string }>;
}) {
  const { shareId } = await params;
  const playlist = await fetchQuery(api.public.getPlaylistByShareId, { shareId });

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          background: "linear-gradient(135deg, #1a1a2e 0%, #16213e 100%)",
          padding: 60,
        }}
      >
        {/* Artwork */}
        <div style={{ width: 400, height: 400, borderRadius: 20, overflow: "hidden" }}>
          {playlist?.artwork ? (
            <img src={playlist.artwork} style={{ width: "100%", height: "100%" }} />
          ) : (
            <div style={{ width: "100%", height: "100%", background: "#333" }} />
          )}
        </div>

        {/* Info */}
        <div style={{ marginLeft: 60, display: "flex", flexDirection: "column", justifyContent: "center" }}>
          <div style={{ fontSize: 28, color: "#888", marginBottom: 20 }}>MixBridge Playlist</div>
          <div style={{ fontSize: 56, color: "white", fontWeight: "bold", marginBottom: 20 }}>
            {playlist?.name || "Playlist"}
          </div>
          <div style={{ fontSize: 32, color: "#aaa" }}>
            {playlist?.trackCount || 0} tracks
          </div>
          {playlist?.owner?.username && (
            <div style={{ fontSize: 24, color: "#666", marginTop: 20 }}>
              by @{playlist.owner.username}
            </div>
          )}
        </div>
      </div>
    ),
    { ...size }
  );
}
```

### Phase 4: iOS Universal Links Setup

#### Associated Domains Entitlement

Add to `mixbridge.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:mixbridge.app</string>
        <string>webcredentials:mixbridge.app</string>
    </array>
</dict>
</plist>
```

#### Apple App Site Association (Web Server)

Host at `https://mixbridge.app/.well-known/apple-app-site-association`:
```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["TEAMID.com.mixbridge.app"],
        "components": [
          { "/": "/p/*", "comment": "Shared playlists" }
        ]
      }
    ]
  }
}
```

#### Deep Link Router (`DeepLinkRouter.swift`)

```swift
import SwiftUI

@MainActor
@Observable
final class DeepLinkRouter {
    var pendingDeepLink: DeepLink?

    enum DeepLink: Equatable {
        case sharedPlaylist(shareId: String)
    }

    func handle(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.host,
              host == "mixbridge.app" else {
            return
        }

        let pathComponents = components.path.split(separator: "/").map(String.init)

        // Handle /p/{shareId}
        if pathComponents.count >= 2, pathComponents[0] == "p" {
            let shareId = pathComponents[1]
            pendingDeepLink = .sharedPlaylist(shareId: shareId)
        }
    }
}
```

#### App Entry Point Update (`mixbridgeApp.swift`)

```swift
@main
struct mixbridgeApp: App {
    @State private var deepLinkRouter = DeepLinkRouter()
    // ... existing state ...

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deepLinkRouter)
                // ... existing environment ...
                .onOpenURL { url in
                    deepLinkRouter.handle(url: url)
                }
        }
    }
}
```

### Phase 5: iOS Share UI

#### Share Button in PlaylistDetailView

```swift
// Add to PlaylistDetailView.swift toolbar
ToolbarItem(placement: .topBarTrailing) {
    Menu {
        if playlist.isUserCreated {
            ShareLink(
                item: shareURL ?? URL(string: "https://mixbridge.app")!,
                subject: Text(playlist.name),
                message: Text("Check out this playlist on MixBridge!")
            ) {
                Label("Share Playlist", systemImage: "square.and.arrow.up")
            }
            .disabled(shareURL == nil)
            .task {
                await generateShareLink()
            }

            Button {
                toggleVisibility()
            } label: {
                Label(
                    isPublic ? "Make Private" : "Make Public",
                    systemImage: isPublic ? "lock" : "globe"
                )
            }
        }

        Button {
            downloadAllTracks()
        } label: {
            Label("Download All", systemImage: "arrow.down.circle")
        }

        if playlist.isUserCreated {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Playlist", systemImage: "trash")
            }
        }
    } label: {
        Image(systemName: "ellipsis.circle")
    }
}
```

#### SharedPlaylistView Component

```swift
struct SharedPlaylistView: View {
    let shareId: String
    @State private var playlist: SharedPlaylist?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading playlist...")
            } else if let error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                }
            } else if let playlist {
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        PlaylistHeader(playlist: playlist)

                        // Actions
                        HStack(spacing: 16) {
                            Button {
                                addToLibrary()
                            } label: {
                                Label("Add to Library", systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                playAll()
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal)

                        // Track list
                        LazyVStack(spacing: 0) {
                            ForEach(playlist.tracks, id: \.id) { track in
                                TrackRow(track: track)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Shared Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPlaylist()
        }
    }

    private func loadPlaylist() async {
        do {
            playlist = try await ConvexService.shared.getPublicPlaylist(shareId: shareId)
            isLoading = false
        } catch {
            self.error = "This playlist is no longer available"
            isLoading = false
        }
    }
}
```

---

## Acceptance Criteria

### Functional Requirements

- [ ] User can tap "Share" on any user-created playlist
- [ ] Share sheet presents with URL: `https://mixbridge.app/p/{shareId}`
- [ ] User can toggle playlist visibility (public/private)
- [ ] Private playlists cannot be accessed via share link
- [ ] Web preview page displays playlist name, artwork, track count, and track list
- [ ] Open Graph metadata renders correctly in social media previews
- [ ] Universal Link opens app directly when app is installed
- [ ] App navigates to SharedPlaylistView when opened via Universal Link
- [ ] User can add shared playlist to their library
- [ ] User can play tracks from shared playlist

### Non-Functional Requirements

- [ ] Share ID generation is collision-resistant (12-char NanoID)
- [ ] Public query endpoint has rate limiting (60 req/min/IP)
- [ ] Web preview page loads in under 2 seconds
- [ ] Open Graph image is dynamically generated with playlist artwork

### Quality Gates

- [ ] Unit tests for share ID generation and collision handling
- [ ] Integration tests for Convex public query
- [ ] E2E test for complete share flow (iOS -> Web -> iOS)
- [ ] Universal Links tested on physical device
- [ ] Social preview tested on Twitter, iMessage, WhatsApp

---

## Success Metrics

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Share link creation rate | 10% of active users | Analytics: `share_link_created` events |
| Share link click-through | 30% of shared links | Analytics: `share_link_opened` events |
| App installs from share | 5% of non-user clicks | Attribution tracking |
| Library additions from share | 20% of app opens from share | Analytics: `playlist_added_from_share` |

---

## Dependencies & Prerequisites

### Backend (Convex)
- [ ] Install `nanoid` package for share ID generation
- [ ] Schema migration for new fields
- [ ] Deploy public query endpoint

### Web (Next.js)
- [ ] Create `/p/[shareId]` route
- [ ] Configure Open Graph image generation
- [ ] Deploy AASA file to `.well-known/`

### iOS
- [ ] Add Associated Domains capability in Xcode
- [ ] Update provisioning profile with entitlement
- [ ] Submit app update with Universal Links support

### Infrastructure
- [ ] Configure CDN caching for AASA file
- [ ] Set up rate limiting for public endpoints
- [ ] Configure analytics events

---

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Universal Links not triggering | Medium | High | Test on physical devices; implement fallback to web |
| Share ID collisions | Low | Medium | Retry logic with 10 attempts; monitoring for collision rate |
| Rate limiting abuse | Medium | Medium | Implement per-IP and global rate limits |
| SoundCloud track playback issues | Medium | High | Verify API terms; implement error handling |
| AASA file caching delays | Medium | Low | Use developer mode for testing; document cache TTL |

---

## Implementation Phases

### Phase 1: Foundation (Backend)
- [ ] Add `nanoid` to Convex dependencies
- [ ] Create schema migration for share fields
- [ ] Implement `createShareLink` mutation
- [ ] Implement `getPlaylistByShareId` public query
- [ ] Implement `updateVisibility` mutation
- [ ] Add rate limiting middleware

### Phase 2: Web Experience
- [ ] Create `/p/[shareId]/page.tsx` route
- [ ] Implement `generateMetadata` for Open Graph
- [ ] Create `opengraph-image.tsx` for dynamic images
- [ ] Build `PlaylistPreview` component
- [ ] Add Smart App Banner meta tag
- [ ] Deploy AASA file to `.well-known/`

### Phase 3: iOS Deep Linking
- [ ] Add Associated Domains entitlement
- [ ] Create `DeepLinkRouter.swift`
- [ ] Add `.onOpenURL` handler to app entry point
- [ ] Build `SharedPlaylistView` component
- [ ] Implement "Add to Library" action

### Phase 4: iOS Share UI
- [ ] Add share button to `PlaylistDetailView` toolbar
- [ ] Implement visibility toggle UI
- [ ] Add share confirmation feedback
- [ ] Update `ConvexService` with new mutations

### Phase 5: Testing & Polish
- [ ] E2E testing on physical devices
- [ ] Social preview testing (Twitter, iMessage, WhatsApp)
- [ ] Performance optimization
- [ ] Analytics integration
- [ ] Documentation

---

## Future Considerations

### Potential Enhancements
- **Collaborative playlists**: Multiple users can add/remove tracks
- **Share analytics**: View count, click-through tracking
- **QR code generation**: For in-person sharing
- **App Clips**: Instant preview without full app install
- **Expiring links**: Time-limited share URLs
- **Password-protected playlists**: Additional access control

### Technical Debt to Address
- Consider migrating from custom URL scheme to Universal Links for OAuth
- Evaluate caching strategy for public playlist data
- Plan for handling deleted playlists with active share links

---

## References

### Internal References
- `convex/customPlaylists.ts:1-50` - Current playlist schema
- `mixbridge/Views/Playlist/PlaylistDetailView.swift:1-200` - Current playlist UI
- `mixbridge/Services/ConvexService.swift:1-100` - Backend communication

### External References
- [Apple Universal Links Documentation](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)
- [NanoID Collision Calculator](https://zelark.github.io/nano-id-cc/)
- [Next.js Metadata API](https://nextjs.org/docs/app/api-reference/functions/generate-metadata)
- [Convex Public Functions](https://docs.convex.dev/functions/query-functions)

### Related Work
- Apple Music sharing: `music.apple.com/playlist/...`
- Spotify sharing: `open.spotify.com/playlist/...`
