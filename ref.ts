"use client";

import {
	createContext,
	type ReactNode,
	useCallback,
	useContext,
	useEffect,
	useRef,
	useState,
} from "react";
import { useMutation, useQuery } from "convex/react";
import Hls, { Events, ErrorTypes } from "hls.js";
import type { SoundCloudTrack } from "@/backend/soundcloud/types";
import { type AuthUser, getAuthUserClient } from "@/lib/auth-client";
import { api } from "../../convex/_generated/api";
import type { Id } from "../../convex/_generated/dataModel";
import { createHlsConfig, createPreloadHlsConfig, getHlsImplementation } from "@/lib/hls-config";
import { buildApiUrl, getStreamInfoCached } from "@/lib/stream-detector";

// ============================================================================
// TYPES
// ============================================================================

type PlaybackStatus = "idle" | "loading" | "ready" | "playing" | "paused" | "blocked" | "error";

interface PlayTrackOptions {
	autoPlay?: boolean;
	fromQueueSync?: boolean;
	startTime?: number;
	forceReload?: boolean;
}

interface PlaybackControlOptions {
	skipSync?: boolean;
}

interface PlayerContextType {
	currentTrack: SoundCloudTrack | null;
	isPlaying: boolean;
	playbackStatus: PlaybackStatus;
	autoplayBlocked: boolean;
	volume: number;
	currentTime: number;
	duration: number;
	queue: SoundCloudTrack[];
	currentTrackIndex: number;
	playTrack: (track: SoundCloudTrack, options?: PlayTrackOptions) => Promise<void>;
	pause: (options?: PlaybackControlOptions) => Promise<void>;
	resume: (options?: PlaybackControlOptions) => Promise<void>;
	seek: (time: number) => void;
	setVolume: (volume: number) => void;
	addToQueue: (track: SoundCloudTrack) => void;
	removeFromQueue: (index: number) => void;
	clearQueue: () => void;
	reorderQueue: (fromIndex: number, toIndex: number) => void;
	playQueueTrack: (index: number) => void;
	playNext: () => void;
	playPrevious: () => void;
	audioRef: React.RefObject<HTMLAudioElement | null>;
}

const PlayerContext = createContext<PlayerContextType | null>(null);

// ============================================================================
// CONSTANTS
// ============================================================================

const MAX_RETRY_ATTEMPTS = 3;
const PRELOAD_TRIGGER_PROGRESS = 0.75;
const MAX_CONSECUTIVE_HLS_ERRORS = 3;

// ============================================================================
// UTILITIES
// ============================================================================

const normalizePlaybackTime = (value?: number) => {
	if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
	return Math.max(0, value);
};

// ============================================================================
// PROVIDER
// ============================================================================

export function PlayerProvider({ children }: { children: ReactNode }) {
	// Auth
	const [authUser, setAuthUser] = useState<AuthUser | null>(null);

	// Playback state
	const [currentTrack, setCurrentTrack] = useState<SoundCloudTrack | null>(null);
	const [isPlaying, setIsPlaying] = useState(false);
	const [playbackStatus, setPlaybackStatus] = useState<PlaybackStatus>("idle");
	const [autoplayBlocked, setAutoplayBlocked] = useState(false);
	const [volume, setVolumeState] = useState(0.7);
	const [currentTime, setCurrentTime] = useState(0);
	const [duration, setDuration] = useState(0);
	const [queue, setQueue] = useState<SoundCloudTrack[]>([]);
	const [currentTrackIndex, setCurrentTrackIndex] = useState(-1);

	// Refs
	const audioRef = useRef<HTMLAudioElement>(null);
	const hlsRef = useRef<Hls | null>(null);
	const preloadHlsRef = useRef<Hls | null>(null);
	const preloadAudioRef = useRef<HTMLAudioElement | null>(null);
	const isLoadingRef = useRef(false);
	const playPromiseRef = useRef<Promise<void> | null>(null);
	const sourceLoadedRef = useRef(false);
	const currentTrackIdRef = useRef<number | null>(null);
	const retryCountRef = useRef(0);
	const consecutiveHlsErrorsRef = useRef(0);
	const preloadedTrackIdRef = useRef<number | null>(null);
	const pendingAutoplayTrackRef = useRef<SoundCloudTrack | null>(null);

	// Queue persistence refs
	const queueIdRef = useRef<Id<"queues"> | null>(null);
	const queueTrackIdsRef = useRef<Map<string, string>>(new Map());
	const lastQueueWriteRef = useRef<number>(0);
	const syncTimeoutRef = useRef<NodeJS.Timeout | null>(null);
	const hasAutoLoadedRef = useRef(false);
	const continuousTimeSyncRef = useRef<NodeJS.Timeout | null>(null);
	const lastSyncedTimeRef = useRef<number>(0);

	// Convex
	const queueData = useQuery(
		api.queues.getByUserId,
		authUser ? { userId: authUser.id, paginationOpts: { numItems: 1000, cursor: null } } : "skip",
	);
	const addTrackMutation = useMutation(api.queues.addTrack);
	const removeTrackMutation = useMutation(api.queues.removeTrack);
	const clearTracksMutation = useMutation(api.queues.clearTracks);
	const reorderTracksMutation = useMutation(api.queues.reorderTracks);
	const updateStateMutation = useMutation(api.queues.updateState);
	const createQueueMutation = useMutation(api.queues.create);
	const addPlayMutation = useMutation(api.playHistory.addPlay);

	// ========================================================================
	// CONTINUOUS TIME SYNC
	// ========================================================================

	const startContinuousTimeSync = useCallback(() => {
		// Clear any existing interval
		if (continuousTimeSyncRef.current) {
			clearInterval(continuousTimeSyncRef.current);
		}

		// Sync playback position every second
		continuousTimeSyncRef.current = setInterval(() => {
			if (!queueIdRef.current || !audioRef.current || !isPlaying) return;

			const currentPlaybackTime = audioRef.current.currentTime;
			
			// Only sync if time has changed by at least 0.5 seconds
			// This prevents excessive writes for the same position
			if (Math.abs(currentPlaybackTime - lastSyncedTimeRef.current) >= 0.5) {
				lastSyncedTimeRef.current = currentPlaybackTime;
				
				updateStateMutation({
					queueId: queueIdRef.current,
					currentPosition: currentTrackIndex,
					currentTime: currentPlaybackTime,
					playbackState: "playing",
				}).catch((err) => {
					console.warn("[TimeSync] Failed to sync playback position:", err);
				});
			}
		}, 1000); // Sync every 1 second
	}, [isPlaying, currentTrackIndex, updateStateMutation]);

	const stopContinuousTimeSync = useCallback(() => {
		if (continuousTimeSyncRef.current) {
			clearInterval(continuousTimeSyncRef.current);
			continuousTimeSyncRef.current = null;
		}
	}, []);

	// ========================================================================
	// CLEANUP
	// ========================================================================

	const cleanupHls = useCallback(() => {
		if (hlsRef.current) {
			try {
				hlsRef.current.destroy();
			} catch (err) {
				console.warn("[HLS] Cleanup error:", err);
			}
			hlsRef.current = null;
		}
	}, []);

	const cleanupPreload = useCallback(() => {
		if (preloadHlsRef.current) {
			try {
				preloadHlsRef.current.destroy();
			} catch (err) {
				console.warn("[Preload] Cleanup error:", err);
			}
			preloadHlsRef.current = null;
		}
		if (preloadAudioRef.current) {
			preloadAudioRef.current.pause();
			preloadAudioRef.current.src = "";
			preloadAudioRef.current.load();
		}
		preloadedTrackIdRef.current = null;
	}, []);

	const cleanupAudio = useCallback(async () => {
		if (!audioRef.current) return;

		cleanupHls();
		stopContinuousTimeSync();

		if (playPromiseRef.current) {
			try {
				await playPromiseRef.current;
			} catch {}
			playPromiseRef.current = null;
		}

		audioRef.current.pause();
		audioRef.current.src = "";
		audioRef.current.load();
		setIsPlaying(false);
		setPlaybackStatus("idle");
		setAutoplayBlocked(false);
		sourceLoadedRef.current = false;
		pendingAutoplayTrackRef.current = null;
	}, [cleanupHls, stopContinuousTimeSync]);

	// ========================================================================
	// HLS SETUP
	// ========================================================================

	const setupHlsStream = useCallback(
		(url: string, autoPlay: boolean): Promise<{ autoplayBlocked: boolean }> => {
			return new Promise((resolve, reject) => {
				const audio = audioRef.current;
				if (!audio) return reject(new Error("Audio element not available"));

				cleanupHls();

				const config = createHlsConfig();
				const hls = new Hls(config);
				hlsRef.current = hls;

				hls.on(Events.MANIFEST_PARSED, async () => {
					sourceLoadedRef.current = true;
					audio.volume = volume;
					consecutiveHlsErrorsRef.current = 0;

					if (!autoPlay) {
						setPlaybackStatus("ready");
						return resolve({ autoplayBlocked: false });
					}

					try {
						playPromiseRef.current = audio.play();
						await playPromiseRef.current;
						setIsPlaying(true);
						setPlaybackStatus("playing");
						startContinuousTimeSync();
						resolve({ autoplayBlocked: false });
					} catch (error) {
						if ((error as DOMException)?.name === "NotAllowedError") {
							setAutoplayBlocked(true);
							setPlaybackStatus("blocked");
							resolve({ autoplayBlocked: true });
						} else {
							setPlaybackStatus("error");
							reject(error);
						}
					} finally {
						playPromiseRef.current = null;
					}
				});

				hls.on(Events.ERROR, (_event, data) => {
					if (!data.fatal) return;

					consecutiveHlsErrorsRef.current++;

					if (consecutiveHlsErrorsRef.current >= MAX_CONSECUTIVE_HLS_ERRORS) {
						cleanupHls();
						setPlaybackStatus("error");
						return reject(new Error(`HLS error: ${data.details}`));
					}

					setTimeout(() => {
						if (data.type === ErrorTypes.NETWORK_ERROR) {
							hls.startLoad();
						} else if (data.type === ErrorTypes.MEDIA_ERROR) {
							hls.recoverMediaError();
						} else {
							reject(new Error(`HLS error: ${data.details}`));
						}
					}, 1000);
				});

				hls.loadSource(url);
				hls.attachMedia(audio);
			});
		},
		[volume, cleanupHls, startContinuousTimeSync],
	);

	const setupNativeHls = useCallback(
		(url: string, autoPlay: boolean): Promise<{ autoplayBlocked: boolean }> => {
			return new Promise((resolve, reject) => {
				const audio = audioRef.current;
				if (!audio) return reject(new Error("Audio element not available"));

				let settled = false;
				const cleanup = () => {
					audio.removeEventListener("canplay", handleCanPlay);
					audio.removeEventListener("error", handleError);
				};

				const handleCanPlay = async () => {
					if (settled) return;
					settled = true;
					cleanup();

					sourceLoadedRef.current = true;
					audio.volume = volume;

					if (!autoPlay) {
						setPlaybackStatus("ready");
						return resolve({ autoplayBlocked: false });
					}

					try {
						playPromiseRef.current = audio.play();
						await playPromiseRef.current;
						setIsPlaying(true);
						setPlaybackStatus("playing");
						startContinuousTimeSync();
						resolve({ autoplayBlocked: false });
					} catch (error) {
						if ((error as DOMException)?.name === "NotAllowedError") {
							setAutoplayBlocked(true);
							setPlaybackStatus("blocked");
							resolve({ autoplayBlocked: true });
						} else {
							setPlaybackStatus("error");
							reject(error);
						}
					} finally {
						playPromiseRef.current = null;
					}
				};

				const handleError = (e: Event) => {
					if (settled) return;
					settled = true;
					cleanup();
					const mediaError = (e.target as HTMLAudioElement)?.error;
					reject(new Error(`Native HLS error: ${mediaError?.message}`));
				};

				audio.addEventListener("canplay", handleCanPlay, { once: true });
				audio.addEventListener("error", handleError);
				audio.src = url;
				audio.load();
			});
		},
		[volume, startContinuousTimeSync],
	);

	const setupProgressive = useCallback(
		(url: string, autoPlay: boolean): Promise<{ autoplayBlocked: boolean }> => {
			return new Promise((resolve, reject) => {
				const audio = audioRef.current;
				if (!audio) return reject(new Error("Audio element not available"));

				let settled = false;
				const cleanup = () => {
					audio.removeEventListener("canplay", handleCanPlay);
					audio.removeEventListener("error", handleError);
				};

				const handleCanPlay = async () => {
					if (settled) return;
					settled = true;
					cleanup();

					sourceLoadedRef.current = true;
					audio.volume = volume;

					if (!autoPlay) {
						setPlaybackStatus("ready");
						return resolve({ autoplayBlocked: false });
					}

					try {
						playPromiseRef.current = audio.play();
						await playPromiseRef.current;
						setIsPlaying(true);
						setPlaybackStatus("playing");
						startContinuousTimeSync();
						resolve({ autoplayBlocked: false });
					} catch (error) {
						if ((error as DOMException)?.name === "NotAllowedError") {
							setAutoplayBlocked(true);
							setPlaybackStatus("blocked");
							resolve({ autoplayBlocked: true });
						} else {
							setPlaybackStatus("error");
							reject(error);
						}
					} finally {
						playPromiseRef.current = null;
					}
				};

				const handleError = (e: Event) => {
					if (settled) return;
					settled = true;
					cleanup();
					const mediaError = (e.target as HTMLAudioElement)?.error;
					reject(new Error(`Progressive error: ${mediaError?.message}`));
				};

				audio.addEventListener("canplay", handleCanPlay, { once: true });
				audio.addEventListener("error", handleError);
				audio.src = url;
				audio.load();
			});
		},
		[volume, startContinuousTimeSync],
	);

	// ========================================================================
	// PRELOADING
	// ========================================================================

	const preloadNextTrack = useCallback(async () => {
		if (currentTrackIndex >= queue.length - 1) return;

		const nextTrack = queue[currentTrackIndex + 1];
		if (!nextTrack || preloadedTrackIdRef.current === nextTrack.id) return;

		try {
			cleanupPreload();

			const streamInfo = await getStreamInfoCached(buildApiUrl(nextTrack.id));
			const preloadAudio = new Audio();
			preloadAudio.volume = 0;
			preloadAudioRef.current = preloadAudio;
			preloadedTrackIdRef.current = nextTrack.id;

			if (streamInfo.type === "hls" && Hls.isSupported()) {
				const hls = new Hls(createPreloadHlsConfig());
				preloadHlsRef.current = hls;
				hls.loadSource(streamInfo.url);
				hls.attachMedia(preloadAudio);
			} else if (streamInfo.type === "hls" && preloadAudio.canPlayType("application/vnd.apple.mpegurl")) {
				preloadAudio.src = streamInfo.url;
				preloadAudio.load();
			} else {
				preloadAudio.src = streamInfo.url;
				preloadAudio.load();
			}
		} catch (err) {
			console.warn("[Preload] Failed:", err);
			cleanupPreload();
		}
	}, [currentTrackIndex, queue, cleanupPreload]);

	// ========================================================================
	// PLAYBACK
	// ========================================================================

	const playTrack = useCallback(
		async (track: SoundCloudTrack, options: PlayTrackOptions = {}) => {
			if (!audioRef.current) return;
			if (isLoadingRef.current && currentTrackIdRef.current !== track.id) return;

			const { autoPlay = true, fromQueueSync = false, startTime, forceReload = false } = options;
			const normalizedStartTime = normalizePlaybackTime(startTime);

			// Update track index
			const trackIndex = queue.findIndex((t) => t.id === track.id);
			if (trackIndex !== -1 && trackIndex !== currentTrackIndex) {
				setCurrentTrackIndex(trackIndex);
			}

			// If already loaded, just resume
			if (!forceReload && sourceLoadedRef.current && currentTrackIdRef.current === track.id) {
				setCurrentTrack(track);
				if (normalizedStartTime !== undefined && audioRef.current) {
					audioRef.current.currentTime = normalizedStartTime;
					setCurrentTime(normalizedStartTime);
				}
				if (autoPlay) await resume({ skipSync: true });
				else await pause({ skipSync: true });
				return;
			}

			isLoadingRef.current = true;

			try {
				await cleanupAudio();
				setCurrentTrack(track);
				currentTrackIdRef.current = track.id;
				setPlaybackStatus(autoPlay ? "loading" : "ready");

				if (normalizedStartTime !== undefined) {
					setCurrentTime(normalizedStartTime);
				} else {
					setCurrentTime(0);
				}

				// Get stream
				const streamInfo = await getStreamInfoCached(buildApiUrl(track.id));
				const implementation = getHlsImplementation();

				// Load based on type
				let result: { autoplayBlocked: boolean };
				if (streamInfo.type === "hls" && implementation === "hlsjs") {
					result = await setupHlsStream(streamInfo.url, autoPlay);
				} else if (streamInfo.type === "hls" && implementation === "native") {
					result = await setupNativeHls(streamInfo.url, autoPlay);
				} else {
					result = await setupProgressive(streamInfo.url, autoPlay);
				}

				if (normalizedStartTime !== undefined && audioRef.current) {
					audioRef.current.currentTime = normalizedStartTime;
					setCurrentTime(normalizedStartTime);
				}

				if (result.autoplayBlocked) {
					pendingAutoplayTrackRef.current = track;
					return;
				}

				if (!autoPlay) {
					pendingAutoplayTrackRef.current = track;
					return;
				}

				// Success
				retryCountRef.current = 0;
				pendingAutoplayTrackRef.current = null;

				// Log play
				if (authUser && autoPlay && !fromQueueSync) {
					await addPlayMutation({
						userId: authUser.id,
						trackId: track.id.toString(),
						source: "soundcloud",
						trackData: track,
					}).catch(console.error);
				}

				// Sync queue
				if (queueIdRef.current && !fromQueueSync) {
					await updateStateMutation({
						queueId: queueIdRef.current,
						currentPosition: trackIndex !== -1 ? trackIndex : currentTrackIndex,
						currentTime: audioRef.current?.currentTime ?? normalizedStartTime ?? 0,
						playbackState: "playing",
					}).catch(console.error);
				}
			} catch (error) {
				console.error("[Player] Load failed:", error);

				// Retry
				if (retryCountRef.current < MAX_RETRY_ATTEMPTS && !fromQueueSync) {
					retryCountRef.current++;
					const delay = Math.pow(2, retryCountRef.current - 1) * 1000;
					setTimeout(() => playTrack(track, options), delay);
					return;
				}

				retryCountRef.current = 0;
				setPlaybackStatus("error");

				// Skip to next
				if (!fromQueueSync && currentTrackIndex < queue.length - 1) {
					setTimeout(() => playNext(), 500);
				}
			} finally {
				isLoadingRef.current = false;
			}
		},
		[
			queue,
			currentTrackIndex,
			cleanupAudio,
			setupHlsStream,
			setupNativeHls,
			setupProgressive,
			authUser,
			addPlayMutation,
			updateStateMutation,
		],
	);

	const pause = useCallback(
		async (options: PlaybackControlOptions = {}) => {
			if (!audioRef.current) return;

			if (playPromiseRef.current) {
				try {
					await playPromiseRef.current;
				} catch {}
				playPromiseRef.current = null;
			}

			audioRef.current.pause();
			setIsPlaying(false);
			setPlaybackStatus("paused");
			setAutoplayBlocked(false);
			stopContinuousTimeSync();

			if (!options.skipSync && queueIdRef.current) {
				await updateStateMutation({
					queueId: queueIdRef.current,
					currentPosition: currentTrackIndex,
					currentTime: audioRef.current.currentTime,
					playbackState: "paused",
				}).catch(console.error);
			}
		},
		[currentTrackIndex, updateStateMutation, stopContinuousTimeSync],
	);

	const resume = useCallback(
		async (options: PlaybackControlOptions = {}) => {
			if (!audioRef.current) return;

			if (!sourceLoadedRef.current && currentTrack) {
				await playTrack(currentTrack, { autoPlay: true, startTime: currentTime });
				return;
			}

			if (!sourceLoadedRef.current) return;

			try {
				setPlaybackStatus("loading");
				playPromiseRef.current = audioRef.current.play();
				await playPromiseRef.current;
				setIsPlaying(true);
				setPlaybackStatus("playing");
				setAutoplayBlocked(false);
				startContinuousTimeSync();

				// Track deferred play
				if (authUser && pendingAutoplayTrackRef.current && currentTrack && 
					pendingAutoplayTrackRef.current.id === currentTrack.id) {
					await addPlayMutation({
						userId: authUser.id,
						trackId: currentTrack.id.toString(),
						source: "soundcloud",
						trackData: currentTrack,
					}).catch(console.error);
					pendingAutoplayTrackRef.current = null;
				}

				if (!options.skipSync && queueIdRef.current) {
					await updateStateMutation({
						queueId: queueIdRef.current,
						currentPosition: currentTrackIndex,
						currentTime: audioRef.current?.currentTime || 0,
						playbackState: "playing",
					}).catch(console.error);
				}
			} catch (error) {
				if ((error as DOMException)?.name === "NotAllowedError") {
					setAutoplayBlocked(true);
					setPlaybackStatus("blocked");
					if (currentTrack) pendingAutoplayTrackRef.current = currentTrack;
				} else {
					setPlaybackStatus("error");
				}
				setIsPlaying(false);
			} finally {
				playPromiseRef.current = null;
			}
		},
		[currentTrack, currentTime, playTrack, currentTrackIndex, authUser, addPlayMutation, updateStateMutation, startContinuousTimeSync],
	);

	const seek = useCallback(
		(time: number) => {
			if (!audioRef.current || !sourceLoadedRef.current) return;
			audioRef.current.currentTime = time;
			setCurrentTime(time);

			if (syncTimeoutRef.current) clearTimeout(syncTimeoutRef.current);

			syncTimeoutRef.current = setTimeout(() => {
				if (queueIdRef.current) {
					updateStateMutation({
						queueId: queueIdRef.current,
						currentPosition: currentTrackIndex,
						currentTime: time,
						playbackState: isPlaying ? "playing" : "paused",
					}).catch(console.error);
				}
			}, 500);
		},
		[currentTrackIndex, isPlaying, updateStateMutation],
	);

	const setVolume = useCallback((newVolume: number) => {
		if (audioRef.current) {
			audioRef.current.volume = newVolume;
			setVolumeState(newVolume);
		}
	}, []);

	// ========================================================================
	// QUEUE
	// ========================================================================

	const playNext = useCallback(() => {
		if (isLoadingRef.current || currentTrackIndex >= queue.length - 1) return;
		setCurrentTrackIndex(currentTrackIndex + 1);
		playTrack(queue[currentTrackIndex + 1]);
	}, [isLoadingRef, currentTrackIndex, queue, playTrack]);

	const playPrevious = useCallback(() => {
		if (isLoadingRef.current || currentTrackIndex <= 0) return;
		setCurrentTrackIndex(currentTrackIndex - 1);
		playTrack(queue[currentTrackIndex - 1]);
	}, [isLoadingRef, currentTrackIndex, queue, playTrack]);

	const playQueueTrack = useCallback(
		(index: number) => {
			if (index >= 0 && index < queue.length) {
				setCurrentTrackIndex(index);
				playTrack(queue[index]);
			}
		},
		[queue, playTrack],
	);

	const handleTrackEnd = useCallback(() => {
		setIsPlaying(false);
		if (currentTrackIndex < queue.length - 1) {
			playNext();
		} else {
			setPlaybackStatus("idle");
			if (queueIdRef.current) {
				updateStateMutation({
					queueId: queueIdRef.current,
					currentPosition: currentTrackIndex,
					currentTime: 0,
					playbackState: "stopped",
				}).catch(console.error);
			}
		}
	}, [currentTrackIndex, queue.length, playNext, updateStateMutation]);

	const addToQueue = useCallback(
		async (track: SoundCloudTrack) => {
			if (!queueIdRef.current || queue.some((t) => t.id === track.id)) return;

			try {
				const trackId = await addTrackMutation({
					queueId: queueIdRef.current,
					trackId: track.id.toString(),
					source: "soundcloud",
					title: track.title,
					artist: track.user?.username || "Unknown",
					duration: track.duration,
					artworkUrl: track.artwork_url,
					trackData: track,
					position: queue.length,
				});
				lastQueueWriteRef.current = Date.now();
				queueTrackIdsRef.current.set(track.id.toString(), trackId);

				// Trigger auto-analysis for the added track
				if (authUser) {
					const { getAutoAnalysisLoop } = await import('@/lib/agent/auto-analysis-loop');
					const analysisLoop = getAutoAnalysisLoop();
					analysisLoop.onTrackAdded(track, authUser.id).catch((err) => {
						console.error("[AutoAnalysis] Failed to trigger analysis:", err);
					});
				}
			} catch (err) {
				console.error("[Queue] Add failed:", err);
			}
		},
		[queue, addTrackMutation, authUser],
	);

	const removeFromQueue = useCallback(
		async (index: number) => {
			if (index < 0 || index >= queue.length) return;

			const trackToRemove = queue[index];
			const dbTrackId = queueTrackIdsRef.current.get(trackToRemove.id.toString()) as Id<"queueTracks"> | undefined;
			if (!dbTrackId) return;

			try {
				await removeTrackMutation({ trackId: dbTrackId });
				lastQueueWriteRef.current = Date.now();
				queueTrackIdsRef.current.delete(trackToRemove.id.toString());

				if (index === currentTrackIndex) {
					const newQueue = queue.filter((_, i) => i !== index);
					if (newQueue.length > 0) {
						const newIndex = Math.min(index, newQueue.length - 1);
						setCurrentTrackIndex(newIndex);
						if (isPlaying) playTrack(newQueue[newIndex]);
						else setCurrentTrack(newQueue[newIndex]);
					} else {
						setCurrentTrackIndex(-1);
						setCurrentTrack(null);
						await pause();
					}
				} else if (index < currentTrackIndex) {
					setCurrentTrackIndex(currentTrackIndex - 1);
				}
			} catch (err) {
				console.error("[Queue] Remove failed:", err);
			}
		},
		[queue, currentTrackIndex, isPlaying, playTrack, pause, removeTrackMutation],
	);

	const clearQueue = useCallback(async () => {
		if (!queueIdRef.current) return;
		try {
			await clearTracksMutation({ queueId: queueIdRef.current });
			lastQueueWriteRef.current = Date.now();
			setCurrentTrackIndex(-1);
			setCurrentTrack(null);
			queueTrackIdsRef.current.clear();
			await pause();
		} catch (err) {
			console.error("[Queue] Clear failed:", err);
		}
	}, [pause, clearTracksMutation]);

	const reorderQueue = useCallback(
		async (fromIndex: number, toIndex: number) => {
			if (fromIndex === toIndex || !queueIdRef.current) return;

			try {
				await reorderTracksMutation({ queueId: queueIdRef.current, fromIndex, toIndex });
				lastQueueWriteRef.current = Date.now();

				if (fromIndex === currentTrackIndex) {
					setCurrentTrackIndex(toIndex);
				} else if (fromIndex < currentTrackIndex && toIndex >= currentTrackIndex) {
					setCurrentTrackIndex(currentTrackIndex - 1);
				} else if (fromIndex > currentTrackIndex && toIndex <= currentTrackIndex) {
					setCurrentTrackIndex(currentTrackIndex + 1);
				}
			} catch (err) {
				console.error("[Queue] Reorder failed:", err);
			}
		},
		[currentTrackIndex, reorderTracksMutation],
	);

	// ========================================================================
	// EFFECTS
	// ========================================================================

	useEffect(() => {
		setAuthUser(getAuthUserClient());
	}, []);

	useEffect(() => {
		if (!authUser || queueData !== null) return;
		createQueueMutation({ userId: authUser.id }).then((id) => {
			queueIdRef.current = id;
		}).catch(console.error);
	}, [authUser, queueData, createQueueMutation]);

	useEffect(() => {
		if (!queueData) return;

		queueIdRef.current = queueData._id;

		const loadedTracks = queueData.tracks
			.map((t) => t.trackData as SoundCloudTrack)
			.filter((t): t is SoundCloudTrack => t != null && t.id != null);

		queueTrackIdsRef.current.clear();
		queueData.tracks.forEach((t) => {
			if (t.trackId && t._id) queueTrackIdsRef.current.set(t.trackId, t._id);
		});

		setQueue(loadedTracks);
		const position = queueData.currentPosition ?? -1;
		setCurrentTrackIndex(position);

		// Auto-load first track on initial queue load
		// Multiple safeguards to ensure this doesn't interfere with existing playback:
		// 1. Only if queue has tracks
		// 2. Only if we haven't already auto-loaded
		// 3. Only if no track is currently loaded (currentTrackIdRef)
		// 4. Only if player is idle (not loading, playing, etc)
		// 5. Only if user isn't already interacting with the player
		if (
			loadedTracks.length > 0 && 
			!hasAutoLoadedRef.current && 
			!currentTrackIdRef.current &&
			!isLoadingRef.current &&
			playbackStatus === "idle"
		) {
			// Prefer the track at saved position, fallback to first track
			const trackToLoad = position >= 0 && position < loadedTracks.length 
				? loadedTracks[position]
				: loadedTracks[0];
			
			// Restore the saved playback time
			const savedTime = queueData.currentTime ?? 0;
			
			if (trackToLoad) {
				hasAutoLoadedRef.current = true;
				// Delay execution to ensure:
				// 1. React render cycle completes
				// 2. Player is fully initialized
				// 3. Doesn't block UI thread
				setTimeout(() => {
					// Double-check conditions before loading (user might have started playback)
					if (!currentTrackIdRef.current && !isLoadingRef.current) {
						playTrack(trackToLoad, { 
							autoPlay: false, 
							fromQueueSync: true,
							startTime: savedTime
						}).catch((err) => {
							console.error("[Queue] Auto-load failed:", err);
							// Reset flag on error so retry is possible if needed
							hasAutoLoadedRef.current = false;
						});
					}
				}, 100);
			}
		}
	}, [queueData, playbackStatus]);

	useEffect(() => {
		if (!duration || duration === 0 || currentTrackIndex >= queue.length - 1) return;
		if (currentTime / duration > PRELOAD_TRIGGER_PROGRESS) {
			preloadNextTrack();
		}
	}, [currentTime, duration, currentTrackIndex, queue.length, preloadNextTrack]);

	useEffect(() => {
		const handleKeyDown = (e: KeyboardEvent) => {
			if (
				e.code === "Space" &&
				!["INPUT", "TEXTAREA"].includes((e.target as HTMLElement).tagName) &&
				!(e.target as HTMLElement).isContentEditable
			) {
				e.preventDefault();
				if (isPlaying) pause();
				else if (currentTrack) resume();
			}
		};
		window.addEventListener("keydown", handleKeyDown);
		return () => window.removeEventListener("keydown", handleKeyDown);
	}, [isPlaying, currentTrack, pause, resume]);

	useEffect(() => {
		if (typeof navigator === "undefined" || !("mediaSession" in navigator) || !currentTrack) return;

		const artworkUrl = currentTrack.artwork_url?.replace("-large", "-t500x500");

		navigator.mediaSession.metadata = new MediaMetadata({
			title: currentTrack.title || "Unknown",
			artist: currentTrack.user?.username || "Unknown",
			album: currentTrack.publisher_metadata?.album_title,
			artwork: artworkUrl ? [
				{ src: artworkUrl, sizes: "500x500", type: "image/jpeg" },
				{ src: currentTrack.artwork_url!.replace("-large", "-t300x300"), sizes: "300x300", type: "image/jpeg" },
			] : undefined,
		});

		navigator.mediaSession.playbackState = isPlaying ? "playing" : "paused";

		navigator.mediaSession.setActionHandler("play", () => resume());
		navigator.mediaSession.setActionHandler("pause", () => pause());
		navigator.mediaSession.setActionHandler("nexttrack", currentTrackIndex < queue.length - 1 ? () => playNext() : null);
		navigator.mediaSession.setActionHandler("previoustrack", currentTrackIndex > 0 ? () => playPrevious() : null);
		navigator.mediaSession.setActionHandler("seekto", (details) => {
			if (details.seekTime != null) seek(details.seekTime);
		});
		navigator.mediaSession.setActionHandler("seekbackward", (details) => {
			seek(Math.max(0, currentTime - (details.seekOffset || 10)));
		});
		navigator.mediaSession.setActionHandler("seekforward", (details) => {
			seek(Math.min(duration, currentTime + (details.seekOffset || 10)));
		});

		if (duration > 0 && "setPositionState" in navigator.mediaSession) {
			try {
				navigator.mediaSession.setPositionState({
					duration,
					playbackRate: 1,
					position: currentTime,
				});
			} catch {}
		}

		return () => {
			if ("mediaSession" in navigator) {
				navigator.mediaSession.setActionHandler("play", null);
				navigator.mediaSession.setActionHandler("pause", null);
				navigator.mediaSession.setActionHandler("nexttrack", null);
				navigator.mediaSession.setActionHandler("previoustrack", null);
				navigator.mediaSession.setActionHandler("seekto", null);
				navigator.mediaSession.setActionHandler("seekbackward", null);
				navigator.mediaSession.setActionHandler("seekforward", null);
			}
		};
	}, [currentTrack, isPlaying, currentTime, duration, currentTrackIndex, queue.length, pause, resume, playNext, playPrevious, seek]);

	useEffect(() => {
		return () => {
			cleanupHls();
			cleanupPreload();
			stopContinuousTimeSync();
		};
	}, [cleanupHls, cleanupPreload, stopContinuousTimeSync]);

	// ========================================================================
	// PROVIDER
	// ========================================================================

	return (
		<PlayerContext.Provider
			value={{
				currentTrack,
				isPlaying,
				playbackStatus,
				autoplayBlocked,
				volume,
				currentTime,
				duration,
				queue,
				currentTrackIndex,
				playTrack,
				pause,
				resume,
				seek,
				setVolume,
				addToQueue,
				removeFromQueue,
				clearQueue,
				reorderQueue,
				playQueueTrack,
				playNext,
				playPrevious,
				audioRef,
			}}
		>
			{children}
			<audio
				ref={audioRef}
				preload="auto"
				onTimeUpdate={(e) => setCurrentTime(e.currentTarget.currentTime)}
				onDurationChange={(e) => setDuration(e.currentTarget.duration)}
				onEnded={handleTrackEnd}
				onPlay={() => {
					setIsPlaying(true);
					setPlaybackStatus("playing");
					setAutoplayBlocked(false);
					startContinuousTimeSync();
				}}
				onPause={() => {
					setIsPlaying(false);
					if (!autoplayBlocked) setPlaybackStatus("paused");
					stopContinuousTimeSync();
				}}
			/>
		</PlayerContext.Provider>
	);
}

export function usePlayer() {
	const context = useContext(PlayerContext);
	if (!context) throw new Error("usePlayer must be used within PlayerProvider");
	return context;
}
