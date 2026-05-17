#!/usr/bin/env python3
"""Render a CJIS Markdown assessment report to a single self-contained HTML file.

Usage:
    python3 generate-html-report.py cjis-reports/cjis-assessment-2026-04-23.md

Produces a sibling .html file. Colors severity badges, scorecards, and status rows.
No third-party deps — uses a tiny Markdown converter (github.com/trentm/python-markdown2
if available, else a minimal built-in fallback good enough for the fixed template).
"""
from __future__ import annotations

import html
import re
import sys
from pathlib import Path

try:
    import markdown2  # optional; falls back to minimal converter
    _HAVE_MD2 = True
except ImportError:
    _HAVE_MD2 = False


CSS = """
:root {
  --bg: #0b1020; --fg: #e6edf3; --muted: #9aa7b8;
  --card: #121a2e; --border: #1f2a44;
  --blocker: #ff5576; --risk: #ff9a4d; --gap: #ffd166; --info: #4ade80;
  --compliant: #4ade80; --subcompliant: #86efac; --atrisk: #fbbf24;
  --noncompliant: #ff5576; --notassessed: #64748b;
  --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
}
@media (prefers-color-scheme: light) {
  :root { --bg:#f8fafc; --fg:#0f172a; --muted:#475569; --card:#fff; --border:#e2e8f0; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg);
  font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; }
.wrap { max-width: 960px; margin: 0 auto; padding: 32px 24px 64px; }
h1 { font-size: 28px; margin: 0 0 8px; }
h2 { font-size: 22px; margin: 40px 0 12px; padding-bottom: 6px; border-bottom: 1px solid var(--border); }
h3 { font-size: 17px; margin: 24px 0 8px; color: var(--muted); }
p, li { color: var(--fg); }
code { font-family: var(--mono); font-size: 0.92em;
  background: var(--border); padding: 1px 5px; border-radius: 4px; }
pre { background: var(--card); border: 1px solid var(--border); border-radius: 8px;
  padding: 12px 14px; overflow-x: auto; font-family: var(--mono); font-size: 13px; }
table { width: 100%; border-collapse: collapse; margin: 12px 0 20px;
  background: var(--card); border: 1px solid var(--border); border-radius: 8px; overflow: hidden; }
th, td { padding: 10px 12px; text-align: left; border-bottom: 1px solid var(--border); vertical-align: top; }
th { background: rgba(255,255,255,0.03); font-weight: 600; font-size: 13px; color: var(--muted);
  text-transform: uppercase; letter-spacing: 0.04em; }
tr:last-child td { border-bottom: none; }

/* Severity badges */
.sev { display: inline-block; padding: 2px 10px; border-radius: 999px;
  font-size: 12px; font-weight: 700; letter-spacing: 0.03em; white-space: nowrap; }
.sev-blocker { background: rgba(255,85,118,0.15); color: var(--blocker); border: 1px solid var(--blocker); }
.sev-risk    { background: rgba(255,154,77,0.15); color: var(--risk);    border: 1px solid var(--risk); }
.sev-gap     { background: rgba(255,209,102,0.15); color: var(--gap);    border: 1px solid var(--gap); }
.sev-info    { background: rgba(74,222,128,0.12); color: var(--info);   border: 1px solid var(--info); }

/* Status labels */
.status { display: inline-block; padding: 2px 10px; border-radius: 6px;
  font-size: 12px; font-weight: 600; }
.st-compliant     { background: rgba(74,222,128,0.15); color: var(--compliant); }
.st-subcompliant  { background: rgba(134,239,172,0.15); color: var(--subcompliant); }
.st-atrisk        { background: rgba(251,191,36,0.15); color: var(--atrisk); }
.st-noncompliant  { background: rgba(255,85,118,0.18); color: var(--noncompliant); }
.st-notassessed   { background: rgba(100,116,139,0.2); color: var(--notassessed); }

.meta { color: var(--muted); font-size: 13px; margin-bottom: 24px; }
.footer { margin-top: 48px; padding-top: 16px; border-top: 1px solid var(--border);
  color: var(--muted); font-size: 12px; }
"""


def _minimal_md(src: str) -> str:
    """Fallback Markdown renderer — handles the subset our template uses."""
    out = []
    in_code = False
    in_list = False
    table_rows: list[str] = []

    def flush_table():
        nonlocal table_rows
        if not table_rows:
            return
        header = table_rows[0]
        # skip the separator row (---|---)
        body = table_rows[2:] if len(table_rows) > 1 and re.match(r"^\s*\|[\s:|-]+\|\s*$", table_rows[1]) else table_rows[1:]
        cells = lambda row: [c.strip() for c in row.strip().strip("|").split("|")]
        out.append("<table><thead><tr>" + "".join(f"<th>{html.escape(c)}</th>" for c in cells(header)) + "</tr></thead><tbody>")
        for r in body:
            out.append("<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in cells(r)) + "</tr>")
        out.append("</tbody></table>")
        table_rows = []

    def _inline(text: str) -> str:
        # inline code, bold, italics, links — minimal
        text = re.sub(r"`([^`]+)`", lambda m: f"<code>{html.escape(m.group(1))}</code>", text)
        text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
        text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", text)
        text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
        return text

    for raw in src.splitlines():
        line = raw.rstrip()
        if line.startswith("```"):
            flush_table()
            if not in_code:
                out.append("<pre><code>")
                in_code = True
            else:
                out.append("</code></pre>")
                in_code = False
            continue
        if in_code:
            out.append(html.escape(line))
            continue
        if line.startswith("|") and line.endswith("|"):
            table_rows.append(line)
            continue
        else:
            flush_table()
        if not line.strip():
            if in_list:
                out.append("</ul>")
                in_list = False
            out.append("")
            continue
        m = re.match(r"^(#{1,6})\s+(.+)$", line)
        if m:
            if in_list:
                out.append("</ul>"); in_list = False
            lvl = len(m.group(1))
            out.append(f"<h{lvl}>{_inline(m.group(2))}</h{lvl}>")
            continue
        if re.match(r"^[-*]\s+", line):
            if not in_list:
                out.append("<ul>"); in_list = True
            out.append(f"<li>{_inline(line[2:].strip())}</li>")
            continue
        if in_list:
            out.append("</ul>"); in_list = False
        out.append(f"<p>{_inline(line)}</p>")
    if in_code:
        out.append("</code></pre>")
    if in_list:
        out.append("</ul>")
    flush_table()
    return "\n".join(out)


SEV_MAP = [
    ("AUDIT BLOCKER", "sev-blocker"),
    ("FINDING RISK",  "sev-risk"),
    ("GAP",           "sev-gap"),
    ("INFO",          "sev-info"),
]
STATUS_MAP = [
    ("Non-Compliant",            "st-noncompliant"),
    ("At Risk",                  "st-atrisk"),
    ("Substantially Compliant",  "st-subcompliant"),
    ("Compliant",                "st-compliant"),
    ("Not Assessed",             "st-notassessed"),
]


def _badgeify(html_text: str) -> str:
    """Wrap severity / status strings in styled spans inside table cells."""
    # severity (only inside <td>...</td>)
    def wrap_sev(m: re.Match) -> str:
        inner = m.group(1)
        for label, cls in SEV_MAP:
            if inner.strip().upper() == label:
                return f'<td><span class="sev {cls}">{label}</span></td>'
        return m.group(0)
    html_text = re.sub(r"<td>([^<]+)</td>", wrap_sev, html_text)
    # status — order matters (longer first)
    for label, cls in STATUS_MAP:
        html_text = re.sub(
            r"<td>\s*" + re.escape(label) + r"\s*</td>",
            f'<td><span class="status {cls}">{label}</span></td>',
            html_text,
        )
    return html_text


def render(md_path: Path) -> Path:
    src = md_path.read_text(encoding="utf-8")
    body_html = markdown2.markdown(src, extras=["tables", "fenced-code-blocks"]) if _HAVE_MD2 else _minimal_md(src)
    body_html = _badgeify(body_html)
    out = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(md_path.stem)}</title>
<style>{CSS}</style></head>
<body><div class="wrap">{body_html}
<div class="footer">Generated from <code>{html.escape(md_path.name)}</code> by the CJIS assessment skill.</div>
</div></body></html>"""
    out_path = md_path.with_suffix(".html")
    out_path.write_text(out, encoding="utf-8")
    return out_path


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <report.md>", file=sys.stderr)
        sys.exit(2)
    p = Path(sys.argv[1]).expanduser().resolve()
    if not p.is_file():
        print(f"Not a file: {p}", file=sys.stderr)
        sys.exit(2)
    out = render(p)
    print(out)
