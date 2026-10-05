"""Dump the full current candidate set (not just what's new) for a landscape baseline review.

Writes Markdown to stdout: every app from the App Store keyword searches and every YC company
matching the topic, with the fields needed to triage them. Reuses the collector's config.
"""

import json
import time
import urllib.parse

from collect_sources import (
    APP_STORE_KEYWORDS,
    COUNTRY,
    TRACKED_APPS,
    YC_DATASET_URL,
    http_get,
    matches_topic,
)


def list_app_store_candidates():
    candidates_by_id = {}
    for keyword in APP_STORE_KEYWORDS:
        search_url = (
            f"https://itunes.apple.com/search?term={urllib.parse.quote(keyword)}"
            f"&entity=software&country={COUNTRY}&limit=25"
        )
        for result in json.loads(http_get(search_url)).get("results", []):
            candidate = candidates_by_id.setdefault(result["trackId"], {"result": result, "keywords": []})
            candidate["keywords"].append(keyword)
        time.sleep(1)
    return candidates_by_id


def print_app_store_section():
    print("## App Store candidates (all results of the keyword searches)")
    candidates_by_id = list_app_store_candidates()
    for app_id, candidate in sorted(candidates_by_id.items(), key=lambda item: item[1]["result"].get("trackName", "")):
        result = candidate["result"]
        tracked_marker = " [ALREADY TRACKED]" if app_id in TRACKED_APPS else ""
        description = (result.get("description") or "").replace("\n", " ")[:300]
        print(
            f"- {result.get('trackName')} — {result.get('sellerName')} — id {app_id}{tracked_marker} — "
            f"genre {result.get('primaryGenreName')} — first {result.get('releaseDate', '')[:10]}, "
            f"updated {result.get('currentVersionReleaseDate', '')[:10]}, ratings {result.get('userRatingCount')} "
            f"— keywords: {', '.join(candidate['keywords'])}\n  > {description}"
        )


def print_yc_section():
    print("\n## YC companies matching the topic (full current set)")
    all_companies = json.loads(http_get(YC_DATASET_URL))
    matching_companies = [company for company in all_companies if matches_topic(company)]
    for company in sorted(matching_companies, key=lambda company: company.get("launched_at") or 0, reverse=True):
        print(
            f"- {company.get('name')} ({company.get('batch')}, {company.get('status')}, team {company.get('team_size')}, "
            f"{', '.join(company.get('regions') or [])}) — {company.get('one_liner')} — {company.get('website')} "
            f"— https://www.ycombinator.com/companies/{company.get('slug')}"
        )


if __name__ == "__main__":
    print_app_store_section()
    print_yc_section()
