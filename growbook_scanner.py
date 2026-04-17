#!/usr/bin/env python3
"""
GrowBook Scanner -- companion server for automatic photo import.

Run this script once, then open GrowBook in Chrome and click the
sparkle button (sparkle). Keep this window open while using GrowBook.

Usage:  python growbook_scanner.py

Endpoints:
  GET  /status   -- health check
  GET  /scan     -- scan folder, return photos grouped by slot (date only, no AI)
  GET  /photo    -- serve a photo file by path
  POST /screen   -- pass 1: quick has_baby check for a list of paths
  POST /analyze  -- pass 2: full tags (mood/activity/milestone/caption) for baby photos
"""
import os, re, json, struct, base64, io
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime
from urllib.parse import urlparse, parse_qs
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

# -- Load .env if present -------------------------------------------------------
_env_path = os.path.join(os.path.dirname(__file__), '.env')
if os.path.isfile(_env_path):
    with open(_env_path) as _f:
        for _line in _f:
            _line = _line.strip()
            if _line and not _line.startswith('#') and '=' in _line:
                _k, _, _v = _line.partition('=')
                os.environ.setdefault(_k.strip(), _v.strip())

# -- AI analysis setup ----------------------------------------------------------
try:
    import anthropic as _anthropic
    _ai_client = _anthropic.Anthropic(api_key=os.environ.get('ANTHROPIC_API_KEY', ''))
    AI_AVAILABLE = bool(os.environ.get('ANTHROPIC_API_KEY'))
except ImportError:
    _ai_client = None
    AI_AVAILABLE = False

# -- Configuration --------------------------------------------------------------
SCAN_FOLDER = r"C:\Users\elazar\Dropbox\Camera Uploads"
BIRTH_DATE  = datetime(2026, 3, 28)
PORT        = 7272
IMAGE_EXTS  = {'.jpg', '.jpeg', '.png', '.heic', '.heif', '.webp', '.bmp'}

# -- Date extraction ------------------------------------------------------------

def parse_date_from_filename(name):
    # Dropbox pattern: "2026-04-13 12.34.56.jpg"
    m = re.search(r'(\d{4})-(\d{2})-(\d{2})', name)
    if m:
        try:
            return datetime(int(m[1]), int(m[2]), int(m[3]))
        except ValueError:
            pass
    # Compact pattern: IMG_20260413, 20260413_123456
    m = re.search(r'(\d{4})(\d{2})(\d{2})', name)
    if m:
        try:
            y, mo, d = int(m[1]), int(m[2]), int(m[3])
            if y > 2000 and 1 <= mo <= 12 and 1 <= d <= 31:
                return datetime(y, mo, d)
        except ValueError:
            pass
    return None

def parse_exif_date(path):
    """Extract DateTimeOriginal from JPEG EXIF header without any dependencies."""
    try:
        with open(path, 'rb') as f:
            data = f.read(65536)
        if data[:2] != b'\xff\xd8':
            return None
        i = 2
        while i < len(data) - 3:
            if data[i] != 0xff:
                break
            marker = data[i + 1]
            if i + 3 >= len(data):
                break
            seg_len = struct.unpack('>H', data[i + 2:i + 4])[0]
            if marker == 0xe1:  # APP1 = EXIF
                seg = data[i + 4:i + 2 + seg_len]
                if seg[:4] == b'Exif':
                    exif = seg[6:]
                    # DateTimeOriginal tag 0x9003 in little-endian EXIF
                    for tag in [b'\x03\x90', b'\x90\x03']:
                        idx = 0
                        while True:
                            idx = exif.find(tag, idx)
                            if idx == -1:
                                break
                            try:
                                offset = struct.unpack('<I', exif[idx + 8:idx + 12])[0]
                                s = exif[offset:offset + 19].decode('ascii', errors='ignore')
                                if len(s) >= 19 and ':' in s:
                                    return datetime.strptime(s, '%Y:%m:%d %H:%M:%S')
                            except Exception:
                                pass
                            idx += 2
                break
            i += 2 + seg_len
    except Exception:
        pass
    return None

def get_photo_date(path):
    name = os.path.basename(path)
    dt = parse_date_from_filename(name)
    if dt:
        return dt
    dt = parse_exif_date(path)
    if dt:
        return dt
    try:
        return datetime.fromtimestamp(os.path.getmtime(path))
    except Exception:
        return None

# -- Slot mapping ---------------------------------------------------------------

def date_to_slot_key(dt):
    days = (dt - BIRTH_DATE).days
    if days < 0:
        return None          # before birth
    if days < 84:            # weeks 0-11
        return f"w-{min(days // 7, 11)}"
    months = int(days / 30.44)
    if months <= 24:
        return f"m-{months}"
    years = days // 365
    return f"y-{years}"

# -- Folder scan ----------------------------------------------------------------

def scan_folder():
    groups = {}
    error = None

    if not os.path.isdir(SCAN_FOLDER):
        return groups, f"Folder not found: {SCAN_FOLDER}"

    count = 0
    for root, dirs, files in os.walk(SCAN_FOLDER):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for fname in files:
            if os.path.splitext(fname)[1].lower() not in IMAGE_EXTS:
                continue
            path = os.path.join(root, fname)
            dt = get_photo_date(path)
            if not dt:
                continue
            key = date_to_slot_key(dt)
            if not key:
                continue
            groups.setdefault(key, []).append({
                'filename': fname,
                'path': path,
                'date': dt.isoformat(),
            })
            count += 1

    # Sort each group chronologically, then tag burst groups
    for key in groups:
        groups[key].sort(key=lambda x: x['date'])
        _tag_bursts(groups[key])

    total = sum(len(v) for v in groups.values())
    print(f"  Scan complete: {total} photos across {len(groups)} slots")
    return groups, error

def _tag_bursts(photos, gap_seconds=10):
    """
    Tag photos that were taken in rapid succession (within gap_seconds of each
    other) with a shared burst_id. The first photo in a burst gets
    burst_representative=True; the rest get burst_representative=False.
    Photos with burst_id=None are standalone shots.
    """
    if len(photos) <= 1:
        return
    burst_counter = [0]

    def new_burst_id():
        burst_counter[0] += 1
        return f'burst_{burst_counter[0]}'

    current_burst = None
    current_burst_start = None

    for i, photo in enumerate(photos):
        try:
            curr_dt = datetime.fromisoformat(photo['date'])
        except Exception:
            photo['burst_id'] = None
            photo['burst_representative'] = True
            current_burst = None
            continue

        if i == 0:
            photo['burst_id'] = None
            photo['burst_representative'] = True
            current_burst_start = curr_dt
            current_burst = None
            continue

        prev_dt = current_burst_start
        delta = (curr_dt - prev_dt).total_seconds()

        if delta <= gap_seconds:
            # Part of a burst
            if current_burst is None:
                # Start a new burst — retroactively tag the previous photo
                current_burst = new_burst_id()
                photos[i - 1]['burst_id'] = current_burst
                photos[i - 1]['burst_representative'] = True
            photo['burst_id'] = current_burst
            photo['burst_representative'] = False
        else:
            # Gap — standalone photo
            photo['burst_id'] = None
            photo['burst_representative'] = True
            current_burst = None
            current_burst_start = curr_dt

# -- AI photo analysis ---------------------------------------------------------

_SUPPORTED_MEDIA = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
}

_MAX_PX    = 1568            # Claude recommended max dimension
_MAX_BYTES = 4 * 1024 * 1024  # 4 MB safety margin (API limit is 5 MB)

def _prepare_image(path):
    """Return (jpeg_bytes, 'image/jpeg') resized to fit Claude's limits."""
    try:
        with Image.open(path) as img:
            img = img.convert('RGB')
            w, h = img.size
            if max(w, h) > _MAX_PX:
                scale = _MAX_PX / max(w, h)
                img = img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
            for quality in (85, 70, 55, 40):
                buf = io.BytesIO()
                img.save(buf, format='JPEG', quality=quality)
                data = buf.getvalue()
                if len(data) <= _MAX_BYTES:
                    return data, 'image/jpeg'
    except Exception:
        pass
    return None, None


_SCREEN_PROMPT = (
    'Does this photo contain a baby, infant, or toddler (under age 3)? '
    'Reply with ONLY valid JSON: {"has_baby": true} or {"has_baby": false}'
)

_TAG_PROMPT = """This photo contains a baby. Return ONLY valid JSON with no extra text:
{
  "people": [],
  "mood": "",
  "activity": "",
  "is_milestone": false,
  "caption": ""
}
Rules:
- "people": array of any that apply: "baby_solo", "with_mom", "with_dad", "with_siblings", "with_grandparents", "family_group"
- "mood": exactly one of: "happy", "calm", "sleeping", "crying", "silly", "surprised"
- "activity": exactly one of: "bath", "feeding", "play", "outdoors", "tummy_time", "reading", "travel", "milestone", "other"
- "is_milestone": true only for clear developmental firsts (first smile, crawl, steps, words, etc.)
- "caption": one warm, concise English sentence under 60 characters"""

def _call_claude(b64, media_type, prompt, max_tokens):
    """Single Claude Vision call. Returns parsed JSON dict or None."""
    try:
        response = _ai_client.messages.create(
            model='claude-haiku-4-5-20251001',
            max_tokens=max_tokens,
            messages=[{
                'role': 'user',
                'content': [
                    {'type': 'image',
                     'source': {'type': 'base64', 'media_type': media_type, 'data': b64}},
                    {'type': 'text', 'text': prompt},
                ]
            }]
        )
        text = response.content[0].text.strip()
        start, end = text.find('{'), text.rfind('}') + 1
        if start != -1 and end > start:
            return json.loads(text[start:end])
    except Exception:
        pass
    return None

def _prepare_b64(path):
    """Returns (b64, media_type) or (None, None) if unsupported/failed."""
    ext = os.path.splitext(path)[1].lower()
    if ext not in _SUPPORTED_MEDIA and ext not in ('.heic', '.heif'):
        return None, None
    data, media_type = _prepare_image(path)
    if data is None:
        return None, None
    return base64.standard_b64encode(data).decode(), media_type

def screen_photo(path):
    """Pass 1: quick has_baby check. Returns (path, True/False) or (path, None) on error."""
    b64, media_type = _prepare_b64(path)
    if b64 is None:
        return path, None
    result = _call_claude(b64, media_type, _SCREEN_PROMPT, max_tokens=20)
    has_baby = result.get('has_baby', False) if result else False
    return path, has_baby

def tag_photo(path):
    """Pass 2: full tagging for confirmed baby photos. Returns tag dict or None."""
    b64, media_type = _prepare_b64(path)
    if b64 is None:
        return path, None
    result = _call_claude(b64, media_type, _TAG_PROMPT, max_tokens=250)
    return path, result

def screen_photos_only(valid_paths):
    """
    Pass 1 only: quick has_baby screen (8 parallel workers).
    Returns dict: path -> True/False
    """
    total = len(valid_paths)
    print(f'  Screening {total} photos for baby...')
    results = {}
    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = {executor.submit(screen_photo, p): p for p in valid_paths}
        for future in futures:
            path, has_baby = future.result()
            if has_baby is not None:
                results[path] = has_baby
    baby_count = sum(1 for v in results.values() if v)
    print(f'  Screen done: {baby_count}/{total} are baby photos')
    return results

def tag_photos_only(valid_paths):
    """
    Pass 2 only: full tagging for photos already confirmed to contain a baby (4 workers).
    Returns dict: path -> {people, mood, activity, is_milestone, caption}
    """
    total = len(valid_paths)
    print(f'  Full-tagging {total} baby photos...')
    tags = {}
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(tag_photo, p): p for p in valid_paths}
        for future in futures:
            path, result = future.result()
            if result:
                tags[path] = result
                print(f'  ok {os.path.basename(path)}: {result.get("activity","?")} / {result.get("mood","?")}')
            else:
                print(f'  warn Tagging failed for {os.path.basename(path)}')
    return tags

# -- HTTP server ----------------------------------------------------------------

def _validate_paths(paths):
    """Return only paths that exist and are within SCAN_FOLDER."""
    scan_abs = os.path.abspath(SCAN_FOLDER)
    return [
        p for p in paths
        if os.path.isfile(p) and os.path.abspath(p).startswith(scan_abs)
    ]

def _read_post_body(handler):
    length = int(handler.headers.get('Content-Length', 0))
    return handler.rfile.read(length)

def _json_response(handler, data):
    body = json.dumps(data).encode()
    handler.send_response(200)
    handler._cors()
    handler.send_header('Content-Type', 'application/json')
    handler.end_headers()
    handler.wfile.write(body)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress per-request logs

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors()
        self.end_headers()

    def do_POST(self):
        parsed = urlparse(self.path)

        if parsed.path not in ('/screen', '/analyze'):
            self.send_response(404)
            self.end_headers()
            return

        try:
            data = json.loads(_read_post_body(self))
            paths = data.get('paths', [])
        except Exception:
            self.send_response(400)
            self.end_headers()
            return

        if not AI_AVAILABLE:
            _json_response(self, {
                'error': 'ANTHROPIC_API_KEY not set. Run: set ANTHROPIC_API_KEY=sk-...'
            })
            return

        valid_paths = _validate_paths(paths)

        if parsed.path == '/screen':
            # Pass 1: quick has_baby classification
            results = screen_photos_only(valid_paths)
            _json_response(self, {'results': results})

        elif parsed.path == '/analyze':
            # Pass 2: full tagging (caller already knows these are baby photos)
            tags = tag_photos_only(valid_paths)
            _json_response(self, {'tags': tags})

    def do_GET(self):
        parsed = urlparse(self.path)
        qs = parse_qs(parsed.query)

        if parsed.path == '/status':
            _json_response(self, {'ok': True, 'folder': SCAN_FOLDER})

        elif parsed.path == '/scan':
            print(f"  Scanning {SCAN_FOLDER}...")
            groups, err = scan_folder()
            _json_response(self, {'groups': groups, 'error': err})

        elif parsed.path == '/photo':
            path = qs.get('path', [''])[0]
            abs_path = os.path.abspath(path) if path else ''
            scan_abs = os.path.abspath(SCAN_FOLDER)
            if not path or not os.path.isfile(abs_path) or not abs_path.startswith(scan_abs):
                self.send_response(404)
                self.end_headers()
                return
            with open(abs_path, 'rb') as fh:
                data = fh.read()
            ext = os.path.splitext(abs_path)[1].lower()
            ctype = ('image/jpeg' if ext in ('.jpg', '.jpeg')
                     else 'image/png' if ext == '.png'
                     else 'image/webp')
            self.send_response(200)
            self._cors()
            self.send_header('Content-Type', ctype)
            self.end_headers()
            self.wfile.write(data)

        else:
            self.send_response(404)
            self.end_headers()


if __name__ == '__main__':
    ai_status = 'AI ON (Claude Vision)' if AI_AVAILABLE else 'AI OFF (set ANTHROPIC_API_KEY)'
    print()
    print('  +-------------------------------------------------+')
    print('  |           GrowBook Scanner                      |')
    print('  +-------------------------------------------------+')
    print(f'  |  Folder : {SCAN_FOLDER[:37]:<37} |')
    print(f'  |  Port   : {PORT:<37} |')
    print(f'  |  AI     : {ai_status:<37} |')
    print('  +-------------------------------------------------+')
    print('  |  /screen = fast has_baby check (import step)    |')
    print('  |  /analyze = full tags (week editor, on demand)  |')
    print('  +-------------------------------------------------+')
    print()
    try:
        server = HTTPServer(('localhost', PORT), Handler)
        server.serve_forever()
    except KeyboardInterrupt:
        print('\n  Scanner stopped.')
