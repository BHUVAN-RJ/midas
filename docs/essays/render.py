import html, re, sys, difflib, pathlib

INS_OPEN, INS_CLOSE = "\u27e6", "\u27e7"  # markers survive html.escape, swapped for <ins> later

source_path = sys.argv[1]
output_path = sys.argv[2]
previous_path = pathlib.Path(output_path).with_suffix(".prev.md")

def split_blocks(markdown_text):
    """Blocks are paragraphs separated by blank lines; lists are split per line."""
    blocks = []
    for chunk in re.split(r"\n\s*\n", markdown_text):
        for line in chunk.split("\n"):
            stripped = line.strip()
            if stripped:
                blocks.append(stripped)
    return blocks

previous_blocks = split_blocks(previous_path.read_text(encoding="utf-8")) if previous_path.exists() else None
previous_block_set = set(previous_blocks or [])

def mark_changes(block_text):
    """Return block text with inserted/changed words wrapped in INS markers."""
    if previous_blocks is None or block_text in previous_block_set:
        return block_text
    candidates = difflib.get_close_matches(block_text, previous_blocks, n=1, cutoff=0.6)
    if not candidates:
        return INS_OPEN + block_text + INS_CLOSE
    old_words = candidates[0].split()
    new_words = block_text.split()
    matcher = difflib.SequenceMatcher(None, old_words, new_words, autojunk=False)
    output_words = []
    for tag, old_start, old_end, new_start, new_end in matcher.get_opcodes():
        segment = new_words[new_start:new_end]
        if tag == "equal":
            output_words.extend(segment)
        elif segment:
            output_words.append(INS_OPEN + " ".join(segment) + INS_CLOSE)
        else:  # pure deletion: drop a visible marker so the reader sees text left here
            output_words.append(INS_OPEN + "\u2205" + INS_CLOSE)
    return " ".join(output_words)

def inline_format(text):
    escaped = html.escape(text, quote=False)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", escaped)
    # gap markers get highlighted so they are easy to spot
    escaped = re.sub(r"\[gap:([^\]]*)\]", r'<mark class="gap">[gap:\1]</mark>', escaped)
    escaped = escaped.replace(INS_OPEN, '<ins class="chg">').replace(INS_CLOSE, "</ins>")
    return escaped

body_parts = []
paragraph_lines = []
list_tag = None  # "ol" or "ul" while inside a list

def flush_paragraph():
    global paragraph_lines
    if paragraph_lines:
        body_parts.append("<p>" + inline_format(mark_changes(" ".join(paragraph_lines))) + "</p>")
        paragraph_lines = []

def close_list():
    global list_tag
    if list_tag:
        body_parts.append(f"</{list_tag}>")
        list_tag = None

source_text = re.sub(r"<!--.*?-->", "", pathlib.Path(source_path).read_text(encoding="utf-8"), flags=re.S)
if True:
    for raw_line in source_text.splitlines(keepends=True):
        line = raw_line.rstrip("\n")
        stripped = line.strip()
        ordered_match = re.match(r"^(\d+)\.\s+(.*)", stripped)
        bullet_match = re.match(r"^-\s+(.*)", stripped)

        if stripped == "":
            flush_paragraph()
            continue
        if stripped == "---":
            flush_paragraph(); close_list()
            body_parts.append("<hr>")
            continue
        if stripped.startswith("# "):
            flush_paragraph(); close_list()
            body_parts.append("<h1>" + inline_format(mark_changes(stripped)) + "</h1>")
            continue
        if stripped.startswith("## "):
            flush_paragraph(); close_list()
            body_parts.append("<h2>" + inline_format(mark_changes(stripped)).replace("## ", "", 1) + "</h2>")
            continue
        if ordered_match and not line.startswith("   "):
            flush_paragraph()
            if list_tag != "ol":
                close_list(); body_parts.append("<ol>"); list_tag = "ol"
            body_parts.append("<li>" + inline_format(mark_changes(stripped)).split(". ", 1)[-1] + "</li>")
            continue
        if bullet_match:
            flush_paragraph()
            if list_tag not in ("ol", "ul"):
                body_parts.append("<ul>"); list_tag = "ul"
            body_parts.append("<li>" + inline_format(mark_changes(stripped)).replace("- ", "", 1) + "</li>")
            continue
        paragraph_lines.append(stripped)

flush_paragraph(); close_list()

page = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Case for Personal Software</title>
<style>
:root { --bg:#fbfaf7; --fg:#1d1d1b; --muted:#6b6a66; --rule:#e2dfd7; --accent:#8a5a1f; --mark:#fff2a8; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#15150f; --fg:#e8e6df; --muted:#9a978e; --rule:#2e2d27; --accent:#d9a860; --mark:#5a4a12; } }
:root[data-theme="dark"] { --bg:#15150f; --fg:#e8e6df; --muted:#9a978e; --rule:#2e2d27; --accent:#d9a860; --mark:#5a4a12; }
html { background:var(--bg); }
body { margin:0; padding:48px 16px 96px; background:var(--bg); color:var(--fg);
  font-family: Georgia, "Iowan Old Style", "Times New Roman", serif; font-size:20px; line-height:1.6; }
main { max-width:680px; margin:0 auto; }
h1 { font-size:2.1em; line-height:1.15; margin:0 0 .4em; letter-spacing:-.01em; }
h2 { font-size:1.25em; margin:2.2em 0 .5em; }
p { margin:0 0 1.15em; }
hr { border:0; border-top:1px solid var(--rule); margin:2.5em 0; }
ol, ul { padding-left:1.4em; } li { margin:.35em 0; }
code { font-family: ui-monospace, Menlo, monospace; font-size:.85em; background:var(--rule); padding:.05em .3em; border-radius:3px; }
mark.gap { background:var(--mark); color:var(--fg); padding:.05em .25em; }
ins.chg { text-decoration:none; background:var(--mark); box-shadow:0 0 0 2px var(--mark); border-radius:2px; }
#changebar { position:sticky; top:0; z-index:5; background:var(--bg); border-bottom:1px solid var(--rule);
  font-family: ui-sans-serif, system-ui, sans-serif; font-size:14px; color:var(--muted);
  padding:8px 0; margin:-48px 0 32px; display:flex; gap:12px; align-items:center; }
#changebar button { font:inherit; padding:4px 10px; border:1px solid var(--rule); background:var(--bg); color:var(--fg); border-radius:6px; cursor:pointer; }
ins.chg.current { outline:2px solid var(--accent); }
em { color:var(--muted); }
h2 + p::first-letter {}
.count { color:var(--muted); font-size:.75em; }
</style></head><body><main>
<div id="changebar"><span id="changecount"></span><button id="prevchg">prev</button><button id="nextchg">next</button></div>
""" + "\n".join(body_parts) + """
</main>
<script>
(function () {
  var changes = Array.prototype.slice.call(document.querySelectorAll("ins.chg"));
  var countLabel = document.getElementById("changecount");
  var currentIndex = -1;
  function showChange(index) {
    if (!changes.length) return;
    if (currentIndex >= 0) changes[currentIndex].classList.remove("current");
    currentIndex = (index + changes.length) % changes.length;
    changes[currentIndex].classList.add("current");
    changes[currentIndex].scrollIntoView({ block: "center", behavior: "smooth" });
    countLabel.textContent = "change " + (currentIndex + 1) + " of " + changes.length;
  }
  function goNext() { showChange(currentIndex + 1); }
  function goPrevious() { showChange(currentIndex - 1); }
  countLabel.textContent = changes.length ? changes.length + " changes since last render" : "no changes since last render";
  document.getElementById("nextchg").addEventListener("click", goNext);
  document.getElementById("prevchg").addEventListener("click", goPrevious);
  document.addEventListener("keydown", function (event) {
    if (event.key === "n" || event.key === "j") goNext();
    if (event.key === "p" || event.key === "k") goPrevious();
  });
})();
</script>
</body></html>
"""

with open(output_path, "w", encoding="utf-8") as output_file:
    output_file.write(page)

previous_path.write_text(pathlib.Path(source_path).read_text(encoding="utf-8"), encoding="utf-8")
