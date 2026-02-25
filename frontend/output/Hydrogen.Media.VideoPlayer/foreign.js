// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                   // hydrogen // video-player
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Custom video player FFI with keyboard controls, fullscreen, PiP support

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // utilities
// ═══════════════════════════════════════════════════════════════════════════════

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

/**
 * Format time in seconds to HH:MM:SS or MM:SS
 */
const formatTime = (seconds) => {
  if (!isFinite(seconds) || seconds < 0) return "0:00";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  const pad = (n) => n.toString().padStart(2, "0");
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
};

/**
 * Get buffered percentage
 */
const getBufferedPercent = (video) => {
  if (!video || !video.buffered || video.buffered.length === 0) return 0;
  const bufferedEnd = video.buffered.end(video.buffered.length - 1);
  return video.duration > 0 ? (bufferedEnd / video.duration) * 100 : 0;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                          // player initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize video player with all event handlers
 */
export const initVideoPlayerImpl = (containerId, config) => {
  const container = document.getElementById(containerId);
  if (!container) return null;

  const video = container.querySelector("video");
  if (!video) return null;

  let state = {
    isPlaying: false,
    currentTime: 0,
    duration: 0,
    volume: 1,
    muted: false,
    playbackRate: 1,
    isFullscreen: false,
    isPiP: false,
    isBuffering: false,
    controlsTimeout: null,
    thumbnailTimeout: null,
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                              // video events
  // ─────────────────────────────────────────────────────────────────────────────

  const onPlay = () => {
    state.isPlaying = true;
    config.onPlay();
  };

  const onPause = () => {
    state.isPlaying = false;
    config.onPause();
  };

  const onEnded = () => {
    state.isPlaying = false;
    config.onEnded();
  };

  const onTimeUpdate = () => {
    state.currentTime = video.currentTime;
    state.duration = video.duration || 0;
    config.onTimeUpdate(video.currentTime)(video.duration || 0)();
  };

  const onVolumeChange = () => {
    state.volume = video.volume;
    state.muted = video.muted;
    config.onVolumeChange(video.volume)(video.muted)();
  };

  const onRateChange = () => {
    state.playbackRate = video.playbackRate;
    config.onPlaybackRateChange(video.playbackRate)();
  };

  const onWaiting = () => {
    state.isBuffering = true;
    config.onBuffering(true)();
  };

  const onCanPlay = () => {
    state.isBuffering = false;
    config.onBuffering(false)();
  };

  const onError = () => {
    const error = video.error;
    if (error) {
      config.onError({
        code: error.code,
        message: error.message || getErrorMessage(error.code),
      })();
    }
  };

  const getErrorMessage = (code) => {
    switch (code) {
      case 1:
        return "Media playback aborted";
      case 2:
        return "Network error occurred";
      case 3:
        return "Media decode error";
      case 4:
        return "Source not supported";
      default:
        return "Unknown error";
    }
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                           // fullscreen events
  // ─────────────────────────────────────────────────────────────────────────────

  const onFullscreenChange = () => {
    state.isFullscreen = !!(
      document.fullscreenElement ||
      document.webkitFullscreenElement ||
      document.mozFullScreenElement
    );
    config.onFullscreenChange(state.isFullscreen)();
  };

  const onPiPChange = () => {
    state.isPiP = document.pictureInPictureElement === video;
    config.onPiPChange(state.isPiP)();
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                           // keyboard controls
  // ─────────────────────────────────────────────────────────────────────────────

  const handleKeyDown = (e) => {
    if (!config.enableKeyboard) return;

    // Don't handle if focus is on input/textarea
    const tagName = document.activeElement?.tagName.toLowerCase();
    if (tagName === "input" || tagName === "textarea") return;

    switch (e.key.toLowerCase()) {
      case " ":
      case "k":
        e.preventDefault();
        if (state.isPlaying) {
          video.pause();
        } else {
          video.play();
        }
        break;

      case "arrowleft":
      case "j":
        e.preventDefault();
        video.currentTime = Math.max(0, video.currentTime - 10);
        break;

      case "arrowright":
      case "l":
        e.preventDefault();
        video.currentTime = Math.min(video.duration, video.currentTime + 10);
        break;

      case "arrowup":
        e.preventDefault();
        video.volume = clamp(video.volume + 0.1, 0, 1);
        break;

      case "arrowdown":
        e.preventDefault();
        video.volume = clamp(video.volume - 0.1, 0, 1);
        break;

      case "m":
        e.preventDefault();
        video.muted = !video.muted;
        break;

      case "f":
        e.preventDefault();
        toggleFullscreen();
        break;

      case "escape":
        if (state.isFullscreen) {
          exitFullscreen();
        }
        break;

      case "0":
      case "1":
      case "2":
      case "3":
      case "4":
      case "5":
      case "6":
      case "7":
      case "8":
      case "9": {
        e.preventDefault();
        const percent = parseInt(e.key) / 10;
        video.currentTime = video.duration * percent;
        break;
      }

      case ",":
        e.preventDefault();
        video.currentTime = Math.max(0, video.currentTime - (1 / 30));
        break;

      case ".":
        e.preventDefault();
        video.currentTime = Math.min(video.duration, video.currentTime + (1 / 30));
        break;

      case "<":
        e.preventDefault();
        decreasePlaybackRate();
        break;

      case ">":
        e.preventDefault();
        increasePlaybackRate();
        break;
    }
  };

  const playbackRates = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];

  const decreasePlaybackRate = () => {
    const currentIndex = playbackRates.indexOf(video.playbackRate);
    if (currentIndex > 0) {
      video.playbackRate = playbackRates[currentIndex - 1];
    }
  };

  const increasePlaybackRate = () => {
    const currentIndex = playbackRates.indexOf(video.playbackRate);
    if (currentIndex < playbackRates.length - 1) {
      video.playbackRate = playbackRates[currentIndex + 1];
    }
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                                // double-click
  // ─────────────────────────────────────────────────────────────────────────────

  const handleDoubleClick = (e) => {
    if (e.target === video || e.target.classList.contains("video-player")) {
      toggleFullscreen();
    }
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                            // controls toggle
  // ─────────────────────────────────────────────────────────────────────────────

  const showControls = () => {
    container.setAttribute("data-controls-visible", "true");
    clearControlsTimeout();
    if (state.isPlaying) {
      state.controlsTimeout = setTimeout(hideControls, 3000);
    }
  };

  const hideControls = () => {
    if (state.isPlaying) {
      container.setAttribute("data-controls-visible", "false");
    }
  };

  const clearControlsTimeout = () => {
    if (state.controlsTimeout) {
      clearTimeout(state.controlsTimeout);
      state.controlsTimeout = null;
    }
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                              // fullscreen api
  // ─────────────────────────────────────────────────────────────────────────────

  const enterFullscreen = () => {
    if (container.requestFullscreen) {
      container.requestFullscreen();
    } else if (container.webkitRequestFullscreen) {
      container.webkitRequestFullscreen();
    } else if (container.mozRequestFullScreen) {
      container.mozRequestFullScreen();
    }
  };

  const exitFullscreen = () => {
    if (document.exitFullscreen) {
      document.exitFullscreen();
    } else if (document.webkitExitFullscreen) {
      document.webkitExitFullscreen();
    } else if (document.mozCancelFullScreen) {
      document.mozCancelFullScreen();
    }
  };

  const toggleFullscreen = () => {
    if (state.isFullscreen) {
      exitFullscreen();
    } else {
      enterFullscreen();
    }
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                          // picture-in-picture
  // ─────────────────────────────────────────────────────────────────────────────

  const enterPiP = async () => {
    try {
      if (document.pictureInPictureEnabled && !video.disablePictureInPicture) {
        await video.requestPictureInPicture();
      }
    } catch (err) {
      console.warn("PiP not available:", err);
    }
  };

  const exitPiP = async () => {
    try {
      if (document.pictureInPictureElement) {
        await document.exitPictureInPicture();
      }
    } catch (err) {
      console.warn("Failed to exit PiP:", err);
    }
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                             // progress bar
  // ─────────────────────────────────────────────────────────────────────────────

  const setupProgressBar = () => {
    const progressBar = container.querySelector('[aria-label="Video progress"]');
    if (!progressBar) return;

    let isDragging = false;

    const seekTo = (e) => {
      const rect = progressBar.getBoundingClientRect();
      const percent = clamp((e.clientX - rect.left) / rect.width, 0, 1);
      video.currentTime = percent * video.duration;
    };

    progressBar.addEventListener("mousedown", (e) => {
      isDragging = true;
      seekTo(e);
    });

    document.addEventListener("mousemove", (e) => {
      if (isDragging) {
        seekTo(e);
      }
    });

    document.addEventListener("mouseup", () => {
      isDragging = false;
    });

    // Touch support
    progressBar.addEventListener("touchstart", (e) => {
      isDragging = true;
      const touch = e.touches[0];
      const rect = progressBar.getBoundingClientRect();
      const percent = clamp((touch.clientX - rect.left) / rect.width, 0, 1);
      video.currentTime = percent * video.duration;
    });

    progressBar.addEventListener("touchmove", (e) => {
      if (!isDragging) return;
      const touch = e.touches[0];
      const rect = progressBar.getBoundingClientRect();
      const percent = clamp((touch.clientX - rect.left) / rect.width, 0, 1);
      video.currentTime = percent * video.duration;
    });

    progressBar.addEventListener("touchend", () => {
      isDragging = false;
    });
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                              // volume slider
  // ─────────────────────────────────────────────────────────────────────────────

  const setupVolumeSlider = () => {
    const volumeSlider = container.querySelector('[aria-label="Volume"]');
    if (!volumeSlider) return;

    let isDragging = false;

    const setVolume = (e) => {
      const rect = volumeSlider.getBoundingClientRect();
      const percent = clamp((e.clientX - rect.left) / rect.width, 0, 1);
      video.volume = percent;
      if (percent > 0) video.muted = false;
    };

    volumeSlider.addEventListener("mousedown", (e) => {
      isDragging = true;
      setVolume(e);
    });

    document.addEventListener("mousemove", (e) => {
      if (isDragging) {
        setVolume(e);
      }
    });

    document.addEventListener("mouseup", () => {
      isDragging = false;
    });
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                            // event listeners
  // ─────────────────────────────────────────────────────────────────────────────

  video.addEventListener("play", onPlay);
  video.addEventListener("pause", onPause);
  video.addEventListener("ended", onEnded);
  video.addEventListener("timeupdate", onTimeUpdate);
  video.addEventListener("volumechange", onVolumeChange);
  video.addEventListener("ratechange", onRateChange);
  video.addEventListener("waiting", onWaiting);
  video.addEventListener("canplay", onCanPlay);
  video.addEventListener("error", onError);
  video.addEventListener("enterpictureinpicture", onPiPChange);
  video.addEventListener("leavepictureinpicture", onPiPChange);

  document.addEventListener("fullscreenchange", onFullscreenChange);
  document.addEventListener("webkitfullscreenchange", onFullscreenChange);
  document.addEventListener("mozfullscreenchange", onFullscreenChange);

  container.addEventListener("keydown", handleKeyDown);
  container.addEventListener("dblclick", handleDoubleClick);
  container.addEventListener("mousemove", showControls);
  container.addEventListener("mouseleave", () => {
    if (state.isPlaying) hideControls();
  });

  setupProgressBar();
  setupVolumeSlider();

  // Initialize controls visibility
  showControls();

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                                   // cleanup
  // ─────────────────────────────────────────────────────────────────────────────

  return {
    container,
    video,
    state,
    destroy: () => {
      video.removeEventListener("play", onPlay);
      video.removeEventListener("pause", onPause);
      video.removeEventListener("ended", onEnded);
      video.removeEventListener("timeupdate", onTimeUpdate);
      video.removeEventListener("volumechange", onVolumeChange);
      video.removeEventListener("ratechange", onRateChange);
      video.removeEventListener("waiting", onWaiting);
      video.removeEventListener("canplay", onCanPlay);
      video.removeEventListener("error", onError);
      video.removeEventListener("enterpictureinpicture", onPiPChange);
      video.removeEventListener("leavepictureinpicture", onPiPChange);

      document.removeEventListener("fullscreenchange", onFullscreenChange);
      document.removeEventListener("webkitfullscreenchange", onFullscreenChange);
      document.removeEventListener("mozfullscreenchange", onFullscreenChange);

      container.removeEventListener("keydown", handleKeyDown);
      container.removeEventListener("dblclick", handleDoubleClick);
      container.removeEventListener("mousemove", showControls);

      clearControlsTimeout();
    },
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // player control
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Play video
 */
export const playImpl = (player) => {
  if (player?.video) {
    player.video.play().catch(() => {});
  }
};

/**
 * Pause video
 */
export const pauseImpl = (player) => {
  if (player?.video) {
    player.video.pause();
  }
};

/**
 * Seek to time
 */
export const seekImpl = (player, time) => {
  if (player?.video) {
    player.video.currentTime = clamp(time, 0, player.video.duration || 0);
  }
};

/**
 * Set volume
 */
export const setVolumeImpl = (player, volume) => {
  if (player?.video) {
    player.video.volume = clamp(volume, 0, 1);
  }
};

/**
 * Set muted
 */
export const setMutedImpl = (player, muted) => {
  if (player?.video) {
    player.video.muted = muted;
  }
};

/**
 * Set playback rate
 */
export const setPlaybackRateImpl = (player, rate) => {
  if (player?.video) {
    player.video.playbackRate = clamp(rate, 0.25, 4);
  }
};

/**
 * Set quality (changes video source)
 */
export const setQualityImpl = (player, qualitySrc) => {
  if (!player?.video) return;

  const currentTime = player.video.currentTime;
  const wasPlaying = !player.video.paused;

  player.video.src = qualitySrc;
  player.video.currentTime = currentTime;

  if (wasPlaying) {
    player.video.play().catch(() => {});
  }
};

/**
 * Set caption track
 */
export const setCaptionImpl = (player, srclang) => {
  if (!player?.video) return;

  const tracks = player.video.textTracks;
  for (let i = 0; i < tracks.length; i++) {
    tracks[i].mode = tracks[i].language === srclang ? "showing" : "hidden";
  }
};

/**
 * Enter fullscreen
 */
export const enterFullscreenImpl = (player) => {
  if (!player?.container) return;

  if (player.container.requestFullscreen) {
    player.container.requestFullscreen();
  } else if (player.container.webkitRequestFullscreen) {
    player.container.webkitRequestFullscreen();
  }
};

/**
 * Exit fullscreen
 */
export const exitFullscreenImpl = (_player) => {
  if (document.exitFullscreen) {
    document.exitFullscreen();
  } else if (document.webkitExitFullscreen) {
    document.webkitExitFullscreen();
  }
};

/**
 * Enter Picture-in-Picture
 */
export const enterPiPImpl = async (player) => {
  if (!player?.video) return;

  try {
    if (document.pictureInPictureEnabled) {
      await player.video.requestPictureInPicture();
    }
  } catch (err) {
    console.warn("PiP error:", err);
  }
};

/**
 * Exit Picture-in-Picture
 */
export const exitPiPImpl = async (_player) => {
  try {
    if (document.pictureInPictureElement) {
      await document.exitPictureInPicture();
    }
  } catch (err) {
    console.warn("Exit PiP error:", err);
  }
};

/**
 * Destroy player
 */
export const destroyVideoPlayerImpl = (player) => {
  if (player?.destroy) {
    player.destroy();
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                            // thumbnail preview
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Get thumbnail position for preview sprite
 */
export const getThumbnailPositionImpl = (player, time) => {
  // Thumbnail sprites are typically arranged in a grid
  // This calculates the background-position for CSS
  const thumbWidth = 160;
  const thumbHeight = 90;
  const columns = 10;
  const interval = 10; // seconds per thumbnail

  const index = Math.floor(time / interval);
  const col = index % columns;
  const row = Math.floor(index / columns);

  return `-${col * thumbWidth}px -${row * thumbHeight}px`;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // media session
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Setup MediaSession API for OS integration
 */
export const setupMediaSession = (title, artist, artwork) => () => {
  if (!("mediaSession" in navigator)) return;

  navigator.mediaSession.metadata = new MediaMetadata({
    title: title || "Video",
    artist: artist || "",
    artwork: artwork
      ? [
          { src: artwork, sizes: "512x512", type: "image/jpeg" },
        ]
      : [],
  });
};

/**
 * Set MediaSession action handlers
 */
export const setMediaSessionHandlers = (handlers) => () => {
  if (!("mediaSession" in navigator)) return;

  if (handlers.onPlay) {
    navigator.mediaSession.setActionHandler("play", handlers.onPlay);
  }
  if (handlers.onPause) {
    navigator.mediaSession.setActionHandler("pause", handlers.onPause);
  }
  if (handlers.onSeekBackward) {
    navigator.mediaSession.setActionHandler("seekbackward", handlers.onSeekBackward);
  }
  if (handlers.onSeekForward) {
    navigator.mediaSession.setActionHandler("seekforward", handlers.onSeekForward);
  }
  if (handlers.onPreviousTrack) {
    navigator.mediaSession.setActionHandler("previoustrack", handlers.onPreviousTrack);
  }
  if (handlers.onNextTrack) {
    navigator.mediaSession.setActionHandler("nexttrack", handlers.onNextTrack);
  }
};
