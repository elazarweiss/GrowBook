#!/usr/bin/env python3
"""
GrowBook Scanner — companion server for automatic photo import.

Run this script once, then open GrowBook in Chrome and click the
sparkle button (✨). Keep this window open while using GrowBook.

Usage:  python growbook_scanner.py
"""
import os, re, json, struct, base64, io
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime
from urllib.parse import urlparse, parse_qs
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

# ── Load .env if present ───────────────────────────────────────────────────────
_env_path = os.path.join(os.path.dirname(__file__), '.env')
if os.path.isfile(_env_path):
    with open(_env_path) as _f:
        for _line in _f:
            _line = _line.strip()
            if _line and not _line.startswith('#') and '=' in _line:
                _k, _, _v = _line.partition('=')
                os.environ.setdefault(_k.strip(), _v.strip())

# ── AI analysis setup ──────────────────────────────────────────────────────────
try:
    import anthropic as _anthropic
    _ai_client = _anthropic.Anthropic(api_key=os.environ.get('ANTHROPIC_API_KEY', ''))
    AI_AVAILABLE = bool(os.environ.get('ANTHROPIC_API_KEY'))
except ImportError:
    _ai_client = None
    AI_AVAILABLE = False

# ── Configuration ──────────────────────────────────────────────────────────────
SCAN_FOLDER = r"C:\Users\elazar\Dropbox\Camera Uploads"
BIRTH_DATE  = datetime(2026, 3, 28)
PORT        = 7272
IMAGE_EXTS  = {'.jpg', '.jpeg', '.png', '.heic', '.heif', '.webp', '.bmp'}

# ── Date extraction ────────────────────────────────────────────────────────────

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

# ── Slot mapping ───────────────────────────────────────────────────────────────

def date_to_slot_key(dt):
    days = (dt - BIRTH_DATE).days
    if days < 0:
        return None          # before birth
    if days < 84:            # weeks 0–11
        return f"w-{min(days // 7, 11)}"
    months = int(days / 30.44)
    if months <= 24:
        return f"m-{months}"
    years = days // 365
    return f"y-{years}"

# ── Folder scan ────────────────────────────────────────────────────────────────

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

    # Sort each group chronologically
    for v in groups.values():
        v.sort(key=lambda x: x['date'])

    print(f"  Scan complete: {count} photos across {len(groups)} slots")
    return groups, error

# ── AI photo analysis ─────────────────────────────────────────────────────────

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


_SCREEN_PROMPT = 'Does this photo contain a baby, infant, or toddler? Reply with ONLY: {"has_baby": true} or {"has_baby": false}'

_TAG_PROMPT = """This photo contains a baby. Return ONLY valid JSON:
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

def analyze_photos_two_pass(valid_paths):
    """
    Two-pass analysis:
    1. Quick has_baby screen for all photos (8 workers, tiny response)
    2. Full tagging only for baby photos (4 workers)
    Returns dict: path → {has_baby, people, mood, activity, is_milestone, caption}
    """
    tags = {}
    total = len(valid_paths)

    # Pass 1: screen all photos
    print(f'  Pass 1: screening {total} photos for baby…')
    baby_paths = []
    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = {executor.submit(screen_photo, p): p for p in valid_paths}
        for future in futures:
            path, has_baby = future.result()
            if has_baby is None:
                continue  # unsupported format
            tags[path] = {'has_baby': has_baby}
            if has_baby:
                baby_paths.append(path)

    print(f'  Pass 1 done: {len(baby_paths)}/{total} are baby photos')

    if not baby_paths:
        return tags

    # Pass 2: full tag only baby photos
    print(f'  Pass 2: tagging {len(baby_paths)} baby photos…')
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(tag_photo, p): p for p in baby_paths}
        for future in futures:
            path, result = future.result()
            if result:
                tags[path].update(result)
                print(f'  ✓ {os.path.basename(path)}: {result.get("activity","?")} / {result.get("mood","?")}')
            else:
                print(f'  ⚠ Tagging failed for {os.path.basename(path)}')

    return tags

# ── HTTP server ────────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress per-request logs

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors()
        self.end_headers()

    def do_POST(self):
        parsed = urlparse(self.path)

        if parsed.path == '/analyze':
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length)
            try:
                data = json.loads(body)
                paths = data.get('paths', [])
            except Exception:
                self.send_response(400)
                self.end_headers()
                return

            if not AI_AVAILABLE:
                body = json.dumps({
                    'tags': {},
                    'error': 'ANTHROPIC_API_KEY not set. Run: set ANTHROPIC_API_KEY=sk-...'
                }).encode()
                self.send_response(200)
                self._cors()
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(body)
                return

            # Validate paths are within scan folder
            scan_abs = os.path.abspath(SCAN_FOLDER)
            valid_paths = [
                p for p in paths
                if os.path.isfile(p) and os.path.abspath(p).startswith(scan_abs)
            ]

            tags = analyze_photos_two_pass(valid_paths)

            response_body = json.dumps({'tags': tags}).encode()
            self.send_response(200)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(response_body)

        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        qs = parse_qs(parsed.query)

        if parsed.path == '/status':
            body = json.dumps({'ok': True, 'folder': SCAN_FOLDER}).encode()
            self.send_response(200)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(body)

        elif parsed.path == '/scan':
            print(f"  Scanning {SCAN_FOLDER} …")
            groups, err = scan_folder()
            body = json.dumps({'groups': groups, 'error': err}).encode()
            self.send_response(200)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(body)

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
    ai_status = '✓ AI tagging ON  (Claude Vision)' if AI_AVAILABLE else '✗ AI tagging OFF (set ANTHROPIC_API_KEY)'
    print()
    print('  ┌─────────────────────────────────────────────┐')
    print('  │          GrowBook Scanner                   │')
    print('  ├─────────────────────────────────────────────┤')
    print(f'  │  Folder : {SCAN_FOLDER[:35]:<35} │')
    print(f'  │  Port   : {PORT:<35} │')
    print(f'  │  AI     : {ai_status:<35} │')
    print('  ├─────────────────────────────────────────────┤')
    print('  │  Keep this window open, then click ✨       │')
    print('  │  in GrowBook to scan and import photos.     │')
    print('  │  Press Ctrl+C to stop.                      │')
    print('  └─────────────────────────────────────────────┘')
    print()
    try:
        server = HTTPServer(('localhost', PORT), Handler)
        server.serve_forever()
    except KeyboardInterrupt:
        print('\n  Scanner stopped.')
