#!/usr/bin/env python3
"""Adds search data to the website as it deploys (SK-287).

    scripts/site/seo.py <site directory>

Changes the files in place, so run it on the copy being deployed:
- each page in the sitemap gets FAQ structured data (FAQPage) made from its
  Questions section, so the two can never disagree;
- each sitemap entry gets a lastmod: the date of the page's last commit.
"""

import html
import json
import re
import subprocess
import sys
from pathlib import Path

SITE_URL = "https://samekeys.com/"


def text(fragment):
    """Plain text of an HTML fragment, with its whitespace collapsed."""
    return " ".join(html.unescape(re.sub(r"<[^>]+>", "", fragment)).split())


def faq_schema(page):
    faq = re.search(r'<div class="faq">(.*?)\n    </div>', page, re.S)
    if not faq:
        return None
    questions = re.findall(r"<summary>(.*?)</summary>\s*(.*?)</details>", faq.group(1), re.S)
    if not questions:
        return None
    return {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        "mainEntity": [
            {
                "@type": "Question",
                "name": text(question),
                "acceptedAnswer": {"@type": "Answer", "text": text(answer)},
            }
            for question, answer in questions
        ],
    }


def page_file(site, url):
    return site / url.removeprefix(SITE_URL) / "index.html"


def last_commit_date(path):
    date = subprocess.run(
        ["git", "log", "-1", "--format=%cs", "--", path.name],
        cwd=path.parent, capture_output=True, text=True, check=True,
    ).stdout.strip()
    if not date:
        sys.exit(f"error: {path} has no commits; deploy with the full history")
    return date


def main():
    site = Path(sys.argv[1])
    sitemap_path = site / "sitemap.xml"
    sitemap = sitemap_path.read_text()

    for url in re.findall(r"<loc>(.*?)</loc>", sitemap):
        path = page_file(site, url)
        page = path.read_text()
        schema = faq_schema(page)
        if schema is None:
            sys.exit(f"error: no Questions section in {path}")
        block = json.dumps(schema, ensure_ascii=False, indent=2).replace("\n", "\n  ")
        page = page.replace("</head>", f'  <script type="application/ld+json">\n  {block}\n  </script>\n</head>', 1)
        path.write_text(page)
        sitemap = sitemap.replace(
            f"<loc>{url}</loc>", f"<loc>{url}</loc>\n    <lastmod>{last_commit_date(path)}</lastmod>", 1
        )
        print(f"{url}: {len(schema['mainEntity'])} questions")

    sitemap_path.write_text(sitemap)


if __name__ == "__main__":
    main()
