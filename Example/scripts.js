if (!('popover' in HTMLElement.prototype)) {
  import('https://unpkg.com/@oddbird/popover-polyfill@latest/dist/popover-fn.js').then(({ apply }) => {
    apply();
  });
}

const svgIconStr = `data:image/svg+xml,%3Csvg width='256' height='256' viewBox='0 0 256 256' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Crect width='256' height='256' rx='60' fill='url(%23paint0_linear_1_2)'/%3E%3Cpath d='M192 101.991C192 90.7259 180.893 83.2185 170.528 88.0066L140.231 102.001C132.33 105.65 123.67 105.65 115.769 102.001L85.4725 88.0066C75.107 83.2185 64 90.7259 64 101.991V163.66C64 172.684 71.3159 180 80.3404 180C89.3649 180 96.6809 172.684 96.6809 163.66V136.216C96.6809 133.093 100.125 131.189 102.83 132.812L123.659 145.31C126.331 146.913 129.669 146.913 132.341 145.31L153.17 132.812C155.875 131.189 159.319 133.093 159.319 136.216V163.66C159.319 172.684 166.635 180 175.66 180C184.684 180 192 172.684 192 163.66V101.991Z' fill='white'/%3E%3Cdefs%3E%3ClinearGradient id='paint0_linear_1_2' x1='128' y1='0' x2='128' y2='256' gradientUnits='userSpaceOnUse'%3E%3Cstop stop-color='%238C6DB4'/%3E%3Cstop offset='1' stop-color='%23E1BBEA'/%3E%3C/linearGradient%3E%3C/defs%3E%3C/svg%3E`;
const manifestData = {
    "name": "M3Player",
    "short_name": "M3Player",
    "start_url": ".",
    "display": "standalone",
    "theme_color": "#FFF7FA",
    "background_color": "#FFF7FA",
    "icons": [
        {
            "src": svgIconStr,
            "sizes": "192x192 256x256 512x512 any",
            "type": "image/svg+xml",
            "purpose": "any maskable"
        }
    ]
};

const blob = new Blob([JSON.stringify(manifestData)], { type: 'application/manifest+json' });
const manifestURL = URL.createObjectURL(blob);
const manifestLink = document.createElement('link');
manifestLink.rel = 'manifest';
manifestLink.href = manifestURL;
document.head.appendChild(manifestLink);

const $id = id => document.getElementById(id);
let nd = { url: '', user: '', pass: '', salt: '', token: '', version: '1.16.1', client: 'm3-desktop' };

let searchData = { songs: [], artists: [], albums: [] };
let detailData = { type: null, id: null, songs: [], albums: [] }; 
let currentTab = 'all';

let queue = [];
let history = []; 
let isLooping = false;

let androidPort = null;
window.addEventListener('message', function(event) {
    if (event.data === "INIT_PORT") {
        androidPort = event.ports[0];
        androidPort.onmessage = function(e) {
            try {
                const data = JSON.parse(e.data);
                switch(data.type) {
                    case "PLAY_STATE":
                        if(window.nativePlayStateChanged) window.nativePlayStateChanged(data.payload === "true");
                        break;
                    case "SKIP_NEXT":
                        nextTrack();
                        break;
                    case "SKIP_PREV":
                        prevTrack();
                        break;
                    case "NATIVE_SKIP_NEXT":
                        if(window.nativeTrackSkippedToNext) window.nativeTrackSkippedToNext();
                        break;
                    case "NATIVE_SKIP_PREV":
                        if(window.nativeTrackSkippedToPrevious) window.nativeTrackSkippedToPrevious();
                        break;
                    case "PLAY_ID":
                        if(window.playSongById) window.playSongById(data.payload);
                        break;
                    case "CUSTOM_ACTION":
                        if(window.handleCustomAction) window.handleCustomAction(data.payload);
                        break;
                    case "TIME_UPDATE":
                        if(window.updateNativeTime) window.updateNativeTime(parseInt(data.payload));
                        break;
                    case "TRACK_ENDED":
                        if(window.nativeTrackEnded) window.nativeTrackEnded();
                        break;
                    case "QUEUE_UPDATED":
                        if(window.nativeQueueUpdated) {
                            const payloadObj = JSON.parse(data.payload);
                            window.nativeQueueUpdated(JSON.stringify(payloadObj.queue), JSON.stringify(payloadObj.history));
                        }
                        break;
                }
            } catch(err) { console.error("Error processing native message", err); }
        };
    }
});

let audio = new Audio();

let hasScrobbledCurrentTrack = false;
let hasPrefetchedCurrentTrack = false;

let searchTimeout;
let sortableInstance = null;

let instantMixPool = [];
let isPrefetching = false;

let previousVolume = 1;
let isMuted = false;

let currentLyrics = [];
let currentLyricIndex = -1;
let lyricsCache = {};
let currentlyLoadedLyricsId = null; 

let artistInfoCache = {};
let backfaceUpdateId = 0;
let loadTrackId = 0;

let useNavidromeLyrics = false;
let isDarkMode = localStorage.getItem('m3_dark_mode') === 'true';
const colorThief = new ColorThief();
const mainArtImg = $id('main-art');

async function prefetchMixPool() {
    if (isPrefetching) return;
    isPrefetching = true;
    try {
        let targetIds = [];
        if (history.length > 0) {
            const recentIdx = 0;
            const oldestIdx = history.length - 1;
            const middleIdx = Math.floor(oldestIdx / 2);
            const targetIndices = [...new Set([recentIdx, middleIdx, oldestIdx])];
            targetIds = targetIndices.map(idx => history[idx].id);
        } else if (queue.length > 0) {
            targetIds = [queue[0].id];
        }

        const fetchPromises = targetIds.map(id =>
            fetch(`${nd.url}/rest/getSimilarSongs.view?id=${id}&count=15&${getBaseParams()}`).then(res => res.json())
        );
        
        const randomPromise = fetch(`${nd.url}/rest/getRandomSongs.view?size=25&${getBaseParams()}`).then(res => res.json());

        const [similarResponses, randomResponse] = await Promise.all([
            Promise.all(fetchPromises),
            randomPromise
        ]);

        let rawSimilar = [];
        similarResponses.forEach(data => {
            rawSimilar = [...rawSimilar, ...(data['subsonic-response'].similarSongs?.song || [])];
        });
        
        let rawRandom = randomResponse['subsonic-response'].randomSongs?.song || [];

        const currentIds = new Set([...queue.map(s => s.id), ...history.slice(0, 15).map(s => s.id)]);
        
        let validSimilar = rawSimilar.filter(s => !currentIds.has(s.id));
        const uniqueSimIds = new Set();
        validSimilar = validSimilar.filter(s => {
            if(uniqueSimIds.has(s.id)) return false;
            uniqueSimIds.add(s.id);
            return true;
        });

        let validRandom = rawRandom.filter(s => !currentIds.has(s.id) && !uniqueSimIds.has(s.id));

        for (let i = validSimilar.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [validSimilar[i], validSimilar[j]] = [validSimilar[j], validSimilar[i]]; }
        for (let i = validRandom.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [validRandom[i], validRandom[j]] = [validRandom[j], validRandom[i]]; }

        instantMixPool = [...validSimilar.slice(0, 10), ...validRandom].slice(0, 15);
        
        for (let i = instantMixPool.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [instantMixPool[i], instantMixPool[j]] = [instantMixPool[j], instantMixPool[i]]; }

    } catch(e) {
        console.error("Prefetch failed", e);
    } finally {
        isPrefetching = false;
    }
}

async function scrobbleCurrentTrack() {
    if (queue.length === 0 || hasScrobbledCurrentTrack) return;
    const song = queue[0];
    try {
        await fetchNd('scrobble.view', `id=${song.id}&submission=true`);
        hasScrobbledCurrentTrack = true;
    } catch (e) {
        console.error("Failed to scrobble track.", e);
    }
}

async function reportNowPlaying() {
    if (queue.length === 0) return;
    const song = queue[0];
    try {
        await fetchNd('scrobble.view', `id=${song.id}&submission=false`);
    } catch (e) {
        console.error("Failed to report now playing.", e);
    }
}

async function updateBackfaceContent(html) {
    const container = $id('art-back-content');
    if (container.innerHTML === html) return; 
    
    const currentId = ++backfaceUpdateId;
    container.classList.add('fade-out');
    await new Promise(r => setTimeout(r, 300));
    if (currentId !== backfaceUpdateId) return; 
    
    container.innerHTML = html;
    container.classList.remove('fade-out');
}

window.expandBio = function(btn, event) {
    if (event) { event.preventDefault(); event.stopPropagation(); }
    const container = btn.parentElement;
    const fullText = decodeURIComponent(container.getAttribute('data-full-text'));
    let currentIndex = parseInt(container.getAttribute('data-current-index'));
    let nextIndex = currentIndex + 300;
    
    if (nextIndex >= fullText.length) {
        container.innerHTML = fullText;
    } else {
        while(nextIndex < fullText.length && fullText[nextIndex] !== ' ') nextIndex++;
        if (nextIndex >= fullText.length) { container.innerHTML = fullText; } 
        else {
            container.setAttribute('data-current-index', nextIndex);
            container.innerHTML = fullText.substring(0, nextIndex) + '... <a href="#" onclick="expandBio(this, event); return false;" style="color:var(--md-sys-color-primary); text-decoration:none; font-weight:600; white-space:nowrap;">Read more</a>';
        }
    }
};

document.addEventListener('mousedown', function(e) {
    const target = e.target.closest('.ctrl-btn, .action-btn, .m3-tabs .tab, .icon-btn-ghost, .track-main-click');
    if (!target) return;
    const rect = target.getBoundingClientRect();
    const ripple = document.createElement('span');
    const diameter = Math.max(rect.width, rect.height);
    const radius = diameter / 2;
    ripple.style.width = ripple.style.height = `${diameter}px`;
    ripple.style.left = `${e.clientX - rect.left - radius}px`;
    ripple.style.top = `${e.clientY - rect.top - radius}px`;
    ripple.classList.add('ripple-effect');
    target.appendChild(ripple);
    setTimeout(() => ripple.remove(), 600);
});

$id('login-form').addEventListener('submit', function(e) {
    e.preventDefault(); 
    connectNavidrome();
});

document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT' || e.target.tagName === 'TEXTAREA') return;
    if (e.code === 'Space') { e.preventDefault(); togglePlayPause(); } 
    else if (e.shiftKey && e.code === 'ArrowRight') { e.preventDefault(); nextTrack(); } 
    else if (e.shiftKey && e.code === 'ArrowLeft') { e.preventDefault(); prevTrack(); }
});

window.addEventListener('DOMContentLoaded', () => {
    const themeIcon = document.querySelector('#theme-btn .material-symbols-rounded');
    if(themeIcon) themeIcon.textContent = isDarkMode ? 'light_mode' : 'dark_mode';
    const settingsMenu = document.getElementById('settings-menu');
    const settingsBtn = document.getElementById('settings-trigger-btn');
    if (settingsMenu && settingsBtn) {
        settingsMenu.addEventListener('toggle', (e) => {
            if (e.newState === 'open') {
                const rect = settingsBtn.getBoundingClientRect();
                settingsMenu.style.top = `${rect.bottom + 8}px`;
                settingsMenu.style.left = `${rect.right - settingsMenu.offsetWidth}px`;
            }
        });
    }
    applyDynamicColors(null, isDarkMode);
});

window.onload = () => {
    const savedUrl = localStorage.getItem('nd_url');
    const savedUser = localStorage.getItem('nd_user');
    const savedPass = localStorage.getItem('nd_pass');
    if(savedUrl) $id('nd-url').value = savedUrl;
    if(savedUrl && savedUser && savedPass) {
        $id('nd-user').value = savedUser;
        $id('nd-pass').value = savedPass;
        connectNavidrome();
    } else {
        $id('login-overlay').style.display = 'flex';
    }

    const savedVol = localStorage.getItem('m3_volume');
    if(savedVol !== null) {
        audio.volume = parseFloat(savedVol);
        $id('volume-slider').value = audio.volume;
        $id('mute-icon').textContent = audio.volume == 0 ? 'volume_off' : (audio.volume > 0.5 ? 'volume_up' : 'volume_down');
    }

    const savedTransLang = localStorage.getItem('m3_trans_lang');
    if(savedTransLang) {
        $id('lyrics-lang').value = savedTransLang;
    }

    sortableInstance = new Sortable($id('queue-list'), {
        handle: '.drag-handle',
        animation: 150, 
        easing: "cubic-bezier(0.165, 0.84, 0.44, 1)", 
        ghostClass: 'sortable-ghost',
        dragClass: 'sortable-drag',
        filter: '.no-drag', 
        axis: 'y',
        scroll: document.getElementById('queue-list'),
        scrollSensitivity: 100,
        bubbleScroll: true,
        swapThreshold: 0.65,
        forceFallback: true,
        fallbackOnBody: true,
        fallbackClass: 'sortable-fallback',
        onEnd: function (evt) {
            if (evt.oldIndex === evt.newIndex) return;
            const item = queue.splice(evt.oldIndex, 1)[0];
            queue.splice(evt.newIndex, 0, item);
            
            if (evt.newIndex === 0) {
                loadTrack(true, true);
                if (!isNativePlayback) {
                    audio.play().catch(e => console.error("Playback failed:", e));
                }
            }
            
            renderQueue();
            saveSession();
        }
    });
};

function saveSession(syncToNative = true) {
    localStorage.setItem('m3_queue', JSON.stringify(queue));
    localStorage.setItem('m3_history', JSON.stringify(history));
    if (syncToNative && window.AndroidMedia && window.AndroidMedia.updateNativeQueue) {
        window.AndroidMedia.updateNativeQueue(JSON.stringify(queue), JSON.stringify(history));
    }
}

window.nativeTrackSkippedToNext = function() {
    if (queue.length <= 1) { 
        if (queue.length === 1) { history.unshift(queue.shift()); history = history.slice(0,50); clearQueue(); }
        return; 
    }
    const oldSong = queue.shift(); history.unshift(oldSong); history = history.slice(0,50);
    loadTrack(false, false); 
    renderQueue();
    renderHistory();
    saveSession(false);
};

window.nativeTrackSkippedToPrevious = function() {
    if (history.length === 0) return;
    queue.unshift(history.shift());
    loadTrack(false, false); 
    renderQueue();
    renderHistory();
    saveSession(false);
};

window.nativeQueueUpdated = function(queueJson, historyJson) {
    try {
        let parsedQueue = JSON.parse(queueJson);
        let parsedHistory = JSON.parse(historyJson);
        parsedQueue = Array.isArray(parsedQueue) ? parsedQueue.filter(s => s && s.id && s.title) : [];
        parsedHistory = Array.isArray(parsedHistory) ? parsedHistory.filter(s => s && s.id && s.title) : [];
        
        const oldId = queue.length > 0 ? queue[0].id : null;
        const newId = parsedQueue.length > 0 ? parsedQueue[0].id : null;

        queue = parsedQueue;
        history = parsedHistory;
        
        saveSession(false);
        renderQueue();
        renderHistory();
        
        if (newId && oldId !== newId) {
            loadTrack(false, false); 
        }
    } catch(e) { console.error("Error parsing native queue", e); }
};

window.playSongById = async function(id) {
    let strId = String(id);
    let qIdx = queue.findIndex(s => s && String(s.id) === strId);
    if (qIdx !== -1) {
        if (qIdx !== 0) playFromQueue(qIdx);
        return;
    }
    let hIdx = history.findIndex(s => s && String(s.id) === strId);
    if (hIdx !== -1) {
        playFromHistory(hIdx);
        return;
    }
    
    // Check local memory first
    let song = null;
    if (searchData.songs) song = searchData.songs.find(s => String(s.id) === strId);
    if (!song && detailData.songs) song = detailData.songs.find(s => String(s.id) === strId);
    if (!song && instantMixPool) song = instantMixPool.find(s => String(s.id) === strId);

    // Network fallback
    if (!song) {
        try {
            const res = await fetchNd('getSong.view', `id=${encodeURIComponent(strId)}`);
            song = res['subsonic-response']?.song;
            if (Array.isArray(song)) song = song[0];
        } catch (e) { console.error("Failed to fetch song by ID", e); }
    }

    if (song) {
        if (queue.length > 0) {
            const oldSong = queue.shift();
            history.unshift(oldSong); 
            history = history.slice(0,50);
        }
        queue.unshift({...song});
        saveSession();
        loadTrack();
        audio.play();
        renderQueue();
        renderHistory();
    }
};

window.handleCustomAction = function(action) {
    if (action === "action_shuffle") {
        $id('shuffle-btn').click();
    } else if (action === "action_repeat") {
        $id('loop-btn').click();
    } else if (action === "action_favorite") {
        $id('fav-btn').click();
    }
};

function restoreSession() {
    try {
        const savedQueue = localStorage.getItem('m3_queue');
        const savedHistory = localStorage.getItem('m3_history');
        if (savedQueue) {
            let q = JSON.parse(savedQueue);
            queue = Array.isArray(q) ? q.filter(s => s && s.id && s.title) : [];
        }
        if (savedHistory) {
            let h = JSON.parse(savedHistory);
            history = Array.isArray(h) ? h.filter(s => s && s.id && s.title) : [];
        }
        if (queue.length > 0) { 
            renderQueue(); 
            loadTrack(false, false); 
        }
        if (isNativePlayback && window.AndroidMedia.requestSync) {
            window.AndroidMedia.requestSync();
        }
    } catch(e) {}
}

function changeUser() {
    localStorage.removeItem('nd_user');
    localStorage.removeItem('nd_pass');
    localStorage.removeItem('m3_queue');
    localStorage.removeItem('m3_history');
    queue = [];
    history = [];
    currentLyrics = [];
    currentSongId = null;
    audio.pause();
    audio.removeAttribute('src');
    
    $id('main-art').src = 'data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=';
    $id('main-art').classList.remove('loaded');
    $id('main-title').textContent = 'Ready to Play';
    $id('main-artist').textContent = 'Select a track from Discover';
    $id('main-album').textContent = '--';
    renderQueue(); renderHistory();
    applyDynamicColors(null, isDarkMode);

    $id('main-app').style.display = 'none';
    $id('login-overlay').style.display = 'flex';
    $id('nd-user').value = '';
    $id('nd-pass').value = '';
    const btn = $id('login-submit-btn');
    if (btn) { btn.textContent = 'Login'; btn.style.opacity = '1'; }
}

$id('volume-slider').addEventListener('input', (e) => {
    audio.volume = e.target.value;
    isMuted = audio.volume == 0;
    $id('mute-icon').textContent = isMuted ? 'volume_off' : (audio.volume > 0.5 ? 'volume_up' : 'volume_down');
    localStorage.setItem('m3_volume', audio.volume);
});

function toggleMute() {
    const muteIcon = $id('mute-icon');
    const volSlider = $id('volume-slider');
    if (isMuted) {
        audio.volume = previousVolume; volSlider.value = previousVolume;
        muteIcon.textContent = previousVolume > 0.5 ? 'volume_up' : 'volume_down';
        isMuted = false;
    } else {
        previousVolume = audio.volume; audio.volume = 0; volSlider.value = 0;
        muteIcon.textContent = 'volume_off';
        isMuted = true;
    }
    localStorage.setItem('m3_volume', audio.volume);
}

function toggleMobileQueue() { $id('discover-panel').classList.remove('mobile-active'); $id('queue-panel').classList.toggle('mobile-active'); }
function toggleMobileDiscover() { $id('queue-panel').classList.remove('mobile-active'); $id('discover-panel').classList.toggle('mobile-active'); }

function toggleReducedQueue() {
    const app = $id('main-app');
    const btn = $id('reduced-queue-toggle-btn');
    app.classList.toggle('queue-hidden-reduced');
    btn.classList.toggle('active');
}

function toggleHistoryView() {
    const qView = $id('queue-view');
    const hView = $id('history-view');
    
    if (hView.style.display === 'flex') {
        hView.style.display = 'none';
        qView.style.display = 'flex';
    } else {
        qView.style.display = 'none';
        hView.style.display = 'flex';
        renderHistory();
    }
}

function toggleLyricSource() {
    useNavidromeLyrics = !useNavidromeLyrics;
    const text = useNavidromeLyrics ? 'Source: Server' : 'Source: Web';
    const topBtn = $id('lyric-source-toggle');
    const fabBtn = $id('lyric-source-toggle-fab');
    if (topBtn) topBtn.textContent = text;
    if (fabBtn) fabBtn.textContent = text;
    displayLyricsForCurrentTrack();
}

function toggleTheme() {
    isDarkMode = !isDarkMode; localStorage.setItem('m3_dark_mode', isDarkMode);
    document.querySelector('#theme-btn .material-symbols-rounded').textContent = isDarkMode ? 'light_mode' : 'dark_mode';
    if (mainArtImg.classList.contains('loaded')) { applyDynamicColors(mainArtImg); } else { applyDynamicColors(null, isDarkMode); }
}

function rgbToHsl(r, g, b) {
    r /= 255, g /= 255, b /= 255;
    let max = Math.max(r, g, b), min = Math.min(r, g, b); let h, s, l = (max + min) / 2;
    if(max === min) { h = s = 0; } else {
        let d = max - min;
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
        switch(max) {
            case r: h = (g - b) / d + (g < b ? 6 : 0); break;
            case g: h = (b - r) / d + 2; break;
            case b: h = (r - g) / d + 4; break;
        }
        h /= 6;
    }
    return [Math.round(h * 360), Math.round(s * 100), Math.round(l * 100)];
}

function applyDynamicColors(imageElement, forceDark = false) {
    try {
        let h=0, s=0, l=0;
        if (imageElement && !imageElement.src.includes('data:image')) {
            const rgb = colorThief.getColor(imageElement); [h, s, l] = rgbToHsl(rgb[0], rgb[1], rgb[2]);
        } else { h = 220; s = 15; l = 50; }

        const root = document.documentElement;
        const isDark = imageElement ? isDarkMode : forceDark;
        
        if (isDark) {
            root.style.setProperty('--md-sys-color-background', `hsl(${h}, ${Math.max(0, s - 10)}%, 10%)`);
            root.style.setProperty('--md-sys-color-surface', `hsl(${h}, ${Math.max(0, s - 10)}%, 12%)`);
            root.style.setProperty('--md-sys-color-surface-variant', `hsl(${h}, ${Math.max(0, s - 15)}%, 20%)`);
            root.style.setProperty('--md-sys-color-secondary-container', `hsl(${h}, ${Math.max(0, s - 20)}%, 25%)`);
            root.style.setProperty('--md-sys-color-primary', `hsl(${h}, ${s}%, 80%)`); 
            root.style.setProperty('--md-sys-color-primary-container', `hsl(${h}, ${Math.max(0, s - 10)}%, 75%)`);
            root.style.setProperty('--md-sys-color-on-primary-container', `hsl(${h}, ${Math.max(0, s - 10)}%, 15%)`);
            root.style.setProperty('--md-sys-color-on-background', `hsl(${h}, ${s}%, 90%)`);
            root.style.setProperty('--md-sys-color-on-surface-variant', `hsl(${h}, ${s}%, 80%)`);
            root.style.setProperty('--md-sys-color-on-secondary-container', `hsl(${h}, ${s}%, 85%)`);
        } else {
            root.style.setProperty('--md-sys-color-primary', `hsl(${h}, ${s}%, 30%)`);
            root.style.setProperty('--md-sys-color-background', `hsl(${h}, ${s}%, 96%)`);
            root.style.setProperty('--md-sys-color-surface', `hsl(${h}, ${s}%, 94%)`);
            root.style.setProperty('--md-sys-color-surface-variant', `hsl(${h}, ${s}%, 90%)`);
            root.style.setProperty('--md-sys-color-secondary-container', `hsl(${h}, ${Math.max(0, s - 10)}%, 88%)`);
            root.style.setProperty('--md-sys-color-primary-container', `hsl(${h}, ${s}%, 80%)`);
            root.style.setProperty('--md-sys-color-on-primary-container', `hsl(${h}, ${s}%, 15%)`);
            root.style.setProperty('--md-sys-color-on-background', `hsl(${h}, ${s}%, 10%)`);
            root.style.setProperty('--md-sys-color-on-surface-variant', `hsl(${h}, ${s}%, 25%)`);
            root.style.setProperty('--md-sys-color-on-secondary-container', `hsl(${h}, ${s}%, 20%)`);
        }
    } catch(e) { console.error("Color processing failed.", e); }
}

mainArtImg.addEventListener('load', function() {
    if(this.src.includes('data:image')) return;
    this.classList.add('loaded'); 
    setTimeout(() => applyDynamicColors(this), 50);
});

function toggleArtFlip() {
    if (queue.length === 0) return;
    const inner = $id('art-flip-inner');
    const isFlipped = inner.classList.toggle('flipped');
    if (isFlipped) {
        fetchArtistInfoForBack();
    }
}

async function generateArtistInfoHtml(song) {
    let bio = ''; let albums = []; let topSongs = [];
    try {
        if (song.artistId || song.artist) {
            const reqArtistId = song.artistId || song.artist;
            const infoRes = await fetch(`${nd.url}/rest/getArtistInfo.view?id=${encodeURIComponent(reqArtistId)}&${getBaseParams()}`);
            const infoData = await infoRes.json();
            bio = infoData['subsonic-response'].artistInfo?.biography || '';
        }

        if (!bio && song.artist) {
            try {
                const wikiRes = await fetch(`https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(song.artist)}`);
                if(wikiRes.ok) { const wikiData = await wikiRes.json(); if (wikiData.extract) bio = wikiData.extract; }
            } catch(e) {}
        }
        
        if (!bio) bio = 'No biography information is available for this artist.';
        const tmp = document.createElement("DIV"); tmp.innerHTML = bio; bio = tmp.textContent || tmp.innerText || "";
        
        if (song.artist) {
            const topRes = await fetch(`${nd.url}/rest/getTopSongs.view?artist=${encodeURIComponent(song.artist)}&count=4&${getBaseParams()}`);
            const topData = await topRes.json();
            topSongs = topData['subsonic-response'].topSongs?.song || [];
        }
        
        if (song.artistId) {
            const artRes = await fetch(`${nd.url}/rest/getArtist.view?id=${song.artistId}&${getBaseParams()}`);
            const artData = await artRes.json();
            albums = artData['subsonic-response'].artist?.album || [];
        }

        let bioHtml = '';
        if (bio.length > 300) {
            let cutIndex = 300; while(cutIndex < bio.length && bio[cutIndex] !== ' ') cutIndex++;
            let encodedBio = encodeURIComponent(bio);
            bioHtml = `<div class="bio-text" data-full-text="${encodedBio}" data-current-index="${cutIndex}">${bio.substring(0, cutIndex)}... <a href="#" onclick="expandBio(this, event); return false;" style="color:var(--md-sys-color-primary); text-decoration:none; font-weight:600; white-space:nowrap;">Read more</a></div>`;
        } else { bioHtml = `<div class="bio-text">${bio}</div>`; }

        let html = `<h3 style="font-size:1.4rem; margin-bottom: 0.5rem; font-weight:800; color: var(--md-sys-color-primary); transition: color 0.8s ease;">${song.artist}</h3>${bioHtml}`;

        if(topSongs.length > 0) {
            html += `<h4 style="font-size:0.95rem; margin-top: 1rem; margin-bottom: 0.2rem; opacity: 0.8;">Popular Songs</h4><div class="bubble-container">`;
            topSongs.slice(0, 4).forEach(s => { html += `<button class="bubble-btn" onclick="event.stopPropagation(); fetchAndPlaySong('${s.id}')"><span class="material-symbols-rounded" style="font-size:1rem; vertical-align:middle; margin-right:4px;">play_arrow</span>${s.title}</button>`; });
            html += `</div>`;
        }

        if(albums.length > 0) {
            html += `<h4 style="font-size:0.95rem; margin-top: 1rem; margin-bottom: 0.2rem; opacity: 0.8;">Albums</h4><div class="bubble-container">`;
            albums.slice(0, 4).forEach(a => { html += `<button class="bubble-btn" onclick="event.stopPropagation(); addAlbumToQueue('${a.id}')"><span class="material-symbols-rounded" style="font-size:1rem; vertical-align:middle; margin-right:4px;">album</span>${a.title || a.name}</button>`; });
            html += `</div>`;
        }
        return html;
    } catch(e) { throw e; }
}

function preloadArtistInfo(index) {
    if (index < 0 || index >= queue.length) return;
    const song = queue[index]; const cacheKey = song.artist || song.artistId;
    if (!cacheKey) return; if (artistInfoCache[cacheKey]) return; 
    const promise = generateArtistInfoHtml(song).then(html => { artistInfoCache[cacheKey] = { status: 'loaded', html: html }; }).catch(err => { artistInfoCache[cacheKey] = { status: 'error' }; });
    artistInfoCache[cacheKey] = { status: 'loading', promise: promise };
}

async function fetchArtistInfoForBack() {
    if (queue.length === 0) return;
    const song = queue[0]; const cacheKey = song.artist || song.artistId;
    
    if (!cacheKey) { await updateBackfaceContent('<p style="opacity:0.5;">No artist information available.</p>'); return; }
    if (!artistInfoCache[cacheKey]) { preloadArtistInfo(0); }
    const cacheEntry = artistInfoCache[cacheKey];

    if (cacheEntry.status === 'loaded') { await updateBackfaceContent(cacheEntry.html); return; }
    await updateBackfaceContent('<div style="display:flex; justify-content:center; align-items:center; height:100%;"><div class="spinner"></div></div>');
    
    if (cacheEntry.status === 'loading') {
        try {
            await cacheEntry.promise;
            if (artistInfoCache[cacheKey].status === 'loaded') {
                if (queue.length > 0 && (queue[0].artist === song.artist || queue[0].artistId === song.artistId)) { await updateBackfaceContent(artistInfoCache[cacheKey].html); }
            } else { await updateBackfaceContent('<p style="opacity:0.5;">Unable to load artist data.</p>'); }
        } catch(e) { await updateBackfaceContent('<p style="opacity:0.5;">Unable to load artist data.</p>'); }
    }
}

async function fetchAndPlaySong(songId) {
    try {
        const res = await fetch(`${nd.url}/rest/getSong.view?id=${songId}&${getBaseParams()}`);
        const data = await res.json(); const s = data['subsonic-response'].song;
        if(s) injectNext(s);
    } catch(e) {}
}

function generateAuth() { nd.salt = Math.random().toString(36).substring(2, 15); nd.token = md5(nd.pass + nd.salt); }
function getBaseParams() { return `u=${encodeURIComponent(nd.user)}&t=${nd.token}&s=${nd.salt}&v=${nd.version}&c=${nd.client}&f=json`; }
async function fetchNd(endpoint, params = '') {
    const res = await fetch(`${nd.url}/rest/${endpoint}?${params ? params + '&' : ''}${getBaseParams()}`);
    return await res.json();
}
function getCoverUrl(id) { return id ? `${nd.url}/rest/getCoverArt.view?id=${id}&size=1200&${getBaseParams()}` : 'data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs='; }
function getThumbUrl(id) { return id ? `${nd.url}/rest/getCoverArt.view?id=${id}&size=300&${getBaseParams()}` : 'data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs='; }
function getStreamUrl(id) { return `${nd.url}/rest/stream.view?id=${id}&${getBaseParams()}`; }
function downloadSong(id) { window.open(`${nd.url}/rest/download.view?id=${id}&${getBaseParams()}`, '_blank'); }
function downloadCurrentSong() { if (queue.length === 0) return; downloadSong(queue[0].id); }

function showError(msg) { const errDiv = $id('login-error'); errDiv.innerHTML = msg; errDiv.style.display = 'block'; }

async function connectNavidrome() {
    $id('login-overlay').style.display = 'flex';
    $id('login-error').style.display = 'none'; 
    const btn = $id('login-submit-btn');
    
    nd.url = $id('nd-url').value.replace(/\/$/, '');
    nd.user = $id('nd-user').value;
    nd.pass = $id('nd-pass').value;

    if(!nd.url || !nd.user || !nd.pass) { showError("Please fill in all required fields."); return; }

    btn.textContent = "Connecting..."; btn.style.opacity = "0.7";
    generateAuth();
    try {
        const res = await fetch(`${nd.url}/rest/ping.view?${getBaseParams()}`);
        const data = await res.json();
        
        if (data['subsonic-response'].status === 'ok') {
            localStorage.setItem('nd_url', nd.url); 
            localStorage.setItem('nd_user', nd.user); 
            localStorage.setItem('nd_pass', nd.pass); 
            
            if (window.AndroidMedia) {
                window.AndroidMedia.saveCredentials(nd.url, nd.user, nd.salt, nd.token);
            }

            $id('login-overlay').style.display = 'none';
            $id('main-app').style.display = window.innerWidth > 850 ? 'grid' : 'flex';
            loadDefaultContent(); restoreSession();
        } else { 
            showError("Auth failed. Check username/password."); btn.textContent = "Login"; btn.style.opacity = "1";
            $id('login-overlay').style.display = 'flex'; $id('main-app').style.display = 'none';
        }
    } catch (err) { 
        showError("Network Error. Ensure your URL uses HTTPS and CORS is configured."); btn.textContent = "Login"; btn.style.opacity = "1";
        $id('login-overlay').style.display = 'flex'; $id('main-app').style.display = 'none';
    }
}

function getArtHtml(item, isArtist) {
    let src = isArtist ? (item.artistImageUrl || getThumbUrl(item.coverArt || item.id)) : getThumbUrl(item.coverArt);
    const fallbackIcon = isArtist ? 'person' : 'music_note';
    return `<div class="image-wrapper"><div class="icon-fallback"><span class="material-symbols-rounded">${fallbackIcon}</span></div><div class="spinner"></div><img class="track-img" src="${src}" loading="lazy" decoding="async" crossorigin="anonymous" onload="this.classList.add('loaded'); this.previousElementSibling.style.display='none';" onerror="this.style.display='none'; this.previousElementSibling.style.display='none';"></div>`;
}

function buildTrackHtml(title, subText, coverHtml, clickAction, extraPrefixHtml = '', extraSuffixHtml = '') {
    return `${extraPrefixHtml}<div class="track-main-click" onclick="${clickAction}" style="flex: 1; padding: 0.25rem 0;">${coverHtml}<div class="track-info-small"><div class="title">${title}</div><div class="artist">${subText}</div></div></div>${extraSuffixHtml}`;
}


function cycleSearchFilter() {
    const filters = ['all', 'song', 'artist', 'album', 'fav'];
    const labels = { 'all': 'All', 'song': 'Songs', 'artist': 'Artists', 'album': 'Albums', 'fav': 'Favorites' };
    let idx = filters.indexOf(currentTab);
    currentTab = filters[(idx + 1) % filters.length];
    
    const pill = $id('search-filter-pill');
    if (pill) pill.textContent = labels[currentTab];
    
    const query = $id('search-input').value.trim();
    if (!query) { loadDefaultContent(); } else { performSearch(); }
}

async function loadDefaultContent() {
    const container = $id('search-results'); container.innerHTML = '<p style="padding: 1rem;">Loading...</p>';
    try {
        if (currentTab === 'all') {
            const [songRes, albRes, artRes] = await Promise.all([
                fetch(`${nd.url}/rest/getRandomSongs.view?size=15&${getBaseParams()}`),
                fetch(`${nd.url}/rest/getAlbumList.view?type=random&size=10&${getBaseParams()}`),
                fetch(`${nd.url}/rest/getArtists.view?${getBaseParams()}`)
            ]);
            const songData = await songRes.json(); const albData = await albRes.json(); const artData = await artRes.json();
            searchData.songs = songData['subsonic-response'].randomSongs?.song || [];
            searchData.albums = albData['subsonic-response'].albumList?.album || [];
            let allArtists = [];
            (artData['subsonic-response'].artists?.index || []).forEach(idx => { if (idx.artist) allArtists.push(...idx.artist); });
            for (let i = allArtists.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [allArtists[i], allArtists[j]] = [allArtists[j], allArtists[i]]; }
            searchData.artists = allArtists.slice(0, 10);
        }
        else if (currentTab === 'song') {
            const res = await fetch(`${nd.url}/rest/getRandomSongs.view?size=50&${getBaseParams()}`); const data = await res.json();
            searchData.songs = data['subsonic-response'].randomSongs?.song || []; searchData.songs.sort((a, b) => (a.title || '').localeCompare(b.title || ''));
        } 
        else if (currentTab === 'album') {
            const res = await fetch(`${nd.url}/rest/getAlbumList.view?type=alphabeticalByName&size=50&${getBaseParams()}`); const data = await res.json();
            let albums = data['subsonic-response'].albumList?.album || [];
            albums.sort((a, b) => (a.title || a.name || '').localeCompare(b.title || b.name || ''));
            searchData.albums = albums;
        } 
        else if (currentTab === 'artist') {
            const res = await fetch(`${nd.url}/rest/getArtists.view?${getBaseParams()}`); const data = await res.json();
            const indices = data['subsonic-response'].artists?.index || []; let allArtists = [];
            indices.forEach(idx => { if (idx.artist) allArtists.push(...idx.artist); });
            allArtists.sort((a, b) => (a.name || '').localeCompare(b.name || '')); searchData.artists = allArtists.slice(0, 50); 
        }
        else if (currentTab === 'fav') {
            const res = await fetch(`${nd.url}/rest/getStarred.view?${getBaseParams()}`); const data = await res.json();
            searchData.songs = data['subsonic-response'].starred?.song || [];
        }
        renderSearch();
    } catch (e) { container.innerHTML = '<p style="padding: 1rem; color: red;">Failed to load data.</p>'; }
}

function debounceSearch() { clearTimeout(searchTimeout); searchTimeout = setTimeout(performSearch, 500); }

async function performSearch() {
    const query = $id('search-input').value.trim();
    if (!query) { loadDefaultContent(); return; }
    try {
        $id('search-results').innerHTML = '<p style="padding: 1rem;">Searching...</p>';
        if (currentTab === 'fav') {
            const res = await fetch(`${nd.url}/rest/getStarred.view?${getBaseParams()}`); const data = await res.json();
            const allFavs = data['subsonic-response'].starred?.song || [];
            searchData.songs = allFavs.filter(s => (s.title || '').toLowerCase().includes(query.toLowerCase()) || (s.artist || '').toLowerCase().includes(query.toLowerCase()));
            renderSearch(); return;
        }
        const res = await fetch(`${nd.url}/rest/search3.view?query=${encodeURIComponent(query)}&songCount=50&albumCount=20&artistCount=20&${getBaseParams()}`);
        const data = await res.json(); const result = data['subsonic-response'].searchResult3;
        searchData.songs = result?.song || []; searchData.albums = result?.album || []; searchData.artists = result?.artist || [];
        searchData.songs.sort((a, b) => (a.title || '').localeCompare(b.title || '')); renderSearch();
    } catch (e) {}
}

function bulkRemoveFromQueue(type, id, title = '') {
    let predicateFunc;
    if (type === 'album') predicateFunc = s => s.albumId === id;
    else if (type === 'artist') predicateFunc = s => s.artistId === id || s.artist === title;

    let currentRemoved = false; let newQueue = [];
    for (let i = 0; i < queue.length; i++) {
        if (predicateFunc(queue[i])) { if (i === 0) currentRemoved = true; } else { newQueue.push(queue[i]); }
    }
    if (currentRemoved && queue.length > 0) { history.unshift(queue[0]); history = history.slice(0,50); }
    queue = newQueue;
    
    if (currentRemoved) {
        if (queue.length > 0) { loadTrack(); audio.play(); } else { clearQueue(); }
    }
    renderQueue(); saveSession();
}

function playNextById(songId) { const song = searchData.songs?.find(s => s && String(s.id) === String(songId)); if(song) injectNext(song); }
function playNextDetailSong(idx) { injectNext(detailData.songs?.[idx]); }
function injectNext(songObj) {
    if (queue.some(s => s && s.id === songObj?.id)) return;
    if (queue.length === 0) { queue.push({...songObj}); loadTrack(); if (!isNativePlayback) audio.play(); } 
    else {
        queue.splice(1, 0, {...songObj});
    }
    renderQueue(); saveSession();
}
async function triggerInstantMix() {
    if (instantMixPool.length === 0) {
        const banner = $id('instant-mix-banner');
        const originalText = banner.innerHTML;
        banner.innerHTML = '<span class="material-symbols-rounded" style="animation: spin 1s linear infinite;">sync</span> Mixing...';
        await prefetchMixPool();
        banner.innerHTML = originalText;
    }

    if (instantMixPool.length === 0) return;

    const wasEmpty = queue.length === 0;
    
    instantMixPool.forEach(s => queue.push({...s}));
    instantMixPool = []; 
    
    if (queue.length > 0 && (wasEmpty || (audio.paused && $id('play-icon')?.textContent === 'play_arrow'))) { 
        loadTrack(); 
        if (!isNativePlayback) audio.play(); 
    }
    
    renderQueue(); 
    saveSession();
}
function renderSearch() {
    const container = $id('search-results'); 
    if (!container) return;
    container.innerHTML = '';
    container.style.animation = 'none'; container.offsetHeight; container.style.animation = 'viewFadeIn 0.25s cubic-bezier(0.2, 0, 0, 1) forwards';

    let list = [];
    if (currentTab === 'all') {
        list = [...(searchData.artists || []), ...(searchData.albums || []), ...(searchData.songs || [])];
    }
    else if (currentTab === 'song' || currentTab === 'fav') list = searchData.songs;
    else if (currentTab === 'album') list = searchData.albums;
    else if (currentTab === 'artist') list = searchData.artists;

    if (list?.length === 0) { container.innerHTML = `<p style="padding: 1rem; opacity: 0.7;">No results.</p>`; return; }

    list?.forEach(item => {
        if (!item) return;
        const isSong = (currentTab === 'song' || currentTab === 'fav') || (currentTab === 'all' && item.isDir === undefined && !item.albumCount && item.album);
        const isAlbum = currentTab === 'album' || (currentTab === 'all' && item.isDir === true);
        const isArtist = currentTab === 'artist' || (currentTab === 'all' && item.albumCount !== undefined);
        let coverHtml = getArtHtml(item, isArtist);
        
        let subText = '';
        if (isSong) subText = `${item.artist} • ${item.album || 'Unknown'}`;
        else if (isAlbum) subText = item.artist;
        else if (isArtist) {
            let meta = []; if (item.albumCount) meta.push(`${item.albumCount} Albums`); if (item.trackCount) meta.push(`${item.trackCount} Tracks`);
            subText = meta.length > 0 ? meta.join(' • ') : 'Artist';
        }

        let encodedTitle = encodeURIComponent(item.title || item.name || '');
        let onClickStr = isSong ? `playSongById('${item.id}')` : (isAlbum ? `viewAlbum('${item.id}', decodeURIComponent('${encodedTitle}'))` : `viewArtist('${item.id}', decodeURIComponent('${encodedTitle}'))`);
        let actionsHtml = isSong ? 
            `<button class="action-btn" onclick="playNextById('${item.id}')" title="Play Next"><span class="material-symbols-rounded">playlist_play</span></button>
             <button class="action-btn" onclick="addToQueueById('${item.id}')" title="Add to End of Queue"><span class="material-symbols-rounded">add</span></button>` : 
            isAlbum ? 
            `<button class="action-btn" onclick="addAlbumToQueue('${item.id}')"><span class="material-symbols-rounded">add</span></button>
             <button class="action-btn remove" onclick="bulkRemoveFromQueue('album', '${item.id}')"><span class="material-symbols-rounded">remove</span></button>` : 
            `<button class="action-btn" onclick="addArtistToQueue('${item.id}')"><span class="material-symbols-rounded">add</span></button>
             <button class="action-btn remove" onclick="bulkRemoveFromQueue('artist', '${item.id}', decodeURIComponent('${encodedTitle}'))"><span class="material-symbols-rounded">remove</span></button>`;

        container.innerHTML += `<div class="track-item" title="${isSong ? 'Play' : 'Open Details'}">${buildTrackHtml(item.title || item.name, subText, coverHtml, onClickStr, '', `<div class="action-group">${actionsHtml}</div>`)}</div>`;
    });
}

async function viewAlbum(id, title) {
    $id('search-view')?.style.setProperty('display', 'none'); 
    const detailView = $id('detail-view');
    detailView.style.animation = 'none'; detailView.offsetHeight;  detailView.style.animation = null; detailView.style.display = 'flex';
    $id('detail-title').textContent = title; $id('detail-results').innerHTML = '<p style="padding: 1rem;">Loading album...</p>';
    try {
        const data = await fetchNd('getAlbum.view', `id=${id}`);
        detailData.songs = data?.['subsonic-response']?.album?.song || []; renderDetailSongs();
    } catch (e) {}
}

async function viewArtist(id, name) {
    $id('search-view')?.style.setProperty('display', 'none'); 
    const detailView = $id('detail-view');
    detailView.style.animation = 'none'; detailView.offsetHeight; detailView.style.animation = null; detailView.style.display = 'flex';
    $id('detail-title').textContent = name; $id('detail-results').innerHTML = '<p style="padding: 1rem;">Loading all songs...</p>';
    try {
        const data = await fetchNd('getArtist.view', `id=${id}`);
        const albums = data?.['subsonic-response']?.artist?.album || [];
        const nestedSongs = await Promise.all(albums.map(async (alb) => {
            return (await fetchNd('getAlbum.view', `id=${alb.id}`))?.['subsonic-response']?.album?.song || [];
        }));
        detailData.songs = nestedSongs.flat(); renderDetailSongs();
    } catch (e) {}
}

function closeDetailView() { 
    $id('detail-view')?.style.setProperty('display', 'none'); 
    const searchView = $id('search-view');
    searchView.style.animation = 'none'; searchView.offsetHeight; searchView.style.animation = null; searchView.style.display = 'flex';
    detailData.songs = []; 
}

function renderDetailSongs() {
    const container = $id('detail-results'); 
    container.innerHTML = '';
    container.style.animation = 'none'; container.offsetHeight; container.style.animation = 'viewFadeIn 0.25s cubic-bezier(0.2, 0, 0, 1) forwards';

    detailData.songs?.forEach((song, idx) => {
        if (!song) return;
        let actions = `<button class="action-btn" onclick="playNextDetailSong(${idx})" title="Play Next"><span class="material-symbols-rounded">playlist_play</span></button><button class="action-btn" onclick="addDetailSongToQueue(${idx})" title="Add to End of Queue"><span class="material-symbols-rounded">add</span></button>`;
        container.innerHTML += `<div class="track-item">${buildTrackHtml(song.title, `${song.artist} • ${song.album}`, getArtHtml(song, false), `playSongById('${song.id}')`, '', `<div class="action-group">${actions}</div>`)}</div>`;
    });
}

function renderHistory() {
    const container = $id('history-list');
    container.innerHTML = '';
    container.style.animation = 'none'; container.offsetHeight; container.style.animation = 'viewFadeIn 0.25s cubic-bezier(0.2, 0, 0, 1) forwards';

    history = history.filter(s => s && s.title);

    if (history.length === 0) {
        container.innerHTML = '<p style="opacity: 0.6; text-align: center; padding: 1.25rem;">History is empty.</p>';
        return;
    }
    
    let htmlBuffer = [];
    history.forEach((song, idx) => {
        htmlBuffer.push(`<div class="track-item">${buildTrackHtml(song.title, song.artist || 'Unknown Artist', getArtHtml(song, false), `playFromHistory(${idx})`)}</div>`);
    });
    container.innerHTML = htmlBuffer.join('');
}

function playFromHistory(index) {
    const song = history.splice(index, 1)[0];
    if (queue.length > 0) { history.unshift(queue[0]); history = history.slice(0,50); }
    queue.unshift(song); saveSession(); loadTrack(); if (!isNativePlayback) audio.play(); renderQueue(); renderHistory();
}

function renderQueue() {
    const container = $id('queue-list'); 
    
    const banner = $id('instant-mix-banner');
    if (queue.length <= 3) { banner?.classList.add('show'); } else { banner?.classList.remove('show'); }

    queue = queue.filter(s => s && s.title);

    if(queue.length === 0) { 
        container.innerHTML = '<p style="opacity: 0.6; text-align: center; padding: 1.25rem;">Queue is empty.</p>'; return; 
    }
    
    if (container.querySelector('p')) {
        container.innerHTML = '';
    }

    const newUids = new Set();
    queue.forEach(song => {
        if (!song._uid) song._uid = Math.random().toString(36).substring(2, 9);
        newUids.add(song._uid);
    });

    const existingElements = new Map();
    const oldRects = new Map();
    Array.from(container.children).forEach(child => {
        if (child.dataset && child.dataset.uid) {
            existingElements.set(child.dataset.uid, child);
            oldRects.set(child.dataset.uid, child.getBoundingClientRect());
            child.style.transition = '';
            child.style.transform = '';
        }
    });

    queue.forEach((song, idx) => {
        const isPlaying = idx === 0;
        let trackDiv = existingElements.get(song._uid);
        
        if (!trackDiv) {
            trackDiv = document.createElement('div');
            trackDiv.dataset.uid = song._uid;
            trackDiv.className = 'track-item';
            
            if (!window.renderedQueueUids || !window.renderedQueueUids.has(song._uid)) {
                trackDiv.classList.add('animate-queue-in');
                trackDiv.addEventListener('animationend', (e) => {
                    if (e.animationName === 'queueItemIn') {
                        trackDiv.classList.remove('animate-queue-in');
                    }
                });
            }
            
            let pre = `<div class="drag-handle" title="Drag to reorder"><span class="material-symbols-rounded">drag_indicator</span></div>`;
            let suf = `<button class="action-btn remove"><span class="material-symbols-rounded">close</span></button>`;
            trackDiv.innerHTML = buildTrackHtml('', song.artist, getArtHtml(song, false), '', pre, suf);
        } else {
            trackDiv.classList.remove('animate-queue-out');
        }
        
        if(isPlaying) {
            trackDiv.classList.add('no-drag');
            trackDiv.style.cssText = 'background: rgba(0,0,0,0.1); border: 1px solid rgba(0,0,0,0.1);';
        } else {
            trackDiv.classList.remove('no-drag');
            trackDiv.style.cssText = '';
        }

        const dragHandle = trackDiv.querySelector('.drag-handle');
        if (dragHandle) dragHandle.style.cssText = isPlaying ? 'opacity:0; cursor:default;' : '';

        if (titleEl) {
            titleEl.innerHTML = '';
            if (isPlaying) {
                titleEl.innerHTML = '<div class="playing-bars"><div class="bar"></div><div class="bar"></div><div class="bar"></div></div> ';
            }
            titleEl.appendChild(document.createTextNode(song.title));
        }

        const mainClick = trackDiv.querySelector('.track-main-click');
        if (mainClick) mainClick.setAttribute('onclick', `playFromQueue(${idx})`);

        const removeBtn = trackDiv.querySelector('.remove');
        if (removeBtn) removeBtn.setAttribute('onclick', `removeFromQueue(${idx})`);

        if (container.children[idx] !== trackDiv) {
            if (container.children[idx]) {
                container.insertBefore(trackDiv, container.children[idx]);
            } else {
                container.appendChild(trackDiv);
            }
        }
    });
    
    Array.from(container.children).forEach(child => {
        if (child.dataset && child.dataset.uid && !newUids.has(child.dataset.uid)) {
            container.removeChild(child);
        }
    });
    
    window.renderedQueueUids = newUids;

    Array.from(container.children).forEach(child => {
        const uid = child.dataset.uid;
        if (uid && oldRects.has(uid)) {
            const oldRect = oldRects.get(uid);
            const newRect = child.getBoundingClientRect();
            const deltaY = oldRect.top - newRect.top;
            
            if (deltaY !== 0) {
                child.style.transform = `translateY(${deltaY}px)`;
                child.style.transition = 'none';
                
                requestAnimationFrame(() => {
                    requestAnimationFrame(() => {
                        child.style.transform = '';
                        child.style.transition = 'transform 0.4s cubic-bezier(0.34, 1.56, 0.64, 1)';
                        
                        const cleanup = (e) => {
                            if (!e || e.propertyName === 'transform') {
                                child.style.transition = '';
                                child.style.transform = '';
                                child.removeEventListener('transitionend', cleanup);
                            }
                        };
                        child.addEventListener('transitionend', cleanup);
                        setTimeout(cleanup, 450);
                    });
                });
            }
        }
    });
}

function playFromQueue(index) {
    if (index === 0) return; 
    
    if (isNativePlayback && window.AndroidMedia && window.AndroidMedia.skipNativeToItem) {
        window.AndroidMedia.skipNativeToItem(index);
        return;
    }
    
    const previousSong = queue.shift();
    if (previousSong) {
        history.unshift(previousSong);
        history = history.slice(0, 50);
    }
    
    const clickedSong = queue.splice(index - 1, 1)[0];
    queue.unshift(clickedSong);
    
    saveSession();
    loadTrack(); 
    if (!isNativePlayback) audio.play(); 
    renderQueue(); 
    renderHistory();
}

function addToQueueById(songId) { const song = searchData.songs.find(s => s && String(s.id) === String(songId)); if(song) pushToQueue(song); }
function addDetailSongToQueue(idx) { pushToQueue(detailData.songs[idx]); }

function pushToQueue(songObj) {
    if (queue.some(s => s && s.id === songObj?.id)) return;
    queue.push({...songObj});
    if (queue.length === 1) { loadTrack(); if (!isNativePlayback) audio.play(); }
    renderQueue(); saveSession();
}

async function addAlbumToQueue(albumId) {
    try { const data = await fetchNd('getAlbum.view', `id=${albumId}`);
        (data['subsonic-response'].album?.song || []).forEach(s => { if (!queue.some(q => q && q.id === s.id)) queue.push({...s}); });
        if(queue.length > 0 && audio.paused && $id('play-icon')?.textContent === 'play_arrow' && queue.length === (data['subsonic-response'].album?.song || []).length) { loadTrack(); if (!isNativePlayback) audio.play(); } 
        renderQueue(); saveSession();
    } catch(e) {}
}

async function addArtistToQueue(artistId) {
    try { const data = await fetchNd('getArtist.view', `id=${artistId}`);
        const nestedSongs = await Promise.all((data['subsonic-response'].artist?.album || []).map(async (alb) => {
            return (await fetchNd('getAlbum.view', `id=${alb.id}`))['subsonic-response'].album?.song || [];
        }));
        const songs = nestedSongs.flat();
        songs.forEach(s => { if (!queue.some(q => q && q.id === s.id)) queue.push({...s}); });
        if(queue.length > 0 && audio.paused && $id('play-icon')?.textContent === 'play_arrow' && queue.length === songs.length) { loadTrack(); if (!isNativePlayback) audio.play(); } 
        renderQueue(); saveSession();
    } catch(e) {}
}

function removeFromQueue(index) {
    if (index === 0) {
        const removed = queue.shift();
        if (removed) {
            history.unshift(removed); 
            history = history.slice(0,50);
        }
        if (queue.length > 0) {
            saveSession(); loadTrack(); audio.play();
        } else { clearQueue(); }
        renderQueue(); renderHistory();
    } else {
        const trackDiv = $id('queue-list')?.children[index];
        if (trackDiv) {
            trackDiv.style.transition = 'all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)';
            trackDiv.style.transform = 'translateX(-100%)';
            trackDiv.style.opacity = '0';
            trackDiv.classList.add('animate-queue-out');
            
            setTimeout(() => {
                queue.splice(index, 1);
                renderQueue(); saveSession();
            }, 300);
        } else {
            queue.splice(index, 1);
            renderQueue(); saveSession();
        }
    }
}

function clearQueue() {
    queue = []; 
    if (isNativePlayback) window.AndroidMedia?.pauseNativeMedia();
    else audio?.pause(); 
    $id('play-icon') && ($id('play-icon').textContent = 'play_arrow');
    
    const titleEl = $id('main-title'); const artistEl = $id('main-artist'); const albumEl = $id('main-album');
    if (titleEl) titleEl.textContent = "Ready to Play"; 
    if (artistEl) artistEl.textContent = "Select a track"; 
    if (albumEl) albumEl.textContent = "--";
    
    const inner = $id('art-flip-inner'); if (inner?.classList.contains('flipped')) inner.classList.remove('flipped');
    const artImg = $id('main-art'); 
    if (artImg) {
        artImg.src = "data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs="; 
        artImg.classList.add('loaded'); 
    }
    const ambient = $id('ambient-bg');
    if (ambient) ambient.style.backgroundImage = 'none';

    progressFill?.classList.remove('is-playing'); 
    if (progressFill) progressFill.style.width = '0%';
    
    const slider = $id('seek-slider');
    if (slider) slider.value = 0;
    
    const current = $id('time-current');
    if (current) current.textContent = '0:00';
    
    const total = $id('time-total');
    if (total) total.textContent = '0:00';
    
    $id('fav-btn')?.classList.remove('favorited'); 
    
    const lyrics = $id('lyrics-content');
    if (lyrics) lyrics.innerHTML = '<p style="opacity:0.5; margin-top:2rem; font-size:1.1rem;">Start playing a track to load lyrics.</p>';
    
    applyDynamicColors(null, isDarkMode); renderQueue(); saveSession();
}

function loadTrack(autoplay = true, syncToNative = true) {
    queue = queue.filter(s => s && s.title);
    if (queue.length === 0) return;
    const song = queue[0]; 
    const currentId = ++loadTrackId;

    if (isNativePlayback) {
        if (autoplay) window.AndroidMedia?.playNativeMedia(song.id, 0);
    } else {
        audio.src = getStreamUrl(song.id);
    }
    
    hasScrobbledCurrentTrack = false;
    hasPrefetchedCurrentTrack = false;

    setTimeout(() => {
        if (currentId !== loadTrackId) return; 

        $id('main-title') && ($id('main-title').textContent = song.title); 
        $id('main-artist') && ($id('main-artist').textContent = song.artist); 
        $id('main-album') && ($id('main-album').textContent = song.album || '');
        
        const coverUrl = getCoverUrl(song.coverArt);

        if (window.AndroidMedia && window.AndroidMedia.updateMetadata) {
            window.AndroidMedia.updateMetadata(song.title, song.artist || '', song.album || '', coverUrl, Math.round((song.duration || 0) * 1000));
        }

        if ('mediaSession' in navigator) {
            navigator.mediaSession.metadata = new MediaMetadata({ 
                title: song.title, 
                artist: song.artist || '', 
                album: song.album || '', 
                artwork: [{ src: coverUrl, sizes: '500x500', type: 'image/jpeg' }] 
            });
            navigator.mediaSession.setActionHandler('play', () => { 
                if (isNativePlayback) window.AndroidMedia?.resumeNativeMedia();
                else audio.play(); 
            }); 
            navigator.mediaSession.setActionHandler('pause', () => { 
                if (isNativePlayback) window.AndroidMedia?.pauseNativeMedia();
                else audio.pause(); 
            });
            navigator.mediaSession.setActionHandler('previoustrack', () => { prevTrack(); }); 
            navigator.mediaSession.setActionHandler('nexttrack', () => { nextTrack(); });
        }

        const playIcon = $id('play-icon');
        if (playIcon) {
            if (autoplay) playIcon.textContent = 'pause';
            else playIcon.textContent = 'play_arrow';
        }

        const favBtn = $id('fav-btn'); 
        if (song.starred) { 
            favBtn.classList.add('favorited'); 
            if (isNativePlayback) window.AndroidMedia.setFavoriteState(true);
        } else { 
            favBtn.classList.remove('favorited'); 
            if (isNativePlayback) window.AndroidMedia.setFavoriteState(false);
        }
        
        const thumbUrl = getThumbUrl(song.coverArt); 
        const artImg = $id('main-art'); 
        
        artImg.classList.remove('loaded'); 
        
        setTimeout(() => {
            if (currentId !== loadTrackId) return;
            artImg.src = coverUrl;
            $id('ambient-bg').style.backgroundImage = `url('${thumbUrl}')`;
        }, 150);

        const isArtFlipped = $id('art-flip-inner').classList.contains('flipped');
        if (isArtFlipped) {
            $id('art-back-content').innerHTML = '<div style="display:flex; justify-content:center; align-items:center; height:100%;"><div class="spinner"></div></div>';
        }

        const isLyricsOpen = $id('lyrics-view').style.display === 'flex';
        if (isLyricsOpen) {
            $id('lyrics-content').innerHTML = '<p style="opacity:0.5; margin-top:2rem; font-size:1.1rem;">Loading lyrics...</p>';
        }

        renderQueue(); 
        saveSession(syncToNative);

        let isHeavyDataLoaded = false;
        
        const loadHeavyData = () => {
            if (currentId !== loadTrackId || isHeavyDataLoaded) return;
            isHeavyDataLoaded = true;
            
            if (isArtFlipped) { fetchArtistInfoForBack(); }
            else { preloadArtistInfo(0); }

            if (isLyricsOpen) { displayLyricsForCurrentTrack(); }
        };

        if (isNativePlayback) {
            loadHeavyData();
        } else {
            audio.addEventListener('playing', loadHeavyData, { once: true });
            setTimeout(loadHeavyData, 1500); 
        }
        
        setTimeout(() => {
            if (currentId === loadTrackId) {
                preloadArtistInfo(1);
                preloadArtistInfo(2);
                preloadLyrics(1);
                prefetchQueueArtwork();
            }
        }, 3000);
    }, 0);
}

function prefetchQueueArtwork() {
    for (let i = 1; i <= 2; i++) {
        if (i < queue.length) {
            const song = queue[i];
            if (song.coverArt) {
                const img = new Image(); img.src = getCoverUrl(song.coverArt);
                const thumb = new Image(); thumb.src = getThumbUrl(song.coverArt);
            }
        }
    }
}

async function toggleFavorite() {
    if (queue.length === 0) return;
    const song = queue[0]; const isStarred = !!song.starred; const favBtn = $id('fav-btn');
    favBtn.classList.remove('favorited'); void favBtn.offsetWidth; 
    favBtn.classList.add('heart-click-anim');
    setTimeout(() => favBtn.classList.remove('heart-click-anim'), 300);
    
    try {
        const endpoint = isStarred ? 'unstar.view' : 'star.view';
        const res = await fetch(`${nd.url}/rest/${endpoint}?id=${song.id}&${getBaseParams()}`); const data = await res.json();
        if (data['subsonic-response'].status === 'ok') { 
            if (isStarred) { 
                delete song.starred; 
                if (isNativePlayback) window.AndroidMedia.setFavoriteState(false);
            } else { 
                song.starred = new Date().toISOString(); 
                favBtn.classList.add('favorited'); 
                if (isNativePlayback) window.AndroidMedia.setFavoriteState(true);
            } 
        }
    } catch (e) { console.error("Failed to sync favorite status.", e); }
}

function toggleLyricsView() {
    const searchView = $id('search-view');
    const detailView = $id('detail-view');
    const lyricsView = $id('lyrics-view');
    const lyricsBtn = $id('lyrics-btn');
    const artWrapper = $id('art-wrapper');

    if (lyricsBtn.classList.contains('active')) {
        lyricsBtn.classList.remove('active');
        lyricsView.style.animation = 'viewFadeOut 0.25s cubic-bezier(0.2, 0, 0, 1) forwards';
        
        setTimeout(() => {
            lyricsView.style.display = 'none';
            lyricsView.style.animation = ''; 
            
            if (window.innerWidth <= 850) {
                artWrapper.style.display = 'block';
                artWrapper.style.animation = 'none'; artWrapper.offsetHeight; artWrapper.style.animation = 'viewFadeIn 0.4s cubic-bezier(0.2, 0, 0, 1) forwards';
            } else {
                searchView.style.animation = 'none'; searchView.offsetHeight; searchView.style.animation = 'viewFadeIn 0.4s cubic-bezier(0.2, 0, 0, 1) forwards'; searchView.style.display = 'flex';
            }
        }, 250);
    } else {
        lastOpenedPanel = 'lyrics';
        lyricsBtn.classList.add('active');
        lyricsView.style.display = 'flex';
        
        if (window.innerWidth <= 850) {
            if (lyricsView.parentNode !== artWrapper.parentNode) {
                artWrapper.parentNode.insertBefore(lyricsView, artWrapper.nextSibling);
                lyricsView.classList.add('lyrics-mobile-overlay');
                lyricsView.style.width = ''; lyricsView.style.maxWidth = ''; lyricsView.style.aspectRatio = ''; lyricsView.style.maxHeight = ''; lyricsView.style.background = ''; lyricsView.style.marginBottom = ''; lyricsView.style.borderRadius = '';
            }
            artWrapper.style.display = 'none';
        } else {
            const discoverPanel = $id('discover-panel');
            if (lyricsView.parentNode !== discoverPanel) {
                discoverPanel.appendChild(lyricsView);
                lyricsView.classList.remove('lyrics-mobile-overlay');
                lyricsView.style.width = ''; lyricsView.style.maxWidth = ''; lyricsView.style.aspectRatio = ''; lyricsView.style.maxHeight = ''; lyricsView.style.background = ''; lyricsView.style.marginBottom = ''; lyricsView.style.borderRadius = '';
            }
            searchView.style.display = 'none';
            detailView.style.display = 'none';
        }
        
        if (queue.length > 0 && currentlyLoadedLyricsId !== queue[0].id) {
            displayLyricsForCurrentTrack();
        }
    }
}

async function fetchLyricData(song) {
    let url = `https://lrclib.net/api/get?track_name=${encodeURIComponent(song.title)}&artist_name=${encodeURIComponent(song.artist)}&album_name=${encodeURIComponent(song.album || '')}`;
    let res = await fetch(url); if (res.ok) { return await res.json(); }
    let searchUrl = `https://lrclib.net/api/search?q=${encodeURIComponent(song.artist + ' ' + song.title)}`;
    let searchRes = await fetch(searchUrl); let searchData = await searchRes.json();
    if (searchData && searchData.length > 0) { return searchData[0]; }
    throw new Error('Not found');
}

function preloadLyrics(index) {
    if (index < 0 || index >= queue.length) return;
    const song = queue[index]; if (lyricsCache[song.id]) return;
    const promise = fetchLyricData(song).then(data => { lyricsCache[song.id] = { status: 'loaded', data: data }; }).catch(err => { lyricsCache[song.id] = { status: 'not_found' }; });
    lyricsCache[song.id] = { status: 'loading', promise: promise };
}

async function displayLyricsForCurrentTrack() {
    const container = $id('lyrics-content');
    if (queue.length === 0) return;
    
    const song = queue[0]; currentLyrics = []; currentLyricIndex = -1;
    currentlyLoadedLyricsId = song.id; 
    
    container.innerHTML = '<p style="opacity:0.5; margin-top:2rem; font-size:1.1rem;">Loading lyrics...</p>';

    if (useNavidromeLyrics) {
        try {
            const res = await fetch(`${nd.url}/rest/getLyrics.view?artist=${encodeURIComponent(song.artist || '')}&title=${encodeURIComponent(song.title || '')}&${getBaseParams()}`);
            const data = await res.json(); const lyricsData = data['subsonic-response'].lyrics;
            if (lyricsData && lyricsData.value) { 
                if (/\[\d{2,}:\d{2}/.test(lyricsData.value)) {
                    parseLrc(lyricsData.value); await triggerTranslation();
                } else {
                    renderPlainLyrics(lyricsData.value); 
                }
            } else { container.innerHTML = '<p style="opacity:0.5; margin-top:2rem; font-size:1.1rem;">No lyrics found on server.</p>'; }
        } catch (e) { container.innerHTML = '<p style="opacity:0.5; margin-top:2rem; font-size:1.1rem;">Failed to fetch from server.</p>'; }
        return; 
    }

    preloadLyrics(0);
    const cacheEntry = lyricsCache[song.id];
    if (cacheEntry && cacheEntry.status === 'loading') { try { await cacheEntry.promise; } catch(e) {} }

    const finalCache = lyricsCache[song.id];
    if (finalCache && finalCache.status === 'loaded' && finalCache.data) {
        const trackData = finalCache.data;
        if (trackData.syncedLyrics) { parseLrc(trackData.syncedLyrics); await triggerTranslation(); } 
        else if (trackData.plainLyrics) { renderPlainLyrics(trackData.plainLyrics); } 
        else { container.innerHTML = '<p style="opacity:0.5; margin-top:2rem; font-size:1.1rem;">No lyrics found for this track.</p>'; }
    } else { container.innerHTML = '<p style="opacity:0.5; margin-top:2rem; font-size:1.1rem;">No lyrics found for this track.</p>'; }
}

function parseLrc(lrcText) {
    currentLyrics = []; const lines = lrcText.split('\n'); const regex = /\[(\d{2,}):(\d{2})(?:\.(\d{1,3}))?\](.*)/;
    for (const line of lines) {
        const match = line.match(regex);
        if (match) {
            const min = parseInt(match[1]); 
            const sec = parseInt(match[2]); 
            const ms = match[3] ? parseFloat('0.' + match[3]) : 0;
            const text = match[4].trim();
            if(text) { currentLyrics.push({ time: (min * 60) + sec + ms, text: text, translations: {} }); }
        }
    }
}

async function triggerTranslation() {
    const lang = $id('lyrics-lang').value;
    localStorage.setItem('m3_trans_lang', lang);
    if (lang === 'none' || currentLyrics.length === 0) { renderLyricsUI(); return; }
    if (currentLyrics[0].translations && currentLyrics[0].translations[lang] !== undefined && currentLyrics[0].translations[lang] !== '') { renderLyricsUI(); return; }
    const container = $id('lyrics-content'); container.innerHTML = '<p style="opacity:0.5; margin-top:2rem; font-size:1.1rem;">Translating lyrics...</p>';

    try {
        const textToTranslate = currentLyrics.map(l => l.text).join('\n');
        const url = `https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=${lang}&dt=t`;
        const res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', }, body: 'q=' + encodeURIComponent(textToTranslate) });
        const data = await res.json(); const detectedLang = data[2]; 
        
        if (detectedLang && detectedLang.toLowerCase() === lang.toLowerCase()) {
            for (let i = 0; i < currentLyrics.length; i++) { if (!currentLyrics[i].translations) currentLyrics[i].translations = {}; currentLyrics[i].translations[lang] = ''; }
        } else {
            const translatedText = data[0].map(item => item[0] || '').join(''); const translatedLines = translatedText.split('\n');
            for (let i = 0; i < currentLyrics.length; i++) { if (!currentLyrics[i].translations) currentLyrics[i].translations = {}; currentLyrics[i].translations[lang] = translatedLines[i] ? translatedLines[i].trim() : ''; }
        }
        renderLyricsUI();
    } catch (e) {
        console.error("Translation API failure", e); container.innerHTML = `<p style="opacity:0.5; margin-top:2rem; font-size:1.1rem; color: var(--md-sys-color-error);">Translation failed. Click to retry.</p>`;
        container.onclick = () => { container.onclick = null; triggerTranslation(); };
    }
}

function renderLyricsUI() {
    const container = $id('lyrics-content'); if (currentLyrics.length === 0) return;
    const lang = $id('lyrics-lang').value; let html = '';
    
    currentLyrics.forEach((line, idx) => {
        let transHtml = ''; if (lang !== 'none' && line.translations && line.translations[lang]) { transHtml = `<div class="lyric-trans">${line.translations[lang]}</div>`; }
        html += `<div class="lyric-line" id="lyric-line-${idx}" onclick="seekToLyric(${line.time})"><div class="lyric-orig">${line.text}</div>${transHtml}</div>`;
    });
    container.innerHTML = html; syncLyricsStatus(); 
}

function renderPlainLyrics(text) {
    const container = $id('lyrics-content'); const lines = text.split('\n').filter(l => l.trim() !== ''); let html = '';
    lines.forEach(line => { html += `<div class="lyric-line" style="cursor:default;"><div class="lyric-orig">${line}</div></div>`; });
    container.innerHTML = html;
}

const isNativePlayback = !!(window.AndroidMedia && window.AndroidMedia.playNativeMedia);

function seekToLyric(time) { 
    const dur = isNativePlayback ? (queue[0]?.duration || 0) : audio.duration;
    if (dur) { 
        if (isNativePlayback) window.AndroidMedia.seekNativeMedia(time * 1000);
        else audio.currentTime = time; 
    } 
}

function togglePlayPause() {
    if (isNativePlayback) {
        if (progressFill.classList.contains('is-playing')) {
            window.AndroidMedia.pauseNativeMedia();
            $id('play-icon').textContent = 'play_arrow';
            progressFill.classList.remove('is-playing');
        } else {
            window.AndroidMedia.resumeNativeMedia();
            $id('play-icon').textContent = 'pause';
            progressFill.classList.add('is-playing');
        }
    } else {
        if (audio.paused) { audio.play(); $id('play-icon').textContent = 'pause'; }
        else { audio.pause(); $id('play-icon').textContent = 'play_arrow'; }
    }
}

function nextTrack() {
    if (isNativePlayback && window.AndroidMedia.skipNativeNext) {
        window.AndroidMedia.skipNativeNext();
        return;
    }
    if (queue.length <= 1) { 
        if (queue.length === 1) { history.unshift(queue.shift()); history = history.slice(0,50); clearQueue(); }
        return; 
    }
    const oldSong = queue.shift(); history.unshift(oldSong); history = history.slice(0,50);
    loadTrack(); 
    if (!isNativePlayback) audio.play();
}

function prevTrack() {
    const currentTime = isNativePlayback ? (parseInt($id('seek-slider').value) / 1000) * (queue[0]?.duration || 0) : audio.currentTime;
    if (currentTime > 3 || history.length === 0) { 
        if (isNativePlayback) window.AndroidMedia.seekNativeMedia(0);
        else audio.currentTime = 0; 
        return; 
    }
    if (isNativePlayback && window.AndroidMedia.skipNativePrevious) {
        window.AndroidMedia.skipNativePrevious();
        return;
    }
    queue.unshift(history.shift());
    loadTrack(); 
    if (!isNativePlayback) audio.play();
}

function toggleLoop() {
    isLooping = !isLooping;
    const btn = $id('loop-btn'); if(isLooping) btn.classList.add('active'); else btn.classList.remove('active');
}

async function shuffleAction() {
    if (queue.length === 0) {
        try {
            const data = await fetchNd('getRandomSongs.view', 'size=10');
            const randomSongs = data['subsonic-response'].randomSongs?.song || [];
            if(randomSongs.length > 0) { queue = randomSongs; saveSession(); loadTrack(); audio.play(); }
        } catch (e) {}
    } else {
        if (queue.length > 1) {
            const activeSong = queue.shift();
            for (let i = queue.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [queue[i], queue[j]] = [queue[j], queue[i]]; }
            queue.unshift(activeSong);
        }
        renderQueue(); saveSession();
    }
}

const progressFill = $id('progress-fill'); const seekSlider = $id('seek-slider'); let isDraggingSeek = false;

seekSlider.addEventListener('input', (e) => {
    isDraggingSeek = true; const percentage = e.target.value / 10; progressFill.style.width = `${percentage}%`;
    const dur = isNativePlayback ? (queue[0]?.duration || 0) : audio.duration;
    if (dur) { $id('time-current').textContent = formatTime((percentage / 100) * dur); }
});

seekSlider.addEventListener('change', (e) => {
    const percentage = e.target.value / 10; 
    const dur = isNativePlayback ? (queue[0]?.duration || 0) : audio.duration;
    if (dur) { 
        if (isNativePlayback) window.AndroidMedia.seekNativeMedia((percentage / 100) * dur * 1000);
        else audio.currentTime = (percentage / 100) * dur; 
    }
    isDraggingSeek = false;
});

audio.addEventListener('play', () => { 
    progressFill.classList.add('is-playing'); $id('play-icon').textContent = 'pause';
    if ('mediaSession' in navigator) navigator.mediaSession.playbackState = "playing";
    if (window.AndroidMedia) window.AndroidMedia.updatePlaybackState(true);
    reportNowPlaying();
});

audio.addEventListener('pause', () => { 
    progressFill.classList.remove('is-playing'); $id('play-icon').textContent = 'play_arrow';
    if ('mediaSession' in navigator) navigator.mediaSession.playbackState = "paused";
    if (window.AndroidMedia) window.AndroidMedia.updatePlaybackState(false);
});

audio.addEventListener('ended', () => { 
    progressFill.classList.remove('is-playing');
    if (isLooping) { 
        if (isNativePlayback) window.AndroidMedia.seekNativeMedia(0); 
        else { audio.currentTime = 0; audio.play(); } 
    } else { nextTrack(); }
});

window.updateNativeTime = function(currentTimeSec) {
    currentTimeSec = currentTimeSec / 1000;
    const dur = isNativePlayback ? (queue[0]?.duration || 0) : audio.duration;
    
    $id('time-current').textContent = formatTime(currentTimeSec);
    $id('time-total').textContent = formatTime(dur);
    if (dur > 0 && !isDraggingSeek) {
        const percentage = (currentTimeSec / dur) * 100;
        progressFill.style.width = `${percentage}%`; 
        seekSlider.value = percentage * 10;
        if (percentage >= 25 && !hasPrefetchedCurrentTrack) { prefetchMixPool(); hasPrefetchedCurrentTrack = true; }
        if (percentage >= 50 && !hasScrobbledCurrentTrack) { scrobbleCurrentTrack(); }
    }
    
    audio.currentTime = currentTimeSec; 
    syncLyricsStatus();
};

window.nativePlayStateChanged = function(isPlaying) {
    if (isPlaying) {
        progressFill.classList.add('is-playing');
        $id('play-icon').textContent = 'pause';
    } else {
        progressFill.classList.remove('is-playing');
        $id('play-icon').textContent = 'play_arrow';
    }
};

window.nativeTrackEnded = function() {
    progressFill.classList.remove('is-playing');
    if (isLooping) { 
        if (isNativePlayback) window.AndroidMedia.seekNativeMedia(0);
    } else { 
        nextTrack(); 
    }
};

function formatTime(sec) {
    if (isNaN(sec)) return "0:00";
    const min = Math.floor(sec / 60); const s = Math.floor(sec % 60); return `${min}:${s.toString().padStart(2, '0')}`;
}

function syncLyricsStatus() {
    if (currentLyrics.length > 0) {
        let newIndex = -1;
        for (let i = 0; i < currentLyrics.length; i++) { if (audio.currentTime >= currentLyrics[i].time - 0.25) { newIndex = i; } else { break; } }
        if (newIndex !== currentLyricIndex && newIndex !== -1) {
            if (currentLyricIndex !== -1) { const oldEl = $id(`lyric-line-${currentLyricIndex}`); if (oldEl) oldEl.classList.remove('active'); }
            currentLyricIndex = newIndex; const newEl = $id(`lyric-line-${currentLyricIndex}`);
            if (newEl) { 
                newEl.classList.add('active'); 
                const container = $id('lyrics-content');
                // We add newEl.clientHeight to scrollPos to scroll down a bit more,
                // which visually pushes the active lyric UP by one line on the screen.
                const scrollPos = newEl.offsetTop - (container.clientHeight / 2) + (newEl.clientHeight * 1.5);
                container.scrollTo({ top: scrollPos, behavior: 'smooth' });
            }
        }
    }
}

audio.addEventListener('timeupdate', () => {
    if (!isDraggingSeek) {
        $id('time-current').textContent = formatTime(audio.currentTime);
        if (audio.duration > 0) { 
            const percentage = (audio.currentTime / audio.duration) * 100; 
            progressFill.style.width = `${percentage}%`; 
            seekSlider.value = percentage * 10; 
            
            if (percentage >= 25 && !hasPrefetchedCurrentTrack) {
                prefetchMixPool();
                hasPrefetchedCurrentTrack = true;
            }
            
            if (percentage >= 50 && !hasScrobbledCurrentTrack) { 
                scrobbleCurrentTrack(); 
            }
        }
    }
    syncLyricsStatus();
});

audio.addEventListener('loadedmetadata', () => { $id('time-total').textContent = formatTime(audio.duration); });

let resizeTimer;
window.addEventListener('resize', () => {
    document.body.classList.add('no-resize-transition'); 
    clearTimeout(resizeTimer); 
    resizeTimer = setTimeout(() => { document.body.classList.remove('no-resize-transition'); }, 100);
    
    const lyricsBtn = $id('lyrics-btn');
    const lyricsView = $id('lyrics-view');
    const artWrapper = $id('art-wrapper');
    if (lyricsBtn && lyricsBtn.classList.contains('active')) {
        if (window.innerWidth <= 850) {
            if (lyricsView.parentNode !== artWrapper.parentNode) {
                artWrapper.parentNode.insertBefore(lyricsView, artWrapper.nextSibling);
                lyricsView.classList.add('lyrics-mobile-overlay');
                lyricsView.style.width = ''; lyricsView.style.maxWidth = ''; lyricsView.style.aspectRatio = ''; lyricsView.style.maxHeight = ''; lyricsView.style.background = ''; lyricsView.style.marginBottom = ''; lyricsView.style.borderRadius = '';
                artWrapper.style.display = 'none';
                
                // Restore discover panel contents since lyrics moved out
                if (detailData.id) {
                    $id('detail-view').style.display = 'flex';
                } else {
                    $id('search-view').style.display = 'flex';
                }
            }
        } else {
            const discoverPanel = $id('discover-panel');
            if (lyricsView.parentNode !== discoverPanel) {
                discoverPanel.appendChild(lyricsView);
                lyricsView.classList.remove('lyrics-mobile-overlay');
                lyricsView.style.width = ''; lyricsView.style.maxWidth = ''; lyricsView.style.aspectRatio = ''; lyricsView.style.maxHeight = ''; lyricsView.style.background = ''; lyricsView.style.marginBottom = ''; lyricsView.style.borderRadius = '';
                artWrapper.style.display = 'block';
                $id('search-view').style.display = 'none';
                $id('detail-view').style.display = 'none';
            }
        }
    }

    if (window.innerWidth > 850) { 
        $id('discover-panel').classList.remove('mobile-active'); 
        $id('queue-panel').classList.remove('mobile-active');
        $id('main-app').style.display = $id('login-overlay').style.display === 'none' ? 'grid' : 'none';
    } else {
        $id('main-app').style.display = $id('login-overlay').style.display === 'none' ? 'flex' : 'none';
    }
});

document.addEventListener('submit', function(e) {
    if (e.target && e.target.id === 'login-form') {
        e.preventDefault(); 
        connectNavidrome();
    }
});

document.addEventListener('input', (e) => {
    if (e.target && e.target.id === 'search-input') {
        clearTimeout(searchTimeout);
        searchTimeout = setTimeout(() => {
            if(e.target.value.trim()) { performSearch(); }
            else { loadDefaultContent(); }
        }, 500);
    }
});

document.addEventListener('keydown', (e) => {
    if(e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    if(e.code === 'Space') { e.preventDefault(); togglePlayPause(); }
    if(e.shiftKey && e.code === 'ArrowRight') { e.preventDefault(); nextTrack(); }
    if(e.shiftKey && e.code === 'ArrowLeft') { e.preventDefault(); prevTrack(); }
});

const volumeSlider = $id('volume-slider');
if (volumeSlider) {
    volumeSlider.addEventListener('input', (e) => {
        audio.volume = e.target.value;
        if (audio.volume === 0) {
            $id('mute-icon').textContent = 'volume_off';
            isMuted = true;
        } else {
            $id('mute-icon').textContent = 'volume_up';
            isMuted = false;
            previousVolume = audio.volume;
        }
    });
}

// --- Swipe Gestures ---
let touchStartX = 0;
let touchStartY = 0;
let swipeTarget = null;
let lastOpenedPanel = 'queue'; 
let activeDragElement = null;
let isDraggingDown = false;

document.addEventListener('touchstart', (e) => {
    touchStartX = e.changedTouches[0].screenX;
    touchStartY = e.changedTouches[0].screenY;
    swipeTarget = e.target;
    activeDragElement = null;
    isDraggingDown = false;

    // Identify if we can drag down.
    // Ensure we are at the top of scrollable content if applicable
    const scrollable = swipeTarget.closest('.scrollable-content');
    if (scrollable && scrollable.scrollTop > 0) {
        return; // User can scroll up natively, don't drag panel
    }
    
    if (swipeTarget.closest('.drag-handle')) {
        return; // User is trying to reorder the queue, do not trigger panel drag
    }

    if (swipeTarget.closest('#queue-panel')) {
        activeDragElement = $id('queue-panel');
    } else if (swipeTarget.closest('#lyrics-view') && $id('lyrics-view').style.display === 'flex') {
        activeDragElement = (window.innerWidth <= 850) ? $id('discover-panel') : $id('lyrics-view');
    } else if (swipeTarget.closest('#detail-view') && $id('detail-view').style.display === 'flex') {
        activeDragElement = (window.innerWidth <= 850) ? $id('discover-panel') : $id('detail-view');
    } else if (window.innerWidth <= 850 && swipeTarget.closest('#discover-panel')) {
        activeDragElement = $id('discover-panel');
    }
    
    // Ignore range inputs
    if (swipeTarget.tagName.toLowerCase() === 'input' && swipeTarget.type === 'range') {
        activeDragElement = null;
    }
}, {passive: true});

document.addEventListener('touchmove', (e) => {
    if (!activeDragElement) return;
    
    const touchCurrentY = e.changedTouches[0].screenY;
    const touchCurrentX = e.changedTouches[0].screenX;
    const deltaY = touchCurrentY - touchStartY;
    const deltaX = touchCurrentX - touchStartX;
    
    // Determine if user is dragging down intentionally
    if (!isDraggingDown && deltaY > 10 && Math.abs(deltaY) > Math.abs(deltaX)) {
        isDraggingDown = true;
    }

    if (isDraggingDown && deltaY > 0) {
        if (e.cancelable) e.preventDefault();
        
        // Disable transition during drag for 1:1 finger tracking
        activeDragElement.style.transition = 'none';
        
        // Add a slight resistance effect as it drags further
        const dragAmount = Math.pow(deltaY, 0.95);
        activeDragElement.style.transform = `translateY(${dragAmount}px)`;
    }
}, {passive: false});

document.addEventListener('touchend', (e) => {
    const touchEndX = e.changedTouches[0].screenX;
    const touchEndY = e.changedTouches[0].screenY;
    const deltaX = touchEndX - touchStartX;
    const deltaY = touchEndY - touchStartY;
    const absX = Math.abs(deltaX);
    const absY = Math.abs(deltaY);
    
    if (isDraggingDown && activeDragElement) {
        // Restore CSS transitions
        activeDragElement.style.transition = '';
        
        if (deltaY > 150) {
            // Dragged far enough to dismiss
            activeDragElement.style.transform = ''; // Let CSS take over
            
            if (activeDragElement.id === 'queue-panel') {
                if (window.innerWidth <= 850) {
                    $id('queue-panel').classList.remove('mobile-active');
                } else if (!$id('main-app').classList.contains('queue-hidden-reduced')) {
                    toggleReducedQueue();
                }
            } else if (activeDragElement.id === 'discover-panel') {
                $id('discover-panel').classList.remove('mobile-active');
            } else if (activeDragElement.id === 'lyrics-view') {
                toggleLyricsView();
            } else if (activeDragElement.id === 'detail-view') {
                closeDetailView();
            }
        } else {
            // Didn't drag far enough, snap back
            activeDragElement.style.transform = '';
        }
        
        activeDragElement = null;
        isDraggingDown = false;
        return;
    }

    activeDragElement = null;
    isDraggingDown = false;

    // Standard tap/swipe logic (for left/right and up)
    if (absX < 40 && absY < 40) return; // Too short
    
    const isHorizontal = absX > absY;
    
    if (isHorizontal) {
        if (swipeTarget.closest('.center-stage') || swipeTarget.closest('#lyrics-view')) {
            if (swipeTarget.tagName.toLowerCase() === 'input' && swipeTarget.type === 'range') return;
            if (deltaX < -50) nextTrack();
            else if (deltaX > 50) prevTrack();
        }
    } else {
        if (deltaY < -50) { 
            // Swipe Up to open
            if (swipeTarget.closest('.bottom-bar')) {
                if (lastOpenedPanel === 'lyrics') {
                    if ($id('lyrics-view').style.display !== 'flex') toggleLyricsView();
                } else {
                    if (window.innerWidth <= 850) {
                        $id('queue-panel').classList.add('mobile-active');
                        $id('discover-panel').classList.remove('mobile-active');
                    } else if ($id('main-app').classList.contains('queue-hidden-reduced')) {
                        toggleReducedQueue();
                    }
                }
            }
        }
    }
}, {passive: true});
