// A level's background loop: a port of the level's autoplaying AudioStreamPlayer (the parking lot's BackgroundMusic,
// on the Music bus). The level JSON's "music" gives the file, the loop's length and the volume (player + bus).
// The file (audio/<name>.mp3, cut by tools/audio/make_ambience_loops.py) is the loop plus a few seconds of what
// follows it in the recording. Each pass starts exactly one loop length after the last and the two crossfade over
// that tail, the same crossfade the Godot .ogg has baked in; overlapping copies (rather than `loop = true`) means
// the MP3's encoder padding can't leave a gap. Keeps playing while paused, like the Godot node (process_mode always).
import { audioContext } from './sound.js';

const LEAD = 75;          // s: queue the next pass this long before it starts (background tabs run timers once a minute)
const buffers = {};       // file -> AudioBuffer | 'loading'
let want = null;          // the current level's "music", or null
let out = null;           // GainNode at the level's volume
let passes = [];          // [{src, gain, start}]
let nextStart = 0;        // AudioContext time the next pass starts at

const dbToGain = db => Math.pow(10, db / 20);

/** The level changed: stop the old loop and play `music` (level JSON "music", or null for none). */
export function setMusic(music) {
  if (want && music && want.file === music.file && out) return;   // same loop: keep it going
  stop();
  want = music || null;
  tick();
}

function stop() {
  const audio = audioContext();
  if (out && audio) {
    const t = audio.currentTime, o = out, ps = passes;
    o.gain.cancelScheduledValues(t); o.gain.setTargetAtTime(0, t, 0.1);
    setTimeout(() => { for (const p of ps) { try { p.src.stop(); } catch (e) { /* done */ } p.src.disconnect(); p.gain.disconnect(); } o.disconnect(); }, 800);
  }
  out = null; passes = [];
}

/** Starts the loop once sound is allowed and the file has loaded, and keeps queueing passes. */
async function tick() {
  const audio = audioContext(), m = want;
  if (!audio || !m) return;
  let buf = buffers[m.file];
  if (!buf) {
    buffers[m.file] = 'loading';
    try { buf = buffers[m.file] = await audio.decodeAudioData(await (await fetch(m.file)).arrayBuffer()); }
    catch (e) { console.warn('Background loop did not load', m.file, e); delete buffers[m.file]; return; }
    if (want !== m) return;
  }
  if (!(buf instanceof AudioBuffer)) return;
  const len = m.loop_length, fade = Math.max(0.05, Math.min(buf.duration - len, 8));
  if (!out) {
    out = new GainNode(audio, { gain: 0 });
    out.connect(audio.destination);
    out.gain.setTargetAtTime(dbToGain(m.volume_db), audio.currentTime, 0.3);
    nextStart = audio.currentTime + 0.05;
    queue(audio, buf, len, fade, true);
  }
  if (nextStart < audio.currentTime + 0.05) { nextStart = audio.currentTime + 0.05; queue(audio, buf, len, fade, true); }   // fell behind
  while (nextStart - audio.currentTime < LEAD) queue(audio, buf, len, fade, false);
}

// One pass: fades in over the last pass's tail (equal power, as the .ogg's baked crossfade), plays, fades out over
// the next pass's head.
function queue(audio, buf, len, fade, first) {
  const t0 = nextStart, n = 64;
  const fadeIn = new Float32Array(n), fadeOut = new Float32Array(n);
  for (let i = 0; i < n; i++) { const a = i / (n - 1) * Math.PI / 2; fadeIn[i] = Math.sin(a); fadeOut[i] = Math.cos(a); }
  const gain = new GainNode(audio, { gain: first ? 1 : 0 });
  if (!first) gain.gain.setValueCurveAtTime(fadeIn, t0, fade);
  gain.gain.setValueCurveAtTime(fadeOut, t0 + len, fade);
  const src = new AudioBufferSourceNode(audio, { buffer: buf });
  src.connect(gain).connect(out);
  src.start(t0);
  src.stop(t0 + len + fade);
  src.onended = () => { src.disconnect(); gain.disconnect(); passes = passes.filter(p => p.src !== src); };
  passes.push({ src, gain, start: t0 });
  nextStart = t0 + len;
}

setInterval(tick, 1000);

/** Call after the first tap (once sound is allowed) so the loop starts without waiting for the timer. */
export const startMusic = () => tick();

/** For the test: what should be playing and what is. */
export function musicState() {
  const audio = audioContext();
  return { file: want && want.file, loaded: !!(want && buffers[want.file] instanceof AudioBuffer), playing: !!out,
    passes: passes.length, volumeDb: want && want.volume_db, nextIn: out && audio ? nextStart - audio.currentTime : null };
}
