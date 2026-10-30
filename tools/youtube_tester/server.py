"""Freeify YouTube tester: an MCP server that sends Freeify's exact YouTube requests from
this PC, so a playback block can be diagnosed without building the app.

The request values mirror Freeify/YouTubeSearch.swift. When the app's client settings,
visitor source, or search filter change there, change them here too (see SYNC below).
Nothing here signs in or keeps cookies, matching the app. Run by Claude Code over stdio.
"""

import datetime
import re

import requests
from mcp.server.mcpserver import MCPServer

# --- SYNC with Freeify/YouTubeSearch.swift -------------------------------------------
VISIONOS_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 "
               "(KHTML, like Gecko) Version/26.0 Safari/605.1.15")
VISIONOS_CLIENT = {"clientName": "VISIONOS", "clientVersion": "1.02", "deviceMake": "Apple",
                   "deviceModel": "RealityDevice17,1", "osName": "visionOS",
                   "osVersion": "26.5.23O471", "hl": "en", "userAgent": VISIONOS_UA}
VISIONOS_HEADER_ID = "101"
WATCH_PAGE_UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                 "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36")
SONGS_FILTER = "EgWKAQIIAWoMEA4QChADEAQQCRAF"
# ---------------------------------------------------------------------------------------

TIMEOUT = 20
server = MCPServer(
    name="freeify-youtube-tester",
    instructions=(
        "Diagnose Freeify's YouTube playback from the user's PC. check_playback sends the "
        "app's exact visionOS player request. Results come from the PC's network, not the "
        "phone's: a pass here and a failure on the phone points at the phone's network or "
        "session. Keep calls few and spaced; bursts are what got Freeify bot-checked."
    ),
)


def _music_client_version() -> str:
    # Like the app (and ytmusicapi): today's UTC date.
    return "1." + datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d") + ".01.00"


def _music_request(endpoint: str, body: dict) -> dict:
    body = {**body, "context": {"client": {"clientName": "WEB_REMIX",
                                           "clientVersion": _music_client_version(),
                                           "hl": "en", "gl": "US"}}}
    r = requests.post(f"https://music.youtube.com/youtubei/v1/{endpoint}?prettyPrint=false",
                      json=body, timeout=TIMEOUT,
                      headers={"Content-Type": "application/json",
                               "Origin": "https://music.youtube.com"})
    r.raise_for_status()
    return r.json()


def _watch_page_visitor(video_id: str) -> str:
    r = requests.get(f"https://www.youtube.com/watch?v={video_id}&bpctr=9999999999&has_verified=1",
                     timeout=TIMEOUT,
                     headers={"User-Agent": WATCH_PAGE_UA,
                              "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"})
    if r.status_code != 200:
        return ""
    m = re.search(r'"(?:VISITOR_DATA|visitorData)"\s*:\s*"([^"]+)"', r.text)
    return m.group(1) if m else ""


def _visitor(source: str, video_id: str) -> str:
    if source == "watch":
        return _watch_page_visitor(video_id)
    if source == "music":
        data = _music_request("browse", {"browseId": "FEmusic_home"})
        return data.get("responseContext", {}).get("visitorData", "")
    if source == "none":
        return ""
    raise ValueError("source must be 'watch', 'music', or 'none'")


def _runs_text(column: dict) -> str:
    runs = (column.get("musicResponsiveListItemFlexColumnRenderer", {})
            .get("text", {}).get("runs", []))
    return "".join(run.get("text", "") for run in runs)


@server.tool()
def search_songs(query: str, limit: int = 10) -> list[dict]:
    """Search YouTube Music's Songs tab like Freeify does. Returns video IDs to test."""
    data = _music_request("search", {"query": query, "params": SONGS_FILTER})
    songs = []

    def walk(node):
        if isinstance(node, dict):
            item = node.get("musicResponsiveListItemRenderer")
            if item:
                video_id = item.get("playlistItemData", {}).get("videoId")
                columns = item.get("flexColumns", [])
                if video_id and columns:
                    songs.append({"video_id": video_id,
                                  "title": _runs_text(columns[0]),
                                  "details": _runs_text(columns[1]) if len(columns) > 1 else ""})
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(data)
    return songs[:max(1, min(limit, 20))]


@server.tool()
def visitor_id(source: str = "watch", video_id: str = "dQw4w9WgXcQ") -> dict:
    """Get an anonymous visitor ID the way Freeify does. source: 'watch' (playback, from a
    youtube.com watch page) or 'music' (search and Discover, and playback's fallback)."""
    value = _visitor(source, video_id)
    return {"source": source, "found": bool(value), "length": len(value), "starts_with": value[:16]}


@server.tool()
def check_playback(video_id: str, visitor_source: str = "watch", probe_media: bool = True) -> dict:
    """Send Freeify's exact visionOS player request for one song and report YouTube's answer:
    playability status and reason, the direct AAC formats Freeify would choose from, and
    (probe_media) whether the chosen audio URL serves its first byte.
    visitor_source: 'watch' (what the app uses), 'music' (the app's fallback), or 'none'."""
    visitor = _visitor(visitor_source, video_id)
    body = {"contentCheckOk": True, "racyCheckOk": True,
            "context": {"client": {**VISIONOS_CLIENT, "visitorData": visitor}},
            "playbackContext": {"contentPlaybackContext": {"html5Preference": "HTML5_PREF_WANTS"}},
            "videoId": video_id}
    headers = {"Content-Type": "application/json", "User-Agent": VISIONOS_UA,
               "Origin": "https://www.youtube.com", "X-Youtube-Client-Name": VISIONOS_HEADER_ID,
               "X-Youtube-Client-Version": VISIONOS_CLIENT["clientVersion"]}
    if visitor:
        headers["X-Goog-Visitor-Id"] = visitor
    r = requests.post("https://www.youtube.com/youtubei/v1/player?prettyPrint=false",
                      json=body, headers=headers, timeout=TIMEOUT)
    data = r.json()
    status = data.get("playabilityStatus", {})
    # Freeify picks the highest-bitrate audio/mp4 format with a direct URL and no DRC.
    formats = [f for f in data.get("streamingData", {}).get("adaptiveFormats", [])
               if f.get("mimeType", "").startswith("audio/mp4") and "url" in f and not f.get("isDrc")]
    formats.sort(key=lambda f: f.get("averageBitrate", 0), reverse=True)
    result = {
        "video_id": video_id,
        "http_status": r.status_code,
        "visitor_source": visitor_source,
        "visitor_length": len(visitor),
        "playability": status.get("status"),
        "reason": status.get("reason"),
        "title": data.get("videoDetails", {}).get("title"),
        "playable_aac_formats": [{"itag": f.get("itag"), "bitrate": f.get("averageBitrate"),
                                  "bytes": f.get("contentLength"), "loudness_db": f.get("loudnessDb")}
                                 for f in formats],
        "verdict": "Freeify would play this" if formats else "Freeify would fail on this",
    }
    if probe_media and formats:
        media = requests.get(formats[0]["url"], timeout=TIMEOUT, stream=True,
                             headers={"User-Agent": VISIONOS_UA, "Range": "bytes=0-0"})
        result["media_probe_http"] = media.status_code
        media.close()
        if media.status_code not in (200, 206):
            result["verdict"] = "player OK, but the audio URL refused access"
    return result


@server.tool()
def ytdlp_compare(video_id: str, client: str = "visionos") -> dict:
    """Ask the installed yt-dlp for the same song with one player client (e.g. visionos,
    tv_samsung, mweb, web_music), as a reference for what currently works."""
    import yt_dlp

    options = {"quiet": True, "no_warnings": True, "skip_download": True,
               "format": "bestaudio[ext=m4a]/bestaudio",
               "extractor_args": {"youtube": {"player_client": [client]}}}
    try:
        with yt_dlp.YoutubeDL(options) as ydl:
            info = ydl.extract_info(f"https://music.youtube.com/watch?v={video_id}", download=False)
        return {"client": client, "yt_dlp": yt_dlp.version.__version__, "ok": True,
                "format": info.get("format"), "title": info.get("title")}
    except Exception as error:  # yt-dlp reports YouTube's refusal as an exception
        return {"client": client, "yt_dlp": yt_dlp.version.__version__, "ok": False,
                "error": str(error)[:500]}


@server.tool()
def network_info() -> dict:
    """This PC's public IPv4 and IPv6 addresses (via ipify), to compare with the phone's
    (open https://api64.ipify.org in Safari with Private Relay off)."""
    out = {}
    for name, url in (("ipv4", "https://api.ipify.org"), ("ipv6", "https://api6.ipify.org")):
        try:
            out[name] = requests.get(url, timeout=8).text.strip()
        except requests.RequestException:
            out[name] = None
    return out


if __name__ == "__main__":
    server.run()
