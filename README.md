#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
import sys
import time
import json
import websocket
import threading
from collections import deque
import queue
import warnings
sys.path.append('/opt/nvidia/deepstream/deepstream/sources/deepstream_python_apps/bindings/python')
import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst, GLib
import pyds
from datetime import datetime, timedelta
import socket
import cv2
import numpy as np
import uuid
import requests
from urllib.parse import urlparse, urlunparse, quote

# Suppress deprecation warnings
warnings.filterwarnings('ignore', category=DeprecationWarning)

# ============= VERBOSITY CONTROL =============
VERBOSE = False  # Set to True for detailed debugging

def log(message, level="INFO"):
    """Conditional logging based on verbosity."""
    if level == "ERROR":
        print(f"❌ {message}")
    elif level == "WARN":
        print(f"⚠️  {message}")
    elif level == "SUCCESS":
        print(f"✅ {message}")
    elif VERBOSE:
        print(message)

# ============= CONFIG =============
MUXER_OUTPUT_WIDTH = 1280
MUXER_OUTPUT_HEIGHT = 720
RELAY_URL = "http://192.168.0.35:31425"
WS_URL = "ws://192.168.0.35:31425/edge"
SOURCE_CONNECTION_TIMEOUT = 5
SNAPSHOT_WORKERS = 3

# ============= RECONNECTION / WATCHDOG =============
RECONNECT_INTERVAL_SEC    = 60     # delay between reconnect attempts
WATCHDOG_THRESHOLD_SEC    = 30.0   # frame-silence before declaring camera offline
WATCHDOG_INTERVAL_SEC     = 15     # watchdog tick interval
OFFLINE_SCAN_INTERVAL_SEC = 30     # safety-net offline rescan interval

# ============= PPE STATE MANAGEMENT CONFIG =============
FRAMES_TO_GAIN_PPE = 5
FRAMES_TO_LOSE_PPE = 15
STATE_CHANGE_GRACE_PERIOD = 10
DETECTION_HISTORY_SIZE = 20
VIOLATION_ALERT_INTERVAL = 5
ALERT_EXPIRY_SECONDS = 300
# Persons whose bbox height (in 1280x720 muxer pixels) meets this are close enough
# that the PPE model should reliably see helmet/mask/vest. For these, "model said
# nothing" can be trusted as "PPE not worn". Smaller persons are too far for that
# assumption — we only update their state when an explicit class fires.
MIN_TRUST_BBOX_HEIGHT = 100

# ============= PPE MODEL CONFIG =============
PRIMARY_PERSON_CLASS_ID = 0

PPE_LABELS = [
    "Hardhat/Helmet",       # 0
    "Mask",                 # 1
    "NO-Hardhat/Helmet",    # 2
    "NO-Mask",              # 3
    "NO-Safety Vest",       # 4
    "Person",               # 5 (ignored)
    "Safety Cone",          # 6 (ignored)
    "Safety Vest"           # 7
]

PPE_MAP = {
    0: ("Helmet", True),
    1: ("Mask", True),
    2: ("Helmet", False),
    3: ("Mask", False),
    4: ("Vest", False),
    7: ("Vest", True),
}

IGNORE_CLASSES = [5, 6]
PPE_CATEGORIES = ["Helmet", "Mask", "Vest"]

# ============= PPE STATE CLASS =============
class PPEState:
    """State machine for tracking PPE detection with hysteresis"""
    def __init__(self):
        self.current_state = None
        self.positive_streak = 0
        self.negative_streak = 0
        self.detection_history = deque(maxlen=DETECTION_HISTORY_SIZE)
        self.last_state_change = 0
        self.state_locked_until = 0
        self.total_positive_detections = 0
        self.total_negative_detections = 0
        # Running count of positives in the last-10 window (avoids list+slice+sum per frame).
        self._recent_positive = 0

    def update_detection(self, detected, current_time):
        history = self.detection_history
        # If history already holds >=10 entries, the element currently at index -10 will
        # slide out of the "last 10" window after this append; subtract it from the running count.
        if len(history) >= 10 and history[-10]:
            self._recent_positive -= 1
        history.append(detected)

        if detected:
            self._recent_positive += 1
            self.positive_streak += 1
            self.negative_streak = 0
            self.total_positive_detections += 1
        else:
            self.negative_streak += 1
            self.positive_streak = 0
            self.total_negative_detections += 1

        if current_time < self.state_locked_until:
            return False, self.current_state

        state_changed = False

        # GAINING PPE
        if self.current_state != True and self.positive_streak >= FRAMES_TO_GAIN_PPE:
            self.current_state = True
            self.last_state_change = current_time
            self.state_locked_until = current_time + STATE_CHANGE_GRACE_PERIOD
            state_changed = True
            log(f"PPE GAINED after {self.positive_streak} detections")
            self.positive_streak = 0
            self.negative_streak = 0

        # LOSING PPE
        elif self.current_state != False and self.negative_streak >= FRAMES_TO_LOSE_PPE:
            recent_size = min(len(history), 10)
            positive_ratio = self._recent_positive / recent_size if recent_size else 0
            if positive_ratio < 0.2:
                self.current_state = False
                self.last_state_change = current_time
                self.state_locked_until = current_time + STATE_CHANGE_GRACE_PERIOD
                state_changed = True
                log(f"PPE LOST after {self.negative_streak} non-detections")
                self.positive_streak = 0
                self.negative_streak = 0

        return state_changed, self.current_state

    def get_confidence(self):
        if not self.detection_history:
            return 0.0
        recent_size = min(len(self.detection_history), 10)
        ratio = self._recent_positive / recent_size
        return ratio if self.current_state else 1.0 - ratio

# ============= JPEG ENCODER (x86 dGPU: software via OpenCV) =============
def encode_jpeg(frame_bgr, quality=85):
    """Encode BGR numpy array to JPEG bytes using OpenCV (software)."""
    try:
        ok, jpg_buf = cv2.imencode('.jpg', frame_bgr, [cv2.IMWRITE_JPEG_QUALITY, quality])
        if not ok:
            log("cv2.imencode failed", "ERROR")
            return None
        return jpg_buf.tobytes()
    except Exception as e:
        log(f"JPEG encoding error: {e}", "ERROR")
        return None

# ============= GLOBAL STATE =============
tracked_states = {}
last_send_times = {}
last_state_snapshot = {}
alerts_sent_for_person_ids = {}

device_configs = {}
source_mgr = None  # SourceManager instance — initialized in main()

pipeline = None
streammux = None
loop = None
ws = None
ws_lock = threading.Lock()
facility_id = None
number_sources = 0

shutdown_flag = threading.Event()
snapshot_queue = queue.Queue(maxsize=20)
demux_pads = []

# Pooled HTTP session: keep-alive across snapshot uploads avoids per-request TCP+TLS handshakes.
http_session = requests.Session()
_http_adapter = requests.adapters.HTTPAdapter(pool_connections=4, pool_maxsize=8, max_retries=0)
http_session.mount("http://", _http_adapter)
http_session.mount("https://", _http_adapter)

# ============= HELPER FUNCTIONS =============
def safe_iter_pyds_list(head, typecast_fn):
    while head is not None:
        yield typecast_fn(head.data)
        head = head.next


def _state_to_str(s):
    if s is True:
        return "yes"
    if s is False:
        return "no"
    return "unknown"

def _build_rtsp_url(rtsp_link, username, password):
    """
    Embed percent-encoded credentials into an RTSP URL.

    The facility config carries `username` / `password` as separate fields and
    `rtsp_link` as a credential-less URL (e.g. rtsp://host/path). We URL-encode
    the credentials per RFC 3986 userinfo rules so passwords containing
    reserved characters (@ : / ? # [ ] ! $ & ' ( ) * + , ; = % { } ^ ` etc.)
    survive intact through GStreamer's URI parser.

    If `rtsp_link` already contains a userinfo component, it is returned
    unchanged so any pre-credentialed entries keep working.
    """
    if not rtsp_link:
        return rtsp_link

    parsed = urlparse(rtsp_link)
    if parsed.username or parsed.password:
        return rtsp_link
    if not username and not password:
        return rtsp_link

    user_enc = quote(username or "", safe="")
    pass_enc = quote(password or "", safe="")

    host = parsed.hostname or ""
    if parsed.port:
        host = f"{host}:{parsed.port}"

    if user_enc and pass_enc:
        netloc = f"{user_enc}:{pass_enc}@{host}"
    elif user_enc:
        netloc = f"{user_enc}@{host}"
    else:
        netloc = host

    return urlunparse((
        parsed.scheme, netloc, parsed.path,
        parsed.params, parsed.query, parsed.fragment,
    ))

def check_source_connection(uri):
    try:
        parsed_uri = urlparse(uri)
        if parsed_uri.scheme not in ['rtsp', 'rtsps']:
            return False

        host = parsed_uri.hostname
        port = parsed_uri.port if parsed_uri.port else 554

        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex((host, port))
        sock.close()

        return result == 0

    except Exception as e:
        log(f"Error checking source {uri}: {e}", "ERROR")
        return False

# ============= SNAPSHOT WORKER THREAD =============
def snapshot_worker():
    global ws, ws_lock, shutdown_flag

    log("Snapshot worker started")

    while not shutdown_flag.is_set():
        try:
            item = snapshot_queue.get(timeout=1)
            if item is None:
                break

            rgba_frame, draw_specs, snapshot_meta, detections, stream_id, device_name = item

            # Heavy work moved off the GStreamer probe thread:
            # RGBA->BGR conversion, overlay drawing, JPEG encode all happen here.
            try:
                bgr_frame = cv2.cvtColor(rgba_frame, cv2.COLOR_RGBA2BGR)
            except Exception as e:
                log(f"cvtColor failed - Camera {stream_id}: {e}", "ERROR")
                continue

            for tl, br, label in draw_specs:
                cv2.rectangle(bgr_frame, tl, br, (0, 0, 255), 3)
                cv2.putText(bgr_frame, label, (tl[0], max(0, tl[1] - 10)),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)

            img_bytes = encode_jpeg(bgr_frame, quality=85)

            if img_bytes is None:
                log(f"Skipping frame - JPEG encoding failed for Camera {stream_id}", "ERROR")
                continue

            files = {'image': ('violation.jpg', img_bytes, 'image/jpeg')}
            post_data = {'metadata': json.dumps(snapshot_meta)}

            try:
                response = http_session.post(
                    f"{RELAY_URL}/api/event-snapshot",
                    files=files,
                    data=post_data,
                    timeout=10
                )
                if response.ok:
                    log(f"Snapshot sent - Camera {stream_id} ({device_name})")
                else:
                    log(f"Snapshot failed: {response.status_code}", "ERROR")
            except Exception as e:
                log(f"HTTP error: {e}", "ERROR")

            payload = {
                "type": "ppe_violation",
                "detections": detections,
                "uuid": snapshot_meta['uuid'],
                "timestamp": snapshot_meta['timestamp'],
                "streamId": stream_id,
                "cameraName": device_name
            }
            json_data = json.dumps(payload)

            with ws_lock:
                if ws is None or not getattr(ws, 'connected', False):
                    try:
                        ws = websocket.create_connection(WS_URL, timeout=5)
                        log("WebSocket reconnected")
                    except Exception as e:
                        log(f"WebSocket connection failed: {e}", "ERROR")
                        ws = None

                if ws is not None:
                    try:
                        ws.send(json_data)
                        log(f"Alert sent for Camera {stream_id}")
                    except Exception as e:
                        log(f"WebSocket send failed: {e}", "ERROR")
                        ws = None

        except queue.Empty:
            continue
        except Exception as e:
            log(f"Snapshot worker error: {e}", "ERROR")

    log("Snapshot worker stopped")

# ============= SOURCE MANAGEMENT =============
def on_source_setup(nvurisrcbin, obj):
    factory_name = obj.get_factory().get_name() if obj.get_factory() else "unknown"
    if factory_name == "rtspsrc":
        obj.set_property("protocols", 4)
        obj.set_property("do-rtsp-keep-alive", True)
        obj.set_property("timeout", SOURCE_CONNECTION_TIMEOUT)
        obj.set_property("retry", True)
        obj.set_property("latency", 300)
        obj.set_property("drop-on-latency", True)
        obj.set_property("buffer-mode", 4)

def on_pad_added(element, pad, data):
    sinkpad = data
    if not pad.is_linked():
        if pad.query_caps(None) and pad.query_caps(None).to_string().startswith("video/"):
            pad.link(sinkpad)


class SourceManager:
    """
    Owns per-source state and reconnection logic for all RTSP sources.

    Methods that mutate pipeline topology MUST be called from the GLib main
    thread. Internal timer/idle callbacks already satisfy this; external
    callers must not invoke mutating methods from arbitrary threads.
    """

    def __init__(self, pipeline, streammux, loop):
        self.pipeline       = pipeline
        self.streammux      = streammux
        self.loop           = loop
        self.state          = {}     # sid → state dict
        self._pipeline_warm = False  # True once first frame clears nvinfer+nvtracker

    # ── Public API ────────────────────────────────────────────────────────────

    def register_source(self, sid, device_id, rtsp_uri):
        """Initialise per-source state. Does NOT add anything to the pipeline."""
        self.state[sid] = {
            'device_id'          : device_id,
            'rtsp_uri'           : rtsp_uri,
            'source_bin'         : None,
            'online'             : False,
            'last_frame_mono'    : time.monotonic(),
            'reconnect_count'    : 0,
            'last_reconnect_mono': 0.0,
            'reconnect_pending'  : False,
        }
        log(f"[src {sid}] Registered: {device_id}  uri={rtsp_uri}")

    def add_source_to_pipeline(self, sid):
        """Create + link source-bin → streammux. Returns True on success."""
        src_bin = self._create_source_bin(sid)
        if src_bin is None:
            log(f"[src {sid}] add_source_to_pipeline: creation failed", "ERROR")
            return False

        s = self.state[sid]
        s['source_bin']      = src_bin
        s['online']          = True       # optimistic; watchdog will correct
        s['last_frame_mono'] = time.monotonic()
        return True

    def mark_offline(self, sid):
        """
        Mark a source offline and schedule the first reconnect.
        Safe to call multiple times — early-return debounces duplicate
        bus errors and watchdog firings. Must be called from the GLib thread.
        """
        s = self.state.get(sid)
        if s is None:
            return
        if not s['online']:
            return  # already offline — debounce

        s['online'] = False
        s['last_reconnect_mono'] = time.monotonic()
        log(f"[src {sid}] {s['device_id']} — marked OFFLINE; scheduling reconnect", "WARN")
        self._schedule_reconnect(sid, self._next_backoff(sid))

    def on_frame_received(self, sid):
        """
        Watchdog timestamp update + offline→online transition.
        Runs on the GStreamer streaming thread. The state transition is
        deferred to the GLib thread via idle_add to avoid racing
        mark_offline / watchdog.
        """
        s = self.state.get(sid)
        if s is None:
            return
        s['last_frame_mono'] = time.monotonic()
        if not self._pipeline_warm:
            self._pipeline_warm = True
            GLib.idle_add(self._on_pipeline_warm)
        if not s['online']:
            GLib.idle_add(self._mark_online, sid)

    def _on_pipeline_warm(self):
        log("Pipeline warm-up complete (TensorRT engines ready) — watchdog now active")
        return False

    def _mark_online(self, sid):
        s = self.state.get(sid)
        if s is not None and not s['online']:
            log(f"[src {sid}] {s['device_id']} — first frame received: ONLINE", "SUCCESS")
            s['online']          = True
            s['reconnect_count'] = 0
        return False

    def watchdog_tick(self):
        """
        Per WATCHDOG_INTERVAL_SEC: declare any online source offline if it
        hasn't produced a frame for WATCHDOG_THRESHOLD_SEC.

        During TensorRT engine build no frames reach the probe regardless of
        camera state, so we refresh all timestamps until pipeline_warm flips.
        """
        if shutdown_flag.is_set() or not self.loop.is_running():
            return False

        now = time.monotonic()

        if not self._pipeline_warm:
            for s in self.state.values():
                s['last_frame_mono'] = now
            return True

        for sid, s in self.state.items():
            if not s['online']:
                continue
            elapsed = now - s['last_frame_mono']
            if elapsed > WATCHDOG_THRESHOLD_SEC:
                log(f"[src {sid}] {s['device_id']} — watchdog: no frame for {elapsed:.1f}s", "WARN")
                self.mark_offline(sid)
        return True

    def periodic_offline_scan(self):
        """
        Per OFFLINE_SCAN_INTERVAL_SEC: safety net for sources that stay
        offline long enough for bus errors to stop firing.
        """
        if shutdown_flag.is_set() or not self.loop.is_running():
            return False

        now = time.monotonic()
        for sid, s in self.state.items():
            if s['online'] or s['reconnect_pending']:
                continue
            if (now - s['last_reconnect_mono']) >= self._next_backoff(sid):
                log(f"[src {sid}] {s['device_id']} — periodic scan: scheduling reconnect")
                self._schedule_reconnect(sid, 0)
        return True

    # ── Single-flight reconnect scheduler ─────────────────────────────────────

    def _schedule_reconnect(self, sid, delay_sec):
        """
        Queue _attempt_reconnect after delay_sec. The reconnect_pending flag
        guarantees at most one pending reconnect per source so that
        mark_offline and periodic_offline_scan cannot race into concurrent
        _do_reconnect cycles on the same bin.
        """
        s = self.state.get(sid)
        if s is None or s['reconnect_pending']:
            return
        s['reconnect_pending'] = True
        if delay_sec <= 0:
            GLib.idle_add(self._attempt_reconnect, sid)
        else:
            GLib.timeout_add_seconds(delay_sec, self._attempt_reconnect, sid)

    def _next_backoff(self, sid):
        return RECONNECT_INTERVAL_SEC

    # ── Reconnect flow ────────────────────────────────────────────────────────

    def _attempt_reconnect(self, sid):
        """TCP probe → schedule _do_reconnect (or retry if probe fails)."""
        s = self.state.get(sid)
        if s is None:
            return False
        s['reconnect_pending'] = False

        if s['online'] or shutdown_flag.is_set() or not self.loop.is_running():
            return False

        log(f"[src {sid}] {s['device_id']} — reconnect attempt #{s['reconnect_count']+1}; "
            f"TCP probe: {s['rtsp_uri']}")
        s['last_reconnect_mono'] = time.monotonic()

        if not check_source_connection(s['rtsp_uri']):
            s['reconnect_count'] += 1
            backoff = self._next_backoff(sid)
            log(f"[src {sid}] {s['device_id']} — still unreachable; retry in {backoff}s")
            self._schedule_reconnect(sid, backoff)
            return False

        # Re-set flag so periodic_offline_scan can't schedule a parallel
        # reconnect while _do_reconnect is in flight.
        s['reconnect_pending'] = True
        GLib.idle_add(self._do_reconnect, sid)
        return False

    def _do_reconnect(self, sid):
        """
        Full teardown + recreate cycle for one source:
          1. Tear down old bin (NULL → flush → unlink → release pad → remove)
          2. Create fresh source-bin
          3. Set PLAYING + sync_state_with_parent
          4. Reschedule on any failure
        """
        s = self.state.get(sid)
        if s is None:
            return False
        s['reconnect_pending'] = False

        if shutdown_flag.is_set() or not self.loop.is_running():
            return False

        log(f"[src {sid}] {s['device_id']} — starting reconnect cycle")

        if s['source_bin'] is not None:
            self._remove_source_bin(sid)
            s['source_bin'] = None

        new_bin = self._create_source_bin(sid)
        if new_bin is None:
            log(f"[src {sid}] {s['device_id']} — failed to create source bin; retry", "ERROR")
            s['reconnect_count'] += 1
            self._schedule_reconnect(sid, self._next_backoff(sid))
            return False

        s['source_bin'] = new_bin
        s['reconnect_count'] += 1   # reset to 0 once first frame arrives

        ret = new_bin.set_state(Gst.State.PLAYING)
        if ret == Gst.StateChangeReturn.FAILURE:
            log(f"[src {sid}] {s['device_id']} — set_state(PLAYING) failed; retry", "ERROR")
            self._remove_source_bin(sid)
            s['source_bin'] = None
            self._schedule_reconnect(sid, self._next_backoff(sid))
            return False

        new_bin.sync_state_with_parent()

        # Reset watchdog grace period — give the source time to negotiate
        # before the post-reconnect watchdog tick.
        s['last_frame_mono'] = time.monotonic()

        log(f"[src {sid}] {s['device_id']} — reconnect cycle complete; waiting for first frame", "SUCCESS")
        return False

    # ── Safe teardown ─────────────────────────────────────────────────────────

    def _remove_source_bin(self, sid):
        """
        Tear down source bin from the pipeline.

        GStreamer invariant sequence (do not reorder):
          A. src_bin → NULL + wait     (prevents buffer use-after-free)
          B. flush + unlink ghost→mux  (drain buffers in flight)
          C. release_request_pad on mux  (CRITICAL — prevents sink_N_1 leak
                                          on next reconnect)
          D. pipeline.remove() the bin
        """
        s       = self.state[sid]
        src_bin = s['source_bin']
        if src_bin is None:
            return

        src_bin.set_state(Gst.State.NULL)
        state_ret, _, _ = src_bin.get_state(timeout=Gst.SECOND * 3)
        if state_ret == Gst.StateChangeReturn.FAILURE:
            log(f"[src {sid}] {s['device_id']} — could not reach NULL; forcing removal", "WARN")

        src_ghostpad = src_bin.get_static_pad("src")
        if src_ghostpad and src_ghostpad.is_linked():
            mux_sinkpad = src_ghostpad.get_peer()
            if mux_sinkpad:
                src_ghostpad.send_event(Gst.Event.new_flush_start())
                mux_sinkpad.send_event(Gst.Event.new_flush_start())
                src_ghostpad.send_event(Gst.Event.new_flush_stop(False))
                mux_sinkpad.send_event(Gst.Event.new_flush_stop(False))
                src_ghostpad.unlink(mux_sinkpad)

                # Without release_request_pad, re-requesting sink_{sid}
                # later creates sink_{sid}_1 and leaks the original slot.
                if mux_sinkpad.get_name().startswith("sink_"):
                    self.streammux.release_request_pad(mux_sinkpad)
                    log(f"[src {sid}] released streammux sink_{sid}")

        self.pipeline.remove(src_bin)
        log(f"[src {sid}] {s['device_id']} — source bin removed cleanly")

    # ── Source bin construction ───────────────────────────────────────────────

    def _create_source_bin(self, sid):
        """
        Build source bin (uridecodebin → nvvideoconvert → capsfilter), link
        ghost pad to streammux sink_{sid}. Returns None on any failure.
        """
        s   = self.state[sid]
        uri = s['rtsp_uri']
        idx = sid

        src_bin        = Gst.Bin.new(f"source-bin-{idx}")
        uri_decode_bin = Gst.ElementFactory.make("uridecodebin", f"uri-decode-bin-{idx}")
        nvvidconv      = Gst.ElementFactory.make("nvvideoconvert", f"nvvidconv-{idx}")
        capsfilter     = Gst.ElementFactory.make("capsfilter", f"capsfilter-{idx}")

        if not all([src_bin, uri_decode_bin, nvvidconv, capsfilter]):
            log(f"[src {idx}] failed to create source bin elements", "ERROR")
            return None

        uri_decode_bin.set_property("uri", uri)
        uri_decode_bin.set_property("buffer-duration", 2000000000)
        # vGPU (A10-4Q): unified memory (type 3) unsupported here; use device
        # memory (type 2) for this GPU-only leg feeding nvstreammux.
        nvvidconv.set_property("nvbuf-memory-type", 2)
        nvmm_caps = Gst.Caps.from_string("video/x-raw(memory:NVMM)")
        capsfilter.set_property("caps", nvmm_caps)

        for elem in [uri_decode_bin, nvvidconv, capsfilter]:
            src_bin.add(elem)
        nvvidconv.link(capsfilter)

        nvvidconv_sinkpad = nvvidconv.get_static_pad("sink")
        uri_decode_bin.connect("pad-added", on_pad_added, nvvidconv_sinkpad)
        uri_decode_bin.connect("source-setup", on_source_setup)

        capsfilter_srcpad = capsfilter.get_static_pad("src")
        ghost_pad = Gst.GhostPad.new("src", capsfilter_srcpad)
        if not ghost_pad or not src_bin.add_pad(ghost_pad):
            log(f"[src {idx}] failed to add ghost pad", "ERROR")
            return None

        self.pipeline.add(src_bin)

        srcpad  = src_bin.get_static_pad("src")
        sinkpad = self.streammux.get_request_pad(f"sink_{idx}")
        if not sinkpad:
            log(f"[src {idx}] failed to request streammux sink_{idx}", "ERROR")
            self.pipeline.remove(src_bin)
            return None

        if srcpad.link(sinkpad) != Gst.PadLinkReturn.OK:
            log(f"[src {idx}] failed to link source bin → streammux", "ERROR")
            self.streammux.release_request_pad(sinkpad)
            self.pipeline.remove(src_bin)
            return None

        log(f"[src {idx}] {s['device_id']} — source bin linked → streammux sink_{idx}")
        return src_bin

# ============= ALERT EXPIRY CLEANUP =============
def cleanup_expired_alerts():
    global alerts_sent_for_person_ids

    if shutdown_flag.is_set():
        return False

    current_time = time.time()
    expired_keys = [k for k, ts in alerts_sent_for_person_ids.items()
                    if current_time - ts > ALERT_EXPIRY_SECONDS]

    for k in expired_keys:
        del alerts_sent_for_person_ids[k]
        stream_id, pid = k
        log(f"Alert expired for Camera {stream_id} Person {pid}")

    return True

# ============= PPE DETECTION LOGIC =============
def per_camera_buffer_probe(pad, info, u_data):
    global facility_id, last_send_times, device_configs, last_state_snapshot, alerts_sent_for_person_ids
    global tracked_states, snapshot_queue

    stream_id = u_data
    current_time = time.time()

    gst_buffer = info.get_buffer()
    if not gst_buffer:
        return Gst.PadProbeReturn.OK

    batch_meta = pyds.gst_buffer_get_nvds_batch_meta(hash(gst_buffer))

    for frame_meta in safe_iter_pyds_list(batch_meta.frame_meta_list, pyds.NvDsFrameMeta.cast):
        if source_mgr is not None:
            source_mgr.on_frame_received(stream_id)

        device_config = device_configs.get(stream_id, {})
        device_id = device_config.get('id', stream_id)
        device_name = device_config.get('name', f'Camera {stream_id}')
        zone_id = device_config.get('zoneId', 'N/A')

        # Single-pass scan: collect persons and their PPE detections in one walk of the
        # object metadata list. Avoids the previous O(persons * objects) re-scan per frame.
        # `saw_sgie_output` flips True the moment any SGIE child meta (positive OR negative
        # class) appears — used below to gate state updates when sgie_config interval > 0.
        # Per-PPE entries are True (positive class detected), False (explicit NO-* class
        # detected), or absent (model said nothing — treated as "unknown" downstream so
        # far/tiny persons don't accumulate false negatives).
        person_objs = {}
        ppe_by_parent = {}
        saw_sgie_output = False
        for obj_meta in safe_iter_pyds_list(frame_meta.obj_meta_list, pyds.NvDsObjectMeta.cast):
            comp_id = obj_meta.unique_component_id
            cls = obj_meta.class_id
            if comp_id == 1:
                if cls == PRIMARY_PERSON_CLASS_ID:
                    person_objs[obj_meta.object_id + 1] = obj_meta
            elif comp_id == 2:
                saw_sgie_output = True
                if cls in PPE_MAP and obj_meta.parent:
                    parent_obj = pyds.NvDsObjectMeta.cast(obj_meta.parent)
                    if parent_obj:
                        ppe_name, is_positive = PPE_MAP[cls]
                        parent_pid = parent_obj.object_id + 1
                        bucket = ppe_by_parent.get(parent_pid)
                        if bucket is None:
                            bucket = {}
                            ppe_by_parent[parent_pid] = bucket
                        # Positive wins over negative if both classes fire on the
                        # same person in the same frame (rare but possible from NMS).
                        if is_positive:
                            bucket[ppe_name] = True
                        elif ppe_name not in bucket:
                            bucket[ppe_name] = False

        stream_states = tracked_states.setdefault(stream_id, {})

        # Register newly seen persons.
        for pid in person_objs:
            if pid not in stream_states:
                stream_states[pid] = {
                    "Helmet": PPEState(),
                    "Mask": PPEState(),
                    "Vest": PPEState(),
                    "last_seen": current_time,
                    "first_seen": current_time
                }
                key = (stream_id, pid)
                last_send_times[key] = 0
                last_state_snapshot[key] = None
                log(f"New person detected - Camera {stream_id}, Person {pid}")

        # Only feed the PPE state machines on frames where SGIE actually inferenced.
        # When `interval` > 0 in sgie_config, skipped frames have no PPE child meta;
        # treating those as "no PPE detected" would falsely inflate negative_streak
        # and trigger spurious "PPE LOST" transitions.
        sgie_active = saw_sgie_output

        for pid in person_objs:
            person_state = stream_states[pid]
            person_state["last_seen"] = current_time

            if not sgie_active:
                continue

            # detected_ppe entries are True (positive class), False (explicit NO-*
            # class), or absent (no SGIE class fired above threshold for this PPE).
            # For close-enough persons, absent is trusted as a negative — many YOLO
            # PPE models have weaker recall on NO-* classes than on positives, so
            # requiring an explicit NO-* would suppress real violations on clearly
            # visible workers. For small/far persons we don't trust absence and
            # only update on explicit signals.
            detected_ppe = ppe_by_parent.get(pid) or {}
            person_obj = person_objs[pid]
            trust_absence = person_obj.rect_params.height >= MIN_TRUST_BBOX_HEIGHT

            for ppe_name in PPE_CATEGORIES:
                detection = detected_ppe.get(ppe_name)
                if detection is None:
                    if not trust_absence:
                        continue
                    detection = False

                ppe_state = person_state[ppe_name]
                state_changed, new_state = ppe_state.update_detection(
                    detection, current_time
                )

                if state_changed and new_state is not None:
                    confidence = ppe_state.get_confidence()
                    log(f"Person {pid} ({device_name}): {ppe_name} → {'HAS' if new_state else 'NO'} ({confidence:.2f})")

        # Evict stale persons.
        pids_to_remove = [pid for pid, st in stream_states.items()
                          if current_time - st["last_seen"] > 10]
        for pid in pids_to_remove:
            log(f"Person {pid} left - Camera {stream_id}")
            del stream_states[pid]
            key = (stream_id, pid)
            last_send_times.pop(key, None)
            last_state_snapshot.pop(key, None)

        # Decide which persons trigger an alert this frame.
        violations_to_send = []

        for pid in person_objs:
            key = (stream_id, pid)

            last_alert_ts = alerts_sent_for_person_ids.get(key)
            if last_alert_ts is not None and current_time - last_alert_ts < ALERT_EXPIRY_SECONDS:
                continue

            person_state = stream_states[pid]
            helmet_state = person_state["Helmet"]
            mask_state = person_state["Mask"]
            vest_state = person_state["Vest"]

            cur_tuple = (helmet_state.current_state,
                         mask_state.current_state,
                         vest_state.current_state)

            # An explicit False (not None) on any category counts as a violation.
            if not (cur_tuple[0] is False or cur_tuple[1] is False or cur_tuple[2] is False):
                continue

            time_since_last_send = current_time - last_send_times.get(key, 0)
            last_tuple = last_state_snapshot.get(key)
            state_changed = cur_tuple != last_tuple

            grace_period_passed = (
                current_time >= helmet_state.state_locked_until and
                current_time >= mask_state.state_locked_until and
                current_time >= vest_state.state_locked_until
            )

            should_send = (
                time_since_last_send >= VIOLATION_ALERT_INTERVAL or
                (state_changed and grace_period_passed and time_since_last_send >= 2)
            )

            if should_send:
                violations_to_send.append((pid, helmet_state, mask_state, vest_state, cur_tuple))
                alerts_sent_for_person_ids[key] = current_time
                log(f"Violation detected - Person {pid} ({device_name})", "WARN")

        if not violations_to_send:
            continue

        detections = []
        draw_specs = []

        for pid, helmet_state, mask_state, vest_state, cur_tuple in violations_to_send:
            key = (stream_id, pid)

            helmet = _state_to_str(cur_tuple[0])
            mask = _state_to_str(cur_tuple[1])
            vest = _state_to_str(cur_tuple[2])

            helmet_conf = helmet_state.get_confidence()
            mask_conf = mask_state.get_confidence()
            vest_conf = vest_state.get_confidence()

            violations = []
            if helmet == "no":
                violations.append("NO_HELMET")
            if mask == "no":
                violations.append("NO_MASK")
            if vest == "no":
                violations.append("NO_VEST")

            detections.append({
                "person_id": pid,
                "helmet": helmet,
                "mask": mask,
                "vest": vest,
                "helmet_confidence": round(helmet_conf, 2),
                "mask_confidence": round(mask_conf, 2),
                "vest_confidence": round(vest_conf, 2),
                "violations": violations,
                "facility_id": facility_id,
                "zone_id": zone_id,
                "device_id": device_id,
                "device_name": device_name,
                "stream_id": stream_id
            })

            last_send_times[key] = current_time
            last_state_snapshot[key] = cur_tuple

            person_obj = person_objs.get(pid)
            if person_obj is not None:
                rect = person_obj.rect_params
                tl = (int(rect.left), int(rect.top))
                br = (int(rect.left + rect.width), int(rect.top + rect.height))
                h_status = "Y" if cur_tuple[0] is True else ("N" if cur_tuple[0] is False else "?")
                m_status = "Y" if cur_tuple[1] is True else ("N" if cur_tuple[1] is False else "?")
                v_status = "Y" if cur_tuple[2] is True else ("N" if cur_tuple[2] is False else "?")
                draw_specs.append((tl, br, f"Person {pid} | H:{h_status} M:{m_status} V:{v_status}"))

        # Capture only the raw RGBA frame here; cvtColor + drawing + JPEG encode happen
        # in the snapshot worker so the streaming thread isn't blocked on CPU work.
        rgba_copy = None
        mapped = False
        try:
            surf = pyds.get_nvds_buf_surface(hash(gst_buffer), frame_meta.batch_id)
            mapped = True
            rgba_copy = np.array(surf, copy=True, order='C')
        except Exception as e:
            log(f"Frame capture error - Camera {stream_id}: {e}", "ERROR")
        finally:
            if mapped:
                try:
                    pyds.unmap_nvds_buf_surface(hash(gst_buffer), frame_meta.batch_id)
                except:
                    pass

        if rgba_copy is None:
            continue

        snapshot_meta = {
            "uuid": str(uuid.uuid4()),
            "facilityId": facility_id,
            "timestamp": int(current_time),
            "eventType": "ppe_violation",
            "deviceId": device_id,
            "cameraName": device_name,
            "streamId": stream_id,
            "detections": detections
        }

        try:
            snapshot_queue.put_nowait((rgba_copy, draw_specs, snapshot_meta, detections, stream_id, device_name))
        except queue.Full:
            log(f"Snapshot queue full - Camera {stream_id}", "WARN")

    return Gst.PadProbeReturn.OK

def bus_call(bus, message, loop):
    global pipeline, streammux, source_mgr
    msg_type = message.type
    src_name = message.src.get_name() if message.src else "Unknown"
    src_path = message.src.get_path_string() if message.src else ""

    if msg_type == Gst.MessageType.EOS:
        if "deepstream-pipeline" in src_name:
            log("EOS received")
            loop.quit()
    elif msg_type == Gst.MessageType.ERROR:
        err, debug = message.parse_error()
        log(f"{src_name}: {err}", "ERROR")

        if source_mgr is not None:
            pipeline_prefix = f"/GstPipeline:{pipeline.get_name()}/"
            for sid, s in source_mgr.state.items():
                bin_name = s['source_bin'].get_name() if s['source_bin'] else ""
                if not bin_name or bin_name not in src_path:
                    continue
                if not src_path.startswith(pipeline_prefix):
                    # Stale error from a detached source bin still cleaning up.
                    return True
                source_mgr.mark_offline(sid)
                return True

        if "nvstreammux" in src_name or "nvtracker" in src_name:
            log(f"Critical error in {src_name}", "ERROR")
            loop.quit()

    elif msg_type == Gst.MessageType.WARNING:
        if VERBOSE:
            warn, debug = message.parse_warning()
            log(f"{src_name}: {warn}", "WARN")

    return True

# ============= GRACEFUL SHUTDOWN =============
def graceful_shutdown(signum=None, frame=None):
    global pipeline, loop, ws, snapshot_queue, shutdown_flag

    print("\n⏹️  Shutting down...")
    shutdown_flag.set()

    for _ in range(SNAPSHOT_WORKERS):
        try:
            snapshot_queue.put(None, timeout=1)
        except:
            pass

    if pipeline:
        pipeline.send_event(Gst.Event.new_eos())
        bus = pipeline.get_bus()
        msg = bus.timed_pop_filtered(5 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR)

    if loop and loop.is_running():
        loop.quit()

import signal
signal.signal(signal.SIGINT, graceful_shutdown)
signal.signal(signal.SIGTERM, graceful_shutdown)

# ============= MAIN =============
def main(args):
    global ws, ws_lock, facility_id, pipeline, streammux, loop, device_configs, number_sources
    global demux_pads, snapshot_queue, source_mgr

    config_path = '/root/LINDE/facility_config.json'
    try:
        with open(config_path) as f:
            config = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        sys.stderr.write(f"ERROR: Config error: {e}\n")
        sys.exit(1)

    if 'device' not in config or 'facilityId' not in config['device']:
        sys.stderr.write("ERROR: Invalid config structure\n")
        sys.exit(1)

    facility_id = config['device']['facilityId']
    devices = config['device'].get('devices', [])

    if not devices:
        sys.stderr.write("ERROR: No devices found\n")
        sys.exit(1)

    # Build full RTSP URL from separate username/password/rtsp_link fields.
    # Special characters in credentials are percent-encoded so GStreamer's
    # URI parser receives a well-formed URL.
    for device in devices:
        device['rtsp_link'] = _build_rtsp_url(
            device.get('rtsp_link', ''),
            device.get('username'),
            device.get('password'),
        )

    number_sources = len(devices)

    print("="*50)
    print("🔒 PPE VIOLATION DETECTION SYSTEM")
    print("="*50)
    print(f"Facility: {facility_id} | Cameras: {number_sources}")
    print(f"Alert expiry: {ALERT_EXPIRY_SECONDS}s")
    print("="*50)

    for i, device in enumerate(devices):
        device_configs[i] = device
        print(f"📹 Camera {i}: {device.get('name')}")

    pgie_config_path = "/root/LINDE/pgie_config.txt"
    sgie_config_path = "/root/LINDE/sgie_config.txt"

    Gst.init(None)

    pipeline = Gst.Pipeline.new("deepstream-pipeline")
    loop = GLib.MainLoop()

    bus = pipeline.get_bus()
    bus.add_signal_watch()
    bus.connect("message", bus_call, loop)

    snapshot_threads = []
    for _ in range(SNAPSHOT_WORKERS):
        t = threading.Thread(target=snapshot_worker, daemon=False)
        t.start()
        snapshot_threads.append(t)

    streammux = Gst.ElementFactory.make("nvstreammux", "Stream-muxer")
    streammux.set_property("width", MUXER_OUTPUT_WIDTH)
    streammux.set_property("height", MUXER_OUTPUT_HEIGHT)
    streammux.set_property("batch-size", number_sources)
    streammux.set_property("batched-push-timeout", 40000)
    streammux.set_property("live-source", 1)
    # vGPU (A10-4Q): unified memory (type 3) unsupported; muxer output only
    # feeds nvinfer/nvtracker (GPU), so device memory (type 2) is correct.
    streammux.set_property("nvbuf-memory-type", 2)
    streammux.set_property("gpu-id", 0)
    streammux.set_property("sync-inputs", 0)
    streammux.set_property("drop-pipeline-eos", True)
    pipeline.add(streammux)

    source_mgr = SourceManager(pipeline, streammux, loop)

    print("\n🔌 Initializing cameras...")
    for i, device in enumerate(devices):
        uri = device.get('rtsp_link')
        device_id = device.get('id', i)
        source_mgr.register_source(i, device_id, uri)

        if check_source_connection(uri):
            if source_mgr.add_source_to_pipeline(i):
                log(f"Camera {i} connected", "SUCCESS")
            else:
                log(f"Camera {i} pipeline add failed; will retry", "ERROR")
                source_mgr.state[i]['online'] = False
                source_mgr._schedule_reconnect(i, source_mgr._next_backoff(i))
        else:
            log(f"Camera {i} offline", "WARN")
            source_mgr.state[i]['online'] = False
            source_mgr._schedule_reconnect(i, source_mgr._next_backoff(i))

    pgie = Gst.ElementFactory.make("nvinfer", "primary-inference")
    tracker = Gst.ElementFactory.make("nvtracker", "tracker")
    sgie = Gst.ElementFactory.make("nvinfer", "secondary-inference")
    demux = Gst.ElementFactory.make("nvstreamdemux", "demux")

    if not all([pgie, tracker, sgie, demux]):
        sys.stderr.write("ERROR: Failed to create elements\n")
        sys.exit(1)

    pgie.set_property("config-file-path", pgie_config_path)
    pgie.set_property("batch-size", number_sources)

    tracker.set_property("ll-config-file", "/root/LINDE/tracker_config.yml")
    tracker.set_property("ll-lib-file", "/opt/nvidia/deepstream/deepstream/lib/libnvds_nvmultiobjecttracker.so")
    tracker.set_property("tracker-width", 640)
    tracker.set_property("tracker-height", 640)
    tracker.set_property("gpu-id", 0)
    tracker.set_property("display-tracking-id", True)

    sgie.set_property("config-file-path", sgie_config_path)

    pipeline.add(pgie)
    pipeline.add(tracker)
    pipeline.add(sgie)
    pipeline.add(demux)

    streammux.link(pgie)
    pgie.link(tracker)
    tracker.link(sgie)
    sgie.link(demux)

    for idx in range(number_sources):
        queue = Gst.ElementFactory.make("queue", f"queue-{idx}")
        nvvidconv_cam = Gst.ElementFactory.make("nvvideoconvert", f"converter-{idx}")
        capsfilter_cam = Gst.ElementFactory.make("capsfilter", f"capsrgba-{idx}")
        fakesink = Gst.ElementFactory.make("fakesink", f"fakesink-{idx}")

        if not all([queue, nvvidconv_cam, capsfilter_cam, fakesink]):
            sys.stderr.write(f"ERROR: Failed to create elements for camera {idx}\n")
            sys.exit(1)

        rgba_caps = Gst.Caps.from_string("video/x-raw(memory:NVMM), format=RGBA")
        capsfilter_cam.set_property("caps", rgba_caps)
        # vGPU (A10-4Q): unified memory (type 3) unsupported; use pinned host
        # memory (type 1) so pyds.get_nvds_buf_surface can CPU-map the RGBA
        # frame at the probe point (this is the only CPU-accessed leg).
        nvvidconv_cam.set_property("nvbuf-memory-type", 1)
        # Drop wall-clock sync and avoid pinning the last buffer in the analysis-only leg.
        fakesink.set_property("sync", False)
        fakesink.set_property("async", False)
        fakesink.set_property("enable-last-sample", False)

        pipeline.add(queue)
        pipeline.add(nvvidconv_cam)
        pipeline.add(capsfilter_cam)
        pipeline.add(fakesink)

        demux_src_pad = demux.get_request_pad(f"src_{idx}")
        demux_pads.append(demux_src_pad)
        queue_sink_pad = queue.get_static_pad("sink")
        if demux_src_pad.link(queue_sink_pad) != Gst.PadLinkReturn.OK:
            sys.stderr.write(f"ERROR: Failed to link demux to queue for camera {idx}\n")
            sys.exit(1)

        queue.link(nvvidconv_cam)
        nvvidconv_cam.link(capsfilter_cam)
        capsfilter_cam.link(fakesink)

        sink_pad = fakesink.get_static_pad("sink")
        sink_pad.add_probe(Gst.PadProbeType.BUFFER, per_camera_buffer_probe, idx)

    try:
        ws = websocket.create_connection(WS_URL, timeout=5)
        log("WebSocket connected", "SUCCESS")
    except Exception as e:
        log(f"WebSocket failed: {e}", "WARN")
        ws = None

    print(f"\n🚀 System running... (Ctrl+C to stop)\n")

    GLib.timeout_add_seconds(WATCHDOG_INTERVAL_SEC, source_mgr.watchdog_tick)
    GLib.timeout_add_seconds(OFFLINE_SCAN_INTERVAL_SEC, source_mgr.periodic_offline_scan)
    GLib.timeout_add_seconds(60, cleanup_expired_alerts)

    pipeline.set_state(Gst.State.PLAYING)

    try:
        loop.run()
    except KeyboardInterrupt:
        graceful_shutdown()
    finally:
        log("Cleaning up...")

        if source_mgr is not None:
            for sid, s in source_mgr.state.items():
                if s['source_bin']:
                    s['source_bin'].set_state(Gst.State.NULL)

        if pipeline:
            pipeline.set_state(Gst.State.READY)
            time.sleep(0.5)
            pipeline.set_state(Gst.State.NULL)

        for pad in demux_pads:
            if pad and demux:
                try:
                    demux.release_request_pad(pad)
                except:
                    pass

        with ws_lock:
            if ws:
                try:
                    ws.close()
                except:
                    pass

        for t in snapshot_threads:
            t.join(timeout=5)

        log("Shutdown complete", "SUCCESS")

if __name__ == '__main__':
    sys.exit(main(sys.argv))
