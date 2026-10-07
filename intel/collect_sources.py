"""Deterministic source collector for the Midas intel job (no LLM, no API keys).

Prints a Markdown report of what is NEW since the last run from:
  1. Apple App Store (iTunes lookup/search API): tracked app versions, rating jumps, new apps
  2. Hacker News (Algolia API): stories and Launch HN posts on the topic
  3. Y Combinator companies (yc-oss public dataset): new or pivoted companies in the space
  4. Reddit (public search RSS): posts on the topic, plus new comments on followed threads
     (intel/state/followed_threads.json; the daily Claude pass may add threads there)

State per source lives in intel/state/<source>.json (local, gitignored). A failed source prints a
"SOURCE FAILED" line instead of stopping the whole run.
"""

import html
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ElementTree
from pathlib import Path

# State is local per machine (gitignored), next to this script.
STATE_DIR = Path(__file__).resolve().parent / "state"
USER_AGENT = "Mozilla/5.0 (Macintosh) midas-intel/0.2 personal research"
COUNTRY = "us"

# ---------- App Store ----------

TRACKED_APPS = {
    6747768928: "Wabi (closest competitor)",
    6797077582: "CriAI (private on-iPhone mini apps, solo dev, public launch Oct 2026)",
    6755592800: "MiniApps Store (Zoomerang)",
    6791572856: "Conjure (closest feature set: named sharing, offline)",
    6767986271: "Kiln",
    6744576554: "Blanks (Polsia)",
    6581479509: "aSim (YC S21)",
    6758931714: "Whip",
    6749073777: "Aippy (Apple precedent)",
    6747975557: "Miniceo (Apple precedent)",
    6747017725: "Even Realities (Even Hub: third-party web-code plug-in store, 4.7 precedent)",
    6747363193: "Mentra (MentraOS miniapp store, moving to on-phone JS runtime, 4.7 precedent)",
    6756137814: "Build Minis",
    1620539343: "Easyapp.ai - Mini Apps",
    6504506653: "Sekai (create/remix/play)",
    6747010458: "Make AI Mini Apps for ChatGPT",
    6757471107: "Lovable",
    6757432427: "Base44",
    1614022293: "Replit",
    1264713923: "Taskade",
    6448311069: "ChatGPT",
    6473753684: "Claude",
    6477489729: "Google Gemini",
}

# Apps Apple removed under 2.5.2 (or that left the US store). Alert if any RETURNS:
# a return means Apple accepted something, which matters for the Midas compliance note.
REMOVED_APPS_TO_WATCH = {
    6740775687: "Bloom (rejected under 2.5.2 / DPLA 3.3.1(B), went Android-first)",
    6748029391: "Emergent iOS app",
    6751247034: "Anything (removed under 2.5.2)",
    6746410361: "Rork",
}

APP_STORE_KEYWORDS = [
    "mini apps",
    "mini app maker",
    "ai app builder",
    "build apps with ai",
    "personal app builder",
    "personal software",
    "vibe coding",
    "ai messenger mini apps",
]

# A rating-count jump at least this large (relative) is worth flagging.
RATING_JUMP_RATIO = 0.25

# ---------- Hacker News ----------

# Exact phrases, matched against story titles only (advancedSyntax + title restriction).
HN_QUERIES = [
    '"personal software"',
    '"software for one"',
    '"small software"',
    '"malleable software"',
    '"home-cooked"',
    '"mini apps"',
    '"mini app"',
    '"personal apps"',
    '"app builder"',
    '"vibe coded"',
    '"Wabi"',
    '"Base44"',
    '"Lovable"',
    '"MCP Apps"',
    '"for myself"',
    '"Alphio"',
]
# Launch HN posts are how YC companies announce; match these against topic words.
LAUNCH_HN_TOPIC_WORDS = ["app", "builder", "personal", "no-code", "agent", "mini", "software", "mobile", "iphone", "ios"]
HN_DEFAULT_LOOKBACK_SECONDS = 3 * 24 * 3600

# ---------- YC companies ----------

YC_DATASET_URL = "https://yc-oss.github.io/api/companies/all.json"
YC_TOPIC_KEYWORDS = [
    "personal software",
    "mini app",
    "small software",
    "app builder",
    "personal app",
    "build apps",
    "build and share",
    "vibe cod",
    "malleable",
    "lovable for",
    "apps in seconds",
    "no-code app",
]

# ---------- Reddit ----------

# Few OR-combined queries: Reddit rate-limits unauthenticated feeds hard.
REDDIT_QUERIES = [
    # The phenomenon and named players.
    '"personal software" OR "software for one" OR "mini apps" OR "Wabi app" '
    'OR "Base44" OR "app for myself" OR "personal app" OR "small software"',
    # Demand chatter (added 2026-10-07): "built it for myself first" posts and the upkeep pain
    # of throwaway personal tools (state, retries, duplicate alerts, notifications).
    # Kept to exact, low-noise phrases: "keep it running" / "personal alert" matched lawnmower and
    # Wi-Fi posts in the 2026-10-07 test. Upkeep chatter on known threads comes via followed threads.
    '"built it for myself" OR "built this for myself" OR "for myself first" OR "Alphio"',
]
REDDIT_RATE_LIMIT_WAIT_SECONDS = 30
# Pause between feed requests (searches and followed threads) to stay under the rate limit.
REDDIT_REQUEST_GAP_SECONDS = 8
FOLLOWED_THREADS_FILE = STATE_DIR / "followed_threads.json"
ATOM_NAMESPACE = {"atom": "http://www.w3.org/2005/Atom"}


def http_get(url):
    """GET a URL with our user agent, retrying once on transient failure."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt_number in range(2):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.read()
        except Exception:
            if attempt_number == 1:
                raise
            time.sleep(3)


def load_state(source_name, default_state):
    state_path = STATE_DIR / f"{source_name}.json"
    if state_path.exists():
        return json.loads(state_path.read_text())
    return default_state


def save_state(source_name, state):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    (STATE_DIR / f"{source_name}.json").write_text(json.dumps(state, indent=2, sort_keys=True))


def run_source(title, collect_function):
    """Print one source's section; never let one failure stop the others."""
    print(f"\n## {title}")
    try:
        report_lines = collect_function()
        print("\n".join(report_lines) if report_lines else "- Nothing new.")
    except Exception as error:
        print(f"- SOURCE FAILED: {type(error).__name__}: {error}")


# ---------- App Store collector ----------

def collect_app_store():
    state = load_state("appstore", {"apps": {}, "seen_search_ids": []})
    is_first_run = not state["apps"]

    joined_ids = ",".join(str(app_id) for app_id in TRACKED_APPS)
    lookup_url = f"https://itunes.apple.com/lookup?id={joined_ids}&country={COUNTRY}"
    lookup_results = json.loads(http_get(lookup_url)).get("results", [])
    current_listings = {listing["trackId"]: listing for listing in lookup_results}

    report_lines = []
    for app_id, label in TRACKED_APPS.items():
        listing = current_listings.get(app_id)
        previous = state["apps"].get(str(app_id))
        if listing is None:
            report_lines.append(f"- {label}: NOT FOUND in lookup (removed or region change?)")
            continue
        if previous is None:
            continue
        if previous.get("version") != listing.get("version"):
            release_notes = (listing.get("releaseNotes") or "").strip().replace("\n", " ")
            report_lines.append(
                f"- {label}: version {previous.get('version')} -> {listing.get('version')} "
                f"({listing.get('currentVersionReleaseDate', '')[:10]}). "
                f"Release notes: {release_notes[:600] or '(none)'}"
            )
        previous_ratings = previous.get("ratings") or 0
        current_ratings = listing.get("userRatingCount") or 0
        rating_delta = current_ratings - previous_ratings
        # Ratio test only means something once an app has a few ratings.
        if previous_ratings and rating_delta >= 5 and rating_delta / previous_ratings >= RATING_JUMP_RATIO:
            report_lines.append(f"- {label}: ratings {previous_ratings} -> {current_ratings} (+{rating_delta})")

    # 2.5.2 sentinel: removed apps reappearing in the US store.
    removed_ids = ",".join(str(app_id) for app_id in REMOVED_APPS_TO_WATCH)
    removed_lookup_url = f"https://itunes.apple.com/lookup?id={removed_ids}&country={COUNTRY}"
    for listing in json.loads(http_get(removed_lookup_url)).get("results", []):
        label = REMOVED_APPS_TO_WATCH.get(listing["trackId"], listing.get("trackName"))
        report_lines.append(
            f"- ⚠ 2.5.2 SENTINEL: {label} is BACK on the US App Store as \"{listing.get('trackName')}\" "
            f"v{listing.get('version')} ({listing.get('currentVersionReleaseDate', '')[:10]})"
        )

    seen_search_ids = set(state["seen_search_ids"])
    newly_seen_ids = set()
    for keyword in APP_STORE_KEYWORDS:
        search_url = (
            f"https://itunes.apple.com/search?term={urllib.parse.quote(keyword)}"
            f"&entity=software&country={COUNTRY}&limit=25"
        )
        for result in json.loads(http_get(search_url)).get("results", []):
            result_id = result["trackId"]
            if result_id in TRACKED_APPS or result_id in seen_search_ids or result_id in newly_seen_ids:
                continue
            newly_seen_ids.add(result_id)
            if not is_first_run:
                report_lines.append(
                    f"- NEW app for '{keyword}': {result.get('trackName')} by {result.get('sellerName')} "
                    f"(v{result.get('version')}, first released {result.get('releaseDate', '')[:10]}, "
                    f"ratings {result.get('userRatingCount')}) https://apps.apple.com/us/app/id{result_id}"
                )
        time.sleep(1)

    if is_first_run:
        report_lines.append(f"- First run: baseline recorded for {len(current_listings)} tracked apps and {len(newly_seen_ids)} search results.")

    state["apps"] = {
        str(app_id): {
            "name": listing.get("trackName"),
            "version": listing.get("version"),
            "released": listing.get("currentVersionReleaseDate"),
            "ratings": listing.get("userRatingCount"),
        }
        for app_id, listing in current_listings.items()
    }
    state["seen_search_ids"] = sorted(seen_search_ids | newly_seen_ids)
    save_state("appstore", state)
    return report_lines


# ---------- Hacker News collector ----------

def format_hn_hit(hit):
    hn_link = f"https://news.ycombinator.com/item?id={hit['objectID']}"
    external_url = hit.get("url") or hn_link
    return (
        f"- [{hit.get('title')}]({external_url}) — {hit.get('points') or 0} pts, "
        f"{hit.get('num_comments') or 0} comments, {hit.get('created_at', '')[:10]} — HN: {hn_link}"
    )


def collect_hacker_news():
    state = load_state("hn", {"last_run_epoch": 0, "seen_ids": []})
    now_epoch = int(time.time())
    since_epoch = state["last_run_epoch"] or now_epoch - HN_DEFAULT_LOOKBACK_SECONDS
    seen_ids = set(state["seen_ids"])
    report_lines = []

    def search_hn(query):
        search_url = (
            "https://hn.algolia.com/api/v1/search_by_date?"
            f"query={urllib.parse.quote(query)}&tags=story&hitsPerPage=30"
            f"&advancedSyntax=true&restrictSearchableAttributes=title"
            f"&numericFilters=created_at_i>{since_epoch}"
        )
        return json.loads(http_get(search_url)).get("hits", [])

    for query in HN_QUERIES:
        for hit in search_hn(query):
            if hit["objectID"] in seen_ids:
                continue
            seen_ids.add(hit["objectID"])
            report_lines.append(f"{format_hn_hit(hit)} (matched '{query}')")

    # Launch HN = YC company launches; keep only topic-relevant ones.
    for hit in search_hn("Launch HN"):
        title_lower = (hit.get("title") or "").lower()
        if hit["objectID"] in seen_ids or not title_lower.startswith("launch hn"):
            continue
        if any(topic_word in title_lower for topic_word in LAUNCH_HN_TOPIC_WORDS):
            seen_ids.add(hit["objectID"])
            report_lines.append(f"{format_hn_hit(hit)} (YC Launch HN)")

    state["last_run_epoch"] = now_epoch
    # Keep the seen list bounded.
    state["seen_ids"] = sorted(seen_ids)[-5000:]
    save_state("hn", state)
    return report_lines


# ---------- YC companies collector ----------

def company_text(company):
    text_parts = [
        company.get("one_liner") or "",
        company.get("long_description") or "",
        " ".join(company.get("tags") or []),
    ]
    return " ".join(text_parts).lower()


def matches_topic(company):
    return any(keyword in company_text(company) for keyword in YC_TOPIC_KEYWORDS)


def collect_yc_companies():
    state = load_state("yc", {"one_liners": {}})
    is_first_run = not state["one_liners"]
    all_companies = json.loads(http_get(YC_DATASET_URL))
    previous_one_liners = state["one_liners"]
    report_lines = []

    for company in all_companies:
        company_id = str(company["id"])
        one_liner = company.get("one_liner") or ""
        if is_first_run or not matches_topic(company):
            continue
        company_line = (
            f"{company.get('name')} ({company.get('batch')}, {company.get('status')}) — {one_liner} "
            f"— {company.get('website') or ''} — https://www.ycombinator.com/companies/{company.get('slug')}"
        )
        if company_id not in previous_one_liners:
            report_lines.append(f"- NEW YC company in the space: {company_line}")
        elif previous_one_liners[company_id] != one_liner:
            # One-liner changed and now matches the topic: likely a pivot into the space.
            report_lines.append(
                f"- PIVOT/REPOSITION: {company_line} (was: \"{previous_one_liners[company_id]}\")"
            )

    if is_first_run:
        matching_companies = [company for company in all_companies if matches_topic(company)]
        report_lines.append(
            f"- First run: baseline recorded for {len(all_companies)} YC companies; "
            f"{len(matching_companies)} currently match the topic. Most recent matches:"
        )
        recent_matches = sorted(matching_companies, key=lambda company: company.get("launched_at") or 0, reverse=True)
        for company in recent_matches[:15]:
            report_lines.append(
                f"  - {company.get('name')} ({company.get('batch')}) — {company.get('one_liner')} "
                f"— https://www.ycombinator.com/companies/{company.get('slug')}"
            )

    state["one_liners"] = {str(company["id"]): company.get("one_liner") or "" for company in all_companies}
    save_state("yc", state)
    return report_lines


# ---------- Reddit collector ----------

def fetch_reddit_feed(rss_url):
    # On HTTP 429, wait and retry a few times before giving up.
    for attempt_number in range(3):
        try:
            return http_get(rss_url)
        except urllib.error.HTTPError as http_error:
            if http_error.code != 429 or attempt_number == 2:
                raise
            time.sleep(REDDIT_RATE_LIMIT_WAIT_SECONDS)
    return None


def entry_plain_text(entry):
    entry_html = entry.findtext("atom:content", default="", namespaces=ATOM_NAMESPACE)
    without_tags = re.sub(r"<[^>]+>", " ", html.unescape(entry_html))
    return re.sub(r"\s+", " ", without_tags).strip()


def collect_reddit():
    state = load_state("reddit", {"seen_ids": []})
    seen_ids = set(state["seen_ids"])
    report_lines = []
    for query_index, query in enumerate(REDDIT_QUERIES):
        if query_index > 0:
            time.sleep(REDDIT_REQUEST_GAP_SECONDS)
        rss_url = f"https://www.reddit.com/search.rss?q={urllib.parse.quote(query)}&sort=new&t=week&limit=50"
        feed_bytes = fetch_reddit_feed(rss_url)
        report_lines.extend(parse_search_feed(feed_bytes, seen_ids))
    report_lines.extend(collect_followed_threads(seen_ids))
    state["seen_ids"] = sorted(seen_ids)[-5000:]
    save_state("reddit", state)
    return report_lines


def parse_search_feed(feed_bytes, seen_ids):
    """Search results not seen before, with post text. Updates seen_ids."""
    report_lines = []
    feed_root = ElementTree.fromstring(feed_bytes)
    for entry in feed_root.findall("atom:entry", ATOM_NAMESPACE):
        entry_id = entry.findtext("atom:id", default="", namespaces=ATOM_NAMESPACE)
        if not entry_id or entry_id in seen_ids:
            continue
        seen_ids.add(entry_id)
        entry_title = entry.findtext("atom:title", default="", namespaces=ATOM_NAMESPACE)
        link_element = entry.find("atom:link", ATOM_NAMESPACE)
        entry_link = link_element.get("href") if link_element is not None else ""
        category_element = entry.find("atom:category", ATOM_NAMESPACE)
        # Entries without a subreddit category are community listings, not posts.
        if category_element is None:
            continue
        subreddit = category_element.get("label")
        updated = entry.findtext("atom:updated", default="", namespaces=ATOM_NAMESPACE)[:10]
        # Include the post body: the Claude pass cannot fetch reddit.com pages itself.
        post_text = entry_plain_text(entry)
        report_lines.append(f"- {subreddit}: [{entry_title}]({entry_link}) — {updated}\n  > {post_text[:700]}")
    return report_lines


def load_followed_threads(today_text):
    """Followed threads still inside their follow window: [{"url", "note", "until"}]."""
    if not FOLLOWED_THREADS_FILE.exists():
        return []
    followed_threads = json.loads(FOLLOWED_THREADS_FILE.read_text())
    active_threads = []
    for thread in followed_threads:
        if thread.get("until", "9999-12-31") >= today_text:
            active_threads.append(thread)
    return active_threads


def parse_thread_comments(feed_bytes, seen_ids, thread_note):
    """New comments on one thread (the first feed entry is the post itself). Updates seen_ids."""
    report_lines = []
    feed_root = ElementTree.fromstring(feed_bytes)
    thread_entries = feed_root.findall("atom:entry", ATOM_NAMESPACE)
    for entry in thread_entries[1:]:
        entry_id = entry.findtext("atom:id", default="", namespaces=ATOM_NAMESPACE)
        if not entry_id or entry_id in seen_ids:
            continue
        seen_ids.add(entry_id)
        author_name = entry.findtext("atom:author/atom:name", default="?", namespaces=ATOM_NAMESPACE)
        if author_name.endswith("AutoModerator"):
            continue
        link_element = entry.find("atom:link", ATOM_NAMESPACE)
        comment_link = link_element.get("href") if link_element is not None else ""
        updated = entry.findtext("atom:updated", default="", namespaces=ATOM_NAMESPACE)[:10]
        report_lines.append(
            f"- followed thread ({thread_note}): comment by {author_name} — {updated} {comment_link}\n"
            f"  > {entry_plain_text(entry)[:500]}"
        )
    return report_lines


def collect_followed_threads(seen_ids):
    report_lines = []
    for thread in load_followed_threads(time.strftime("%Y-%m-%d")):
        time.sleep(REDDIT_REQUEST_GAP_SECONDS)
        thread_rss_url = thread["url"].rstrip("/") + "/.rss?limit=50"
        try:
            feed_bytes = fetch_reddit_feed(thread_rss_url)
            report_lines.extend(parse_thread_comments(feed_bytes, seen_ids, thread.get("note", "")))
        except Exception as error:
            report_lines.append(f"- followed thread FAILED ({thread.get('note', '')}): {error}")
    return report_lines


def main():
    print("# Source collector output (deterministic, no LLM)")
    print(f"Generated {time.strftime('%Y-%m-%d %H:%M %Z')}. Only items new since the last run are listed.")
    run_source("App Store", collect_app_store)
    run_source("Hacker News (stories + YC Launch HN)", collect_hacker_news)
    run_source("Y Combinator companies (new / pivoted into the space)", collect_yc_companies)
    run_source("Reddit (public search RSS)", collect_reddit)


if __name__ == "__main__":
    main()
