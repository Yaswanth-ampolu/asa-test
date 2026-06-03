"""
ASA Spec → Qdrant pipeline.

Strategy:
1. Use existing pdftotext output (clean, fast)
2. Build page-number index so every chunk knows its page
3. Detect section boundaries from TOC pattern (number alone on line, then title)
4. Render page images → S3 (stored as payload, fetched on demand for vision)
5. Embed with Bedrock Titan v2 → push to Qdrant
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import boto3
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, PointStruct, VectorParams
from tqdm import tqdm

# ── Config ─────────────────────────────────────────────────────────────────
PDF_PATH     = Path("/home/ubuntu/siliconp/ASA_Technical_Specification_ver2.0.pdf")
TOTAL_PAGES  = 351
START_PAGE   = 22   # skip TOC and notices (pages 1-21)
BUCKET       = "asa-spec-kb-777095948735"
S3_PAGES_PFX = "pages"
COLLECTION   = "asa-spec"
VECTOR_DIM   = 1024
REGION       = "us-east-1"

QDRANT_URL     = os.environ["QDRANT_URL"]
QDRANT_API_KEY = os.environ["QDRANT_API_KEY"]

MODULE_MAP = {
    1: "Introduction",        2: "Overview",
    3: "Registers",           4: "Physical Layer Gen2020",
    5: "Data Link Layer",     6: "Security",
    7: "ASEP",                8: "Physical Layer MLE",
}
REGISTER_RE  = re.compile(r'\((\d+\.\d+)\)')
SECTION_NUM  = re.compile(r'^(\d+\.\d+(?:\.\d+)*)$')     # section number with at least one dot
DOT_LEADER   = re.compile(r'\.{3,}[\s\d]*$')             # strip ".......... 44" TOC dot leaders
PAGE_FOOTER  = re.compile(r'^(Automotive SerDes Alliance|Transceiver Specification)', re.I)
PAGE_NUM_RE  = re.compile(r'^\d+$')                       # bare page number line (footer)

# ── AWS clients ─────────────────────────────────────────────────────────────
bedrock = boto3.client("bedrock-runtime", region_name=REGION)
s3      = boto3.client("s3",              region_name=REGION)
qdrant  = QdrantClient(url=QDRANT_URL, api_key=QDRANT_API_KEY)


# ── 1. Build page-start index ───────────────────────────────────────────────
def build_page_index() -> dict[int, int]:
    """
    pdftotext -f N -l N gives exactly one page.
    We run it for every page and record the starting character offset in the
    concatenated text so we can map chunk offset → page number.
    Returns {page_num: char_offset_in_full_text}.
    """
    print("Building page index (fast — pdftotext per page)…")
    idx: dict[int, int] = {}
    offset = 0
    for page_num in tqdm(range(START_PAGE, TOTAL_PAGES + 1), desc="Indexing pages"):
        result = subprocess.run(
            ["pdftotext", "-f", str(page_num), "-l", str(page_num),
             str(PDF_PATH), "-"],
            capture_output=True, text=True
        )
        text = result.stdout
        idx[page_num] = offset
        offset += len(text)
    return idx


def page_for_offset(offset: int, idx: dict[int, int]) -> int:
    """Return the page number for a character offset in the full text."""
    page = 1
    for p, start in idx.items():
        if start <= offset:
            page = p
        else:
            break
    return page


# ── 2. Chunker ──────────────────────────────────────────────────────────────
def infer_module(section: str) -> str:
    try:
        top = int(section.split(".")[0])
        return MODULE_MAP.get(top, f"Chapter {top}")
    except (ValueError, IndexError):
        return "Unknown"


def infer_content_type(title: str, text: str) -> str:
    t = title.lower()
    if REGISTER_RE.search(title):
        return "register_table"
    if "state diagram" in t or "state machine" in t:
        return "state_machine"
    if "primitive" in t or "plp_" in t or "dlp_" in t:
        return "primitive_def"
    if "electrical" in t or "jitter" in t or "insertion loss" in t:
        return "timing_spec"
    if "key exchange" in t or "security policy" in t:
        return "security"
    if "asep" in t or "video" in t or "i2c" in t or "spi" in t or "gpio" in t:
        return "asep_protocol"
    return "text"


def build_chunks_from_text(full_text: str, page_idx: dict[int, int]) -> list[dict]:
    """
    Parse the pdftotext output.
    Section structure in this PDF:
      - Section number alone on a line  (e.g. "3.2.2")
      - Followed immediately by the section title on the next non-blank line
      - Then the body text
    """
    lines = full_text.split("\n")
    chunks = []

    current = {
        "section": "0",
        "section_title": "Preamble",
        "module": "Introduction",
        "body_lines": [],
        "char_offset": 0,
    }
    char_pos = 0

    i = 0
    while i < len(lines):
        line = lines[i]
        raw_len = len(line) + 1  # +1 for newline

        # Skip page footers / bare numbers used as column markers
        stripped = line.strip()
        if (PAGE_FOOTER.match(stripped)
                or (PAGE_NUM_RE.match(stripped) and len(stripped) <= 4)):
            char_pos += raw_len
            i += 1
            continue

        # Detect section number alone on line
        if SECTION_NUM.match(stripped):
            sec_num = stripped
            # Peek at next non-blank line for title
            title = ""
            j = i + 1
            while j < len(lines) and not lines[j].strip():
                j += 1
            if j < len(lines):
                title = lines[j].strip()
                # Strip TOC dot leaders: "Section Title ........... 44" → "Section Title"
                title = DOT_LEADER.sub('', title).strip()
                # Skip common noise
                if title.startswith("Automotive") or title.startswith("Transceiver"):
                    title = ""

            if title:
                # Flush current chunk
                body = "\n".join(current["body_lines"]).strip()
                if len(body) > 80:
                    pg = page_for_offset(current["char_offset"], page_idx)
                    chunks.append({
                        "section":          current["section"],
                        "section_title":    current["section_title"],
                        "module":           infer_module(current["section"]),
                        "page_start":       pg,
                        "text":             body[:4000],
                        "content_type":     infer_content_type(current["section_title"], body),
                        "register_address": (m.group(1) if (m := REGISTER_RE.search(current["section_title"])) else None),
                    })
                current = {
                    "section":      sec_num,
                    "section_title": title,
                    "module":       infer_module(sec_num),
                    "body_lines":   [],
                    "char_offset":  char_pos,
                }
                char_pos += raw_len
                i += 1
                continue

        # Skip TOC dot-leader lines entirely (they're noise from the TOC pages)
        clean = DOT_LEADER.sub('', stripped).strip()
        if clean and not DOT_LEADER.search(stripped):
            current["body_lines"].append(stripped)
        elif clean:
            pass  # skip dot-leader lines
        char_pos += raw_len
        i += 1

    # Flush last chunk
    body = "\n".join(current["body_lines"]).strip()
    if len(body) > 80:
        pg = page_for_offset(current["char_offset"], page_idx)
        chunks.append({
            "section":          current["section"],
            "section_title":    current["section_title"],
            "module":           infer_module(current["section"]),
            "page_start":       pg,
            "text":             body[:4000],
            "content_type":     infer_content_type(current["section_title"], body),
            "register_address": (m.group(1) if (m := REGISTER_RE.search(current["section_title"])) else None),
        })

    print(f"Built {len(chunks)} chunks")
    return chunks


# ── 3. S3 page image upload ─────────────────────────────────────────────────
def render_page_to_s3(page_num: int) -> str:
    s3_key = f"{S3_PAGES_PFX}/page_{page_num:03d}.png"
    try:
        s3.head_object(Bucket=BUCKET, Key=s3_key)
        return f"s3://{BUCKET}/{s3_key}"
    except Exception:
        pass
    out_prefix = f"/tmp/asa_p{page_num}"
    subprocess.run(
        ["pdftoppm", "-png", "-r", "150",
         "-f", str(page_num), "-l", str(page_num),
         str(PDF_PATH), out_prefix],
        check=True, capture_output=True
    )
    png_files = sorted(Path("/tmp").glob(f"asa_p{page_num}-*.png"))
    if not png_files:
        return ""
    png = png_files[0]
    s3.upload_file(str(png), BUCKET, s3_key, ExtraArgs={"ContentType": "image/png"})
    png.unlink(missing_ok=True)
    return f"s3://{BUCKET}/{s3_key}"


# ── 4. Embed ────────────────────────────────────────────────────────────────
def embed_text(text: str) -> list[float]:
    resp = bedrock.invoke_model(
        modelId="amazon.titan-embed-text-v2:0",
        body=json.dumps({"inputText": text[:8000], "dimensions": 1024}),
        contentType="application/json",
        accept="application/json",
    )
    return json.loads(resp["body"].read())["embedding"]


# ── 5. Main pipeline ─────────────────────────────────────────────────────────
def run_pipeline(upload_images: bool = True, batch_size: int = 50):
    print("=" * 60)
    print("ASA Spec → Qdrant Pipeline (text-first, images on demand)")
    print("=" * 60)

    # Collection
    existing = [c.name for c in qdrant.get_collections().collections]
    if COLLECTION not in existing:
        qdrant.create_collection(
            collection_name=COLLECTION,
            vectors_config=VectorParams(size=VECTOR_DIM, distance=Distance.COSINE),
        )
        print(f"Created collection '{COLLECTION}' ({VECTOR_DIM}-dim cosine)")
    else:
        print(f"Collection '{COLLECTION}' exists")

    # Build page index
    page_idx = build_page_index()

    # Full text — start from page 22 to skip TOC and notices
    print("Reading full text (pages 22–351)…")
    result = subprocess.run(
        ["pdftotext", "-f", str(START_PAGE), str(PDF_PATH), "-"],
        capture_output=True, text=True
    )
    full_text = result.stdout

    # Chunk
    chunks = build_chunks_from_text(full_text, page_idx)
    if not chunks:
        print("ERROR: No chunks. Check PDF path.")
        return

    # Upload page images (only pages referenced by chunks)
    page_image_urls: dict[int, str] = {}
    if upload_images:
        pages_needed = sorted({c["page_start"] for c in chunks})
        print(f"\nUploading {len(pages_needed)} page images to S3…")
        for page_num in tqdm(pages_needed, desc="Page images"):
            page_image_urls[page_num] = render_page_to_s3(page_num)

    # Embed + upsert
    print(f"\nEmbedding {len(chunks)} chunks → Qdrant…")
    points = []
    failed = 0

    for i, chunk in enumerate(tqdm(chunks, desc="Embedding")):
        try:
            embed_input = f"{chunk['section']} {chunk['section_title']}\n\n{chunk['text']}"
            vector = embed_text(embed_input)
            payload = {
                **chunk,
                "page_image_s3_url": page_image_urls.get(chunk["page_start"], ""),
                "source": "ASA_Technical_Specification_ver2.0.pdf",
            }
            points.append(PointStruct(id=i, vector=vector, payload=payload))
            if len(points) >= batch_size:
                qdrant.upsert(collection_name=COLLECTION, points=points)
                points = []
        except Exception as e:
            print(f"\n  Error chunk {i}: {e}")
            failed += 1
            time.sleep(1)

    if points:
        qdrant.upsert(collection_name=COLLECTION, points=points)

    total = len(chunks) - failed
    info = qdrant.get_collection(COLLECTION)
    print(f"\n✓ Done: {total} chunks embedded into Qdrant '{COLLECTION}'")
    print(f"  Points in collection: {info.points_count}")
    print(f"  Failed: {failed}")
    print(f"  Page images in S3: s3://{BUCKET}/{S3_PAGES_PFX}/")


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--no-images", action="store_true")
    p.add_argument("--batch-size", type=int, default=50)
    args = p.parse_args()
    run_pipeline(upload_images=not args.no_images, batch_size=args.batch_size)
