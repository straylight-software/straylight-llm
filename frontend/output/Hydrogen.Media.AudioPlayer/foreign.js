// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                                   // hydrogen // audio-player
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Audio player with waveform visualization, spectrum analyzer, and MediaSession

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                   // utilities
// ═══════════════════════════════════════════════════════════════════════════════

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

/**
 * Format time in seconds to MM:SS
 */
const formatTime = (seconds) => {
  if (!isFinite(seconds) || seconds < 0) return "0:00";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                        // player initialization
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Initialize audio player
 */
export const initAudioPlayerImpl = (containerId, config) => {
  const container = document.getElementById(containerId);
  if (!container) return null;

  const audio = container.querySelector("audio") || new Audio();
  
  let state = {
    isPlaying: false,
    currentTime: 0,
    duration: 0,
    volume: 1,
    muted: false,
    playbackRate: 1,
    audioContext: null,
    analyser: null,
    source: null,
    waveformData: null,
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                              // audio events
  // ─────────────────────────────────────────────────────────────────────────────

  const onPlay = () => {
    state.isPlaying = true;
    config.onPlay();
    initAudioContext();
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
    state.currentTime = audio.currentTime;
    state.duration = audio.duration || 0;
    config.onTimeUpdate(audio.currentTime)(audio.duration || 0)();
    
    // Update waveform progress
    updateWaveform();
  };

  const onVolumeChange = () => {
    state.volume = audio.volume;
    state.muted = audio.muted;
    config.onVolumeChange(audio.volume)(audio.muted)();
  };

  const onRateChange = () => {
    state.playbackRate = audio.playbackRate;
    config.onPlaybackRateChange(audio.playbackRate)();
  };

  const onLoadStart = () => {
    config.onLoading(true)();
  };

  const onCanPlay = () => {
    config.onLoading(false)();
  };

  const onError = () => {
    const error = audio.error;
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
  //                                                             // audio context
  // ─────────────────────────────────────────────────────────────────────────────

  const initAudioContext = () => {
    if (state.audioContext) return;

    try {
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      state.audioContext = new AudioContext();
      state.analyser = state.audioContext.createAnalyser();
      state.analyser.fftSize = 256;
      
      state.source = state.audioContext.createMediaElementSource(audio);
      state.source.connect(state.analyser);
      state.analyser.connect(state.audioContext.destination);
    } catch (err) {
      console.warn("AudioContext not available:", err);
    }
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                                  // waveform
  // ─────────────────────────────────────────────────────────────────────────────

  const generateWaveform = async (audioUrl) => {
    try {
      const response = await fetch(audioUrl);
      const arrayBuffer = await response.arrayBuffer();
      
      const offlineContext = new (window.OfflineAudioContext || window.webkitOfflineAudioContext)(
        1, // channels
        44100 * 300, // max 5 minutes
        44100
      );
      
      const audioBuffer = await offlineContext.decodeAudioData(arrayBuffer);
      const rawData = audioBuffer.getChannelData(0);
      
      // Downsample to ~200 points
      const samples = 200;
      const blockSize = Math.floor(rawData.length / samples);
      const filteredData = [];
      
      for (let i = 0; i < samples; i++) {
        let blockStart = blockSize * i;
        let sum = 0;
        for (let j = 0; j < blockSize; j++) {
          sum += Math.abs(rawData[blockStart + j]);
        }
        filteredData.push(sum / blockSize);
      }
      
      // Normalize
      const maxVal = Math.max(...filteredData);
      state.waveformData = filteredData.map(v => v / maxVal);
      
      drawWaveform();
    } catch (err) {
      console.warn("Failed to generate waveform:", err);
    }
  };

  const drawWaveform = () => {
    const canvas = container.querySelector("[data-waveform]");
    if (!canvas || !state.waveformData) return;

    const ctx = canvas.getContext("2d");
    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);
    
    const width = rect.width;
    const height = rect.height;
    const data = state.waveformData;
    const barWidth = width / data.length;
    const progress = state.duration > 0 ? state.currentTime / state.duration : 0;
    const progressX = progress * width;
    
    ctx.clearRect(0, 0, width, height);
    
    // Draw waveform bars
    for (let i = 0; i < data.length; i++) {
      const x = i * barWidth;
      const barHeight = data[i] * height * 0.8;
      const y = (height - barHeight) / 2;
      
      ctx.fillStyle = x < progressX ? "#3B82F6" : "#64748B";
      ctx.fillRect(x, y, barWidth - 1, barHeight);
    }
  };

  const updateWaveform = () => {
    if (state.waveformData) {
      drawWaveform();
    }
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                                  // spectrum
  // ─────────────────────────────────────────────────────────────────────────────

  let animationId = null;

  const drawSpectrum = () => {
    const canvas = container.querySelector("[data-spectrum]");
    if (!canvas || !state.analyser) return;

    const ctx = canvas.getContext("2d");
    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);
    
    const width = rect.width;
    const height = rect.height;
    
    const bufferLength = state.analyser.frequencyBinCount;
    const dataArray = new Uint8Array(bufferLength);
    
    const draw = () => {
      if (!state.isPlaying) return;
      
      animationId = requestAnimationFrame(draw);
      state.analyser.getByteFrequencyData(dataArray);
      
      ctx.clearRect(0, 0, width, height);
      
      const barCount = 32;
      const barWidth = width / barCount;
      const step = Math.floor(bufferLength / barCount);
      
      for (let i = 0; i < barCount; i++) {
        const value = dataArray[i * step];
        const barHeight = (value / 255) * height;
        const x = i * barWidth;
        const y = height - barHeight;
        
        // Gradient color based on frequency
        const hue = (i / barCount) * 60 + 200; // Blue to purple
        ctx.fillStyle = `hsl(${hue}, 70%, 60%)`;
        ctx.fillRect(x, y, barWidth - 2, barHeight);
      }
    };
    
    draw();
  };

  const stopSpectrum = () => {
    if (animationId) {
      cancelAnimationFrame(animationId);
      animationId = null;
    }
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                           // keyboard controls
  // ─────────────────────────────────────────────────────────────────────────────

  const handleKeyDown = (e) => {
    if (!config.enableKeyboard) return;

    const tagName = document.activeElement?.tagName.toLowerCase();
    if (tagName === "input" || tagName === "textarea") return;

    switch (e.key.toLowerCase()) {
      case " ":
      case "k":
        e.preventDefault();
        if (state.isPlaying) {
          audio.pause();
        } else {
          audio.play();
        }
        break;

      case "arrowleft":
      case "j":
        e.preventDefault();
        audio.currentTime = Math.max(0, audio.currentTime - 10);
        break;

      case "arrowright":
      case "l":
        e.preventDefault();
        audio.currentTime = Math.min(audio.duration, audio.currentTime + 10);
        break;

      case "arrowup":
        e.preventDefault();
        audio.volume = clamp(audio.volume + 0.1, 0, 1);
        break;

      case "arrowdown":
        e.preventDefault();
        audio.volume = clamp(audio.volume - 0.1, 0, 1);
        break;

      case "m":
        e.preventDefault();
        audio.muted = !audio.muted;
        break;
    }
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                             // progress bar
  // ─────────────────────────────────────────────────────────────────────────────

  const setupProgressBar = () => {
    const progressBar = container.querySelector('[role="slider"]');
    if (!progressBar) return;

    let isDragging = false;

    const seekTo = (e) => {
      const rect = progressBar.getBoundingClientRect();
      const percent = clamp((e.clientX - rect.left) / rect.width, 0, 1);
      audio.currentTime = percent * audio.duration;
    };

    progressBar.addEventListener("mousedown", (e) => {
      isDragging = true;
      seekTo(e);
    });

    document.addEventListener("mousemove", (e) => {
      if (isDragging) seekTo(e);
    });

    document.addEventListener("mouseup", () => {
      isDragging = false;
    });

    // Touch support
    progressBar.addEventListener("touchstart", (e) => {
      const touch = e.touches[0];
      const rect = progressBar.getBoundingClientRect();
      const percent = clamp((touch.clientX - rect.left) / rect.width, 0, 1);
      audio.currentTime = percent * audio.duration;
    });
  };

  const setupWaveformSeek = () => {
    const waveform = container.querySelector("[data-waveform]");
    if (!waveform) return;

    waveform.addEventListener("click", (e) => {
      const rect = waveform.getBoundingClientRect();
      const percent = clamp((e.clientX - rect.left) / rect.width, 0, 1);
      audio.currentTime = percent * audio.duration;
    });
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                            // event listeners
  // ─────────────────────────────────────────────────────────────────────────────

  audio.addEventListener("play", onPlay);
  audio.addEventListener("pause", onPause);
  audio.addEventListener("ended", onEnded);
  audio.addEventListener("timeupdate", onTimeUpdate);
  audio.addEventListener("volumechange", onVolumeChange);
  audio.addEventListener("ratechange", onRateChange);
  audio.addEventListener("loadstart", onLoadStart);
  audio.addEventListener("canplay", onCanPlay);
  audio.addEventListener("error", onError);

  container.addEventListener("keydown", handleKeyDown);

  setupProgressBar();
  setupWaveformSeek();

  // ─────────────────────────────────────────────────────────────────────────────
  //                                                                   // cleanup
  // ─────────────────────────────────────────────────────────────────────────────

  return {
    container,
    audio,
    state,
    generateWaveform,
    drawSpectrum,
    stopSpectrum,
    destroy: () => {
      audio.removeEventListener("play", onPlay);
      audio.removeEventListener("pause", onPause);
      audio.removeEventListener("ended", onEnded);
      audio.removeEventListener("timeupdate", onTimeUpdate);
      audio.removeEventListener("volumechange", onVolumeChange);
      audio.removeEventListener("ratechange", onRateChange);
      audio.removeEventListener("loadstart", onLoadStart);
      audio.removeEventListener("canplay", onCanPlay);
      audio.removeEventListener("error", onError);
      container.removeEventListener("keydown", handleKeyDown);
      stopSpectrum();
      
      if (state.audioContext) {
        state.audioContext.close();
      }
    },
  };
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                                // player control
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Play audio
 */
export const playImpl = (player) => {
  if (player?.audio) {
    player.audio.play().catch(() => {});
    if (player.drawSpectrum) {
      player.drawSpectrum();
    }
  }
};

/**
 * Pause audio
 */
export const pauseImpl = (player) => {
  if (player?.audio) {
    player.audio.pause();
    if (player.stopSpectrum) {
      player.stopSpectrum();
    }
  }
};

/**
 * Seek to time
 */
export const seekImpl = (player, time) => {
  if (player?.audio) {
    player.audio.currentTime = clamp(time, 0, player.audio.duration || 0);
  }
};

/**
 * Set volume
 */
export const setVolumeImpl = (player, volume) => {
  if (player?.audio) {
    player.audio.volume = clamp(volume, 0, 1);
  }
};

/**
 * Set muted
 */
export const setMutedImpl = (player, muted) => {
  if (player?.audio) {
    player.audio.muted = muted;
  }
};

/**
 * Set playback rate
 */
export const setPlaybackRateImpl = (player, rate) => {
  if (player?.audio) {
    player.audio.playbackRate = clamp(rate, 0.25, 4);
  }
};

/**
 * Get waveform data
 */
export const getWaveformDataImpl = (player) => {
  return player?.state?.waveformData || [];
};

/**
 * Get spectrum data
 */
export const getSpectrumDataImpl = (player) => {
  if (!player?.state?.analyser) return [];
  
  const bufferLength = player.state.analyser.frequencyBinCount;
  const dataArray = new Uint8Array(bufferLength);
  player.state.analyser.getByteFrequencyData(dataArray);
  
  return Array.from(dataArray);
};

/**
 * Draw waveform with config
 */
export const drawWaveformImpl = (player, config) => {
  const canvas = document.getElementById(config.canvasId);
  if (!canvas || !player?.state?.waveformData) return;

  const ctx = canvas.getContext("2d");
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;
  ctx.scale(dpr, dpr);
  
  const width = rect.width;
  const height = rect.height;
  const data = player.state.waveformData;
  const barWidth = width / data.length;
  const progressX = config.progress * width;
  
  ctx.clearRect(0, 0, width, height);
  
  for (let i = 0; i < data.length; i++) {
    const x = i * barWidth;
    const barHeight = data[i] * height * 0.8;
    const y = (height - barHeight) / 2;
    
    ctx.fillStyle = x < progressX ? config.progressColor : config.waveformColor;
    ctx.fillRect(x, y, barWidth - 1, barHeight);
  }
};

/**
 * Draw spectrum with config
 */
export const drawSpectrumImpl = (player, config) => {
  const canvas = document.getElementById(config.canvasId);
  if (!canvas || !player?.state?.analyser) return;

  const ctx = canvas.getContext("2d");
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;
  ctx.scale(dpr, dpr);
  
  const width = rect.width;
  const height = rect.height;
  
  const bufferLength = player.state.analyser.frequencyBinCount;
  const dataArray = new Uint8Array(bufferLength);
  player.state.analyser.getByteFrequencyData(dataArray);
  
  ctx.clearRect(0, 0, width, height);
  
  const barWidth = width / config.barCount;
  const step = Math.floor(bufferLength / config.barCount);
  
  for (let i = 0; i < config.barCount; i++) {
    const value = dataArray[i * step];
    const barHeight = (value / 255) * height;
    const x = i * barWidth;
    const y = height - barHeight;
    
    ctx.fillStyle = config.barColor;
    ctx.fillRect(x, y, barWidth - 2, barHeight);
  }
};

/**
 * Destroy audio player
 */
export const destroyAudioPlayerImpl = (player) => {
  if (player?.destroy) {
    player.destroy();
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                               // media session
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Setup MediaSession API for OS integration
 */
export const setupMediaSessionImpl = (config) => {
  if (!("mediaSession" in navigator)) return;

  navigator.mediaSession.metadata = new MediaMetadata({
    title: config.title || "Unknown Title",
    artist: config.artist || "Unknown Artist",
    album: config.album || "",
    artwork: config.artwork
      ? [
          { src: config.artwork, sizes: "96x96", type: "image/jpeg" },
          { src: config.artwork, sizes: "128x128", type: "image/jpeg" },
          { src: config.artwork, sizes: "192x192", type: "image/jpeg" },
          { src: config.artwork, sizes: "256x256", type: "image/jpeg" },
          { src: config.artwork, sizes: "384x384", type: "image/jpeg" },
          { src: config.artwork, sizes: "512x512", type: "image/jpeg" },
        ]
      : [],
  });

  // Action handlers
  try {
    navigator.mediaSession.setActionHandler("play", () => {
      config.onPlay();
    });
    
    navigator.mediaSession.setActionHandler("pause", () => {
      config.onPause();
    });
    
    navigator.mediaSession.setActionHandler("seekbackward", () => {
      config.onSeekBackward();
    });
    
    navigator.mediaSession.setActionHandler("seekforward", () => {
      config.onSeekForward();
    });
    
    navigator.mediaSession.setActionHandler("previoustrack", () => {
      config.onPreviousTrack();
    });
    
    navigator.mediaSession.setActionHandler("nexttrack", () => {
      config.onNextTrack();
    });
  } catch (err) {
    console.warn("MediaSession action handler not supported:", err);
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
//                                                              // shuffle utility
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Fisher-Yates shuffle
 */
export const shuffleArray = (array) => {
  const result = [...array];
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
};

/**
 * Create shuffle order
 */
export const createShuffleOrder = (length) => {
  return shuffleArray(Array.from({ length }, (_, i) => i));
};
