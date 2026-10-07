"""Tests for the Reddit parts of the intel collector. Run: python3 -m unittest discover intel/tests"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import collect_sources  # noqa: E402

SEARCH_FEED = b"""<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry><id>t3_post1</id><title>I built it for myself first</title>
    <link href="https://www.reddit.com/r/sideprojects/comments/post1/"/>
    <category term="sideprojects" label="r/sideprojects"/>
    <updated>2026-10-07T10:00:00+00:00</updated>
    <content type="html">&lt;p&gt;Made a tracker   for me&lt;/p&gt;</content></entry>
  <entry><id>t5_community</id><title>A community listing</title>
    <link href="https://www.reddit.com/r/something/"/><updated>2026-10-07T10:00:00+00:00</updated></entry>
</feed>"""

THREAD_FEED = b"""<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry><id>t3_thread</id><title>the post itself</title><author><name>/u/op</name></author>
    <link href="https://www.reddit.com/r/quantfinance/comments/thread/"/><updated>2026-10-07T09:00:00+00:00</updated>
    <content type="html">post body</content></entry>
  <entry><id>t1_c1</id><title>reply</title><author><name>/u/Funny_Box146</name></author>
    <link href="https://www.reddit.com/r/quantfinance/comments/thread/c1/"/><updated>2026-10-07T11:00:00+00:00</updated>
    <content type="html">&lt;p&gt;the state problem is the whole thing&lt;/p&gt;</content></entry>
  <entry><id>t1_c2</id><title>bot</title><author><name>/u/AutoModerator</name></author>
    <link href="https://www.reddit.com/r/quantfinance/comments/thread/c2/"/><updated>2026-10-07T11:00:00+00:00</updated>
    <content type="html">I am a bot</content></entry>
</feed>"""


class SearchFeedTests(unittest.TestCase):
    def test_new_posts_reported_once_and_listings_skipped(self):
        seen_ids = set()
        first_lines = collect_sources.parse_search_feed(SEARCH_FEED, seen_ids)
        self.assertEqual(len(first_lines), 1)
        self.assertIn("r/sideprojects", first_lines[0])
        self.assertIn("Made a tracker for me", first_lines[0])
        second_lines = collect_sources.parse_search_feed(SEARCH_FEED, seen_ids)
        self.assertEqual(second_lines, [])

    def test_demand_query_covers_new_chatter_terms(self):
        all_queries = " ".join(collect_sources.REDDIT_QUERIES)
        for phrase in ['"built it for myself"', '"for myself first"', '"Alphio"']:
            self.assertIn(phrase, all_queries)
        self.assertIn('"for myself"', collect_sources.HN_QUERIES)
        # Phrases that matched unrelated posts in the live test must stay out.
        self.assertNotIn('"keep it running"', all_queries)
        self.assertNotIn('"personal alert"', all_queries)


class FollowedThreadTests(unittest.TestCase):
    def test_new_comments_only_skipping_post_and_automoderator(self):
        seen_ids = set()
        lines = collect_sources.parse_thread_comments(THREAD_FEED, seen_ids, "quant alerts")
        self.assertEqual(len(lines), 1)
        self.assertIn("Funny_Box146", lines[0])
        self.assertIn("the state problem is the whole thing", lines[0])
        self.assertIn("quant alerts", lines[0])
        self.assertEqual(collect_sources.parse_thread_comments(THREAD_FEED, seen_ids, "quant alerts"), [])

    def test_expired_threads_are_not_followed(self):
        original_file = collect_sources.FOLLOWED_THREADS_FILE
        with tempfile.TemporaryDirectory() as temporary_directory:
            threads_file = Path(temporary_directory) / "followed_threads.json"
            threads_file.write_text(json.dumps([
                {"url": "https://reddit.com/a", "note": "live", "until": "2026-10-21"},
                {"url": "https://reddit.com/b", "note": "expired", "until": "2026-10-01"},
            ]))
            collect_sources.FOLLOWED_THREADS_FILE = threads_file
            try:
                active_threads = collect_sources.load_followed_threads("2026-10-07")
            finally:
                collect_sources.FOLLOWED_THREADS_FILE = original_file
        self.assertEqual([thread["note"] for thread in active_threads], ["live"])

    def test_missing_followed_threads_file_means_none(self):
        original_file = collect_sources.FOLLOWED_THREADS_FILE
        collect_sources.FOLLOWED_THREADS_FILE = Path("/nonexistent/followed_threads.json")
        try:
            self.assertEqual(collect_sources.load_followed_threads("2026-10-07"), [])
        finally:
            collect_sources.FOLLOWED_THREADS_FILE = original_file


if __name__ == "__main__":
    unittest.main()
