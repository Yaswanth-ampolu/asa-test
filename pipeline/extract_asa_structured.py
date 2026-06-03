#!/usr/bin/env python3
"""
Extract the ASA PDF into structured JSONL chunks suitable for RAG.

This parser is purpose-built for ASA_Technical_Specification_ver2.0.pdf:
- Uses the PDF outline from `pdftohtml -xml` as the authoritative section list.
- Reconstructs page text from positioned XML text elements.
- Splits chunks by real outline headings, not by register-looking body lines.
- Preserves page images as optional S3 URLs compatible with the existing pipeline.
- Emits one chunk per outline section with metadata plus figure/table captions.

It deliberately avoids external Python PDF libraries so it can run in the current
environment and on the EC2 host with only Poppler installed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


DEFAULT_PDF = Path("ASA_Technical_Specification_ver2.0.pdf")
MODULE_MAP = {
    1: "Introduction",
    2: "Overview",
    3: "Registers",
    4: "Physical Layer Gen2020",
    5: "Data Link Layer",
    6: "Security",
    7: "ASEP",
    8: "Physical Layer MLE",
    9: "Appendices",
}

SECTION_PREFIX_RE = re.compile(r"^((?:\d+(?:\.\d+)*)|(?:[IVX]+(?:\.[a-z])?))\s+(.+)$")
REGISTER_ADDR_RE = re.compile(r"(?<![\d.])(\d(?:/\d)?(?:\.\w+)?\.\d{4})(?![\d.])")
REGISTER_IN_TITLE_RE = re.compile(r"\(([^)]*\d(?:/\d)?(?:\.\w+)?\.\d{4}[^)]*)\)")
TABLE_CAPTION_RE = re.compile(r"Table\s+([A-ZIVX\d.-]+):\s*(.+)", re.I)
FIGURE_CAPTION_RE = re.compile(r"Figure\s+([A-ZIVX\d.-]+):\s*(.+)", re.I)
FOOTER_RE = re.compile(
    r"^(Automotive SerDes Alliance Confidential|Transceiver Specification version|"
    r"\d+\s*$|link to page\b)",
    re.I,
)


@dataclass
class TextAtom:
    top: int
    left: int
    width: int
    height: int
    text: str


@dataclass
class Page:
    number: int
    width: int
    height: int
    atoms: list[TextAtom] = field(default_factory=list)
    lines: list[tuple[int, str]] = field(default_factory=list)


@dataclass
class OutlineItem:
    section: str
    title: str
    page: int
    depth: int
    order: int
    heading: str


def run_pdftohtml_xml(pdf_path: Path, cache_path: Path | None = None) -> str:
    if cache_path and cache_path.exists():
        return cache_path.read_text(encoding="utf-8")

    result = subprocess.run(
        ["pdftohtml", "-xml", "-stdout", str(pdf_path)],
        text=True,
        capture_output=True,
        check=True,
    )
    xml_text = result.stdout
    if cache_path:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(xml_text, encoding="utf-8")
    return xml_text


def parse_xml(xml_text: str) -> tuple[dict[int, Page], list[OutlineItem]]:
    root = ET.fromstring(xml_text)
    pages: dict[int, Page] = {}
    for page_el in root.findall("page"):
        number = int(page_el.attrib["number"])
        page = Page(
            number=number,
            width=int(page_el.attrib.get("width", "0")),
            height=int(page_el.attrib.get("height", "0")),
        )
        for text_el in page_el.findall("text"):
            raw = "".join(text_el.itertext()).replace("\xa0", " ")
            text = re.sub(r"\s+", " ", raw).strip()
            if not text or FOOTER_RE.match(text):
                continue
            # Some footnote/table column marker numbers appear at the far left.
            if len(text) <= 2 and text.isdigit() and int(text) < 50 and int(text_el.attrib.get("left", "0")) < 90:
                continue
            page.atoms.append(
                TextAtom(
                    top=int(text_el.attrib.get("top", "0")),
                    left=int(text_el.attrib.get("left", "0")),
                    width=int(text_el.attrib.get("width", "0")),
                    height=int(text_el.attrib.get("height", "0")),
                    text=text,
                )
            )
        page.lines = build_page_lines(page.atoms)
        pages[number] = page

    outlines: list[OutlineItem] = []
    order = 0

    def walk(parent: ET.Element, depth: int) -> None:
        nonlocal order
        for child in parent:
            if child.tag == "item":
                text = " ".join("".join(child.itertext()).split())
                match = SECTION_PREFIX_RE.match(text)
                if match:
                    section = match.group(1)
                    title = match.group(2).strip()
                else:
                    section = f"outline-{order}"
                    title = text
                outlines.append(
                    OutlineItem(
                        section=section,
                        title=title,
                        page=int(child.attrib.get("page", "1")),
                        depth=depth,
                        order=order,
                        heading=text,
                    )
                )
                order += 1
            elif child.tag == "outline":
                walk(child, depth + 1)

    for outline_root in root.findall("outline"):
        walk(outline_root, 0)
    return pages, outlines


def build_page_lines(atoms: list[TextAtom]) -> list[tuple[int, str]]:
    rows: list[list[TextAtom]] = []
    for atom in sorted(atoms, key=lambda a: (a.top, a.left)):
        for row in rows:
            if abs(row[0].top - atom.top) <= 3:
                row.append(atom)
                break
        else:
            rows.append([atom])

    lines: list[tuple[int, str]] = []
    for row in rows:
        row = sorted(row, key=lambda a: a.left)
        parts: list[str] = []
        last_right = None
        for atom in row:
            if last_right is not None:
                gap = atom.left - last_right
                if gap > 45:
                    parts.append(" | ")
                elif gap > 12:
                    parts.append(" ")
            parts.append(atom.text)
            last_right = atom.left + atom.width
        line = re.sub(r"\s+", " ", "".join(parts)).strip()
        if line and not FOOTER_RE.match(line):
            lines.append((row[0].top, line))
    return lines


def normalize_heading_line(line: str) -> str:
    return re.sub(r"\s+", " ", line).strip()


def heading_candidates(item: OutlineItem) -> list[str]:
    candidates = [
        item.heading,
        f"{item.section} {item.title}",
    ]
    # Do not match generic titles by themselves ("Semantics of the primitive",
    # "When generated", "Effect of receipt"). Those headings repeat many times
    # on a page and caused unrelated outline entries to collapse to the first
    # occurrence. The section-numbered heading is present in this PDF and is the
    # stable discriminator.
    if item.section.startswith("outline-"):
        candidates.append(item.title)
    # PDF body sometimes separates the section number and title into adjacent text
    # atoms, so tolerate missing spaces around punctuation.
    return [normalize_heading_line(c) for c in candidates if c]


def find_heading_position(item: OutlineItem, pages: dict[int, Page], page_window: int = 3) -> tuple[int, int]:
    candidates = heading_candidates(item)
    for page_num in range(item.page, min(max(pages) + 1, item.page + page_window + 1)):
        page = pages.get(page_num)
        if not page:
            continue
        joined = [normalize_heading_line(line) for _, line in page.lines]
        for idx, line in enumerate(joined):
            for cand in candidates:
                if line == cand or line.startswith(cand + " ") or cand in line:
                    return page_num, page.lines[idx][0]
        # Split heading case: line N is section, line N+1 title.
        for idx in range(len(joined) - 1):
            if joined[idx] == item.section and item.title in joined[idx + 1]:
                return page_num, page.lines[idx][0]
    return item.page, 0


def top_module(section: str) -> str:
    if section.startswith("I"):
        return "Appendices"
    try:
        return MODULE_MAP.get(int(section.split(".")[0]), "Unknown")
    except ValueError:
        return "Unknown"


def content_type(item: OutlineItem, text: str, tables: list[dict[str, str]], figures: list[dict[str, str]]) -> str:
    title = item.title.lower()
    if REGISTER_IN_TITLE_RE.search(item.title) or (item.section.startswith("3.") and "register" in title):
        return "register" if REGISTER_IN_TITLE_RE.search(item.title) else "register_overview"
    if item.section.startswith("3.") and tables:
        return "register_table"
    if "state diagram" in title or "state machine" in title or figures:
        return "state_machine" if "state" in title else "figure"
    if "primitive" in title or "plp_" in title or "dlp_" in title:
        return "primitive_def"
    if "electrical" in title or "jitter" in title or "insertion loss" in title or "psd" in title:
        return "timing_spec"
    if "key exchange" in title or "security" in title:
        return "security"
    if item.section.startswith("7.") or any(k in title for k in ["asep", "video", "i2c", "spi", "gpio", "ethernet", "edp", "i2s"]):
        return "asep_protocol"
    if item.section.startswith("8."):
        return "mle_phy"
    return "text"


def register_address(title: str, text: str) -> str | None:
    m = REGISTER_IN_TITLE_RE.search(title)
    if m:
        return m.group(1).strip()
    m = REGISTER_ADDR_RE.search(title)
    if m:
        return m.group(1)
    return None


def extract_captions(text: str) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    tables = []
    figures = []
    for line in text.splitlines():
        if m := TABLE_CAPTION_RE.search(line):
            tables.append({"id": m.group(1), "title": m.group(2).strip()})
        if m := FIGURE_CAPTION_RE.search(line):
            figures.append({"id": m.group(1), "title": m.group(2).strip()})
    return tables, figures


def build_chunks(pages: dict[int, Page], outlines: list[OutlineItem]) -> list[dict[str, Any]]:
    positions = [(*find_heading_position(item, pages), item) for item in outlines]
    positions.sort(key=lambda x: (x[0], x[1], x[2].order))

    chunks: list[dict[str, Any]] = []
    for idx, (start_page, start_top, item) in enumerate(positions):
        if idx + 1 < len(positions):
            end_page, end_top, _ = positions[idx + 1]
        else:
            end_page, end_top = max(pages), 999999

        lines: list[str] = []
        for page_num in range(start_page, end_page + 1):
            page = pages.get(page_num)
            if not page:
                continue
            for top, line in page.lines:
                if page_num == start_page and top < start_top:
                    continue
                if page_num == end_page and top >= end_top:
                    continue
                lines.append(line)

        text = "\n".join(lines).strip()
        if len(text) < 30:
            continue
        tables, figures = extract_captions(text)
        addr = register_address(item.title, text)
        chunks.append(
            {
                "id": f"asa-{item.section}",
                "section": item.section,
                "section_title": item.title,
                "heading": item.heading,
                "module": top_module(item.section),
                "depth": item.depth,
                "page_start": start_page,
                "page_end": end_page,
                "content_type": content_type(item, text, tables, figures),
                "register_address": addr,
                "tables": tables,
                "figures": figures,
                "text": text,
                "source": "ASA_Technical_Specification_ver2.0.pdf",
            }
        )
    return chunks


def split_long_chunks(chunks: list[dict[str, Any]], max_chars: int = 5000, overlap_lines: int = 4) -> list[dict[str, Any]]:
    expanded: list[dict[str, Any]] = []
    for chunk in chunks:
        text = chunk["text"]
        if len(text) <= max_chars:
            chunk["part_index"] = 0
            chunk["part_count"] = 1
            expanded.append(chunk)
            continue

        parts: list[str] = []
        current: list[str] = []
        current_len = 0
        for line in text.splitlines():
            line_len = len(line) + 1
            if current and current_len + line_len > max_chars:
                parts.append("\n".join(current).strip())
                current = current[-overlap_lines:] if overlap_lines else []
                current_len = sum(len(x) + 1 for x in current)
            current.append(line)
            current_len += line_len
        if current:
            parts.append("\n".join(current).strip())

        for idx, part in enumerate(parts):
            new_chunk = dict(chunk)
            new_chunk["id"] = f"{chunk['id']}-part-{idx + 1}"
            new_chunk["text"] = part
            new_chunk["part_index"] = idx
            new_chunk["part_count"] = len(parts)
            expanded.append(new_chunk)
    return expanded


def write_outputs(chunks: list[dict[str, Any]], out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    jsonl = out_dir / "asa_structured_chunks.jsonl"
    jsonl.write_text(
        "".join(json.dumps(c, ensure_ascii=False) + "\n" for c in chunks),
        encoding="utf-8",
    )

    md_dir = out_dir / "markdown"
    md_dir.mkdir(exist_ok=True)
    for chunk in chunks:
        safe_section = re.sub(r"[^A-Za-z0-9_.-]+", "_", chunk["section"])
        safe_title = re.sub(r"[^A-Za-z0-9_.-]+", "_", chunk["section_title"])[:70].strip("_")
        path = md_dir / f"{safe_section}_{safe_title}.md"
        frontmatter = {
            k: chunk[k]
            for k in [
                "section",
                "section_title",
                "module",
                "depth",
                "page_start",
                "page_end",
                "content_type",
                "register_address",
                "tables",
                "figures",
                "source",
            ]
        }
        path.write_text(
            "---\n"
            + json.dumps(frontmatter, ensure_ascii=False, indent=2)
            + "\n---\n\n"
            + f"# {chunk['heading']}\n\n"
            + chunk["text"]
            + "\n",
            encoding="utf-8",
        )


def summarize(chunks: list[dict[str, Any]]) -> dict[str, Any]:
    from collections import Counter

    return {
        "chunks": len(chunks),
        "modules": dict(Counter(c["module"] for c in chunks)),
        "content_types": dict(Counter(c["content_type"] for c in chunks)),
        "register_address_count": sum(1 for c in chunks if c.get("register_address")),
        "table_caption_count": sum(len(c["tables"]) for c in chunks),
        "figure_caption_count": sum(len(c["figures"]) for c in chunks),
        "avg_text_len": round(sum(len(c["text"]) for c in chunks) / max(len(chunks), 1), 1),
        "max_text_len": max((len(c["text"]) for c in chunks), default=0),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", type=Path, default=DEFAULT_PDF)
    parser.add_argument("--out-dir", type=Path, default=Path("pipeline/out"))
    parser.add_argument("--cache-xml", type=Path, default=Path("pipeline/out/asa_pdftohtml.xml"))
    parser.add_argument("--print-sample", action="store_true")
    args = parser.parse_args()

    xml_text = run_pdftohtml_xml(args.pdf, args.cache_xml)
    pages, outlines = parse_xml(xml_text)
    chunks = split_long_chunks(build_chunks(pages, outlines))
    write_outputs(chunks, args.out_dir)
    summary = summarize(chunks)
    (args.out_dir / "asa_structured_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, indent=2))

    if args.print_sample:
        for needle in ["SGconfig", "MLE Features", "DLP_TX.indicateSlot"]:
            print("\n" + "=" * 80)
            print(f"SAMPLE: {needle}")
            for chunk in chunks:
                if needle.lower() in (chunk["heading"] + "\n" + chunk["text"]).lower():
                    print(json.dumps({k: chunk[k] for k in ["section", "section_title", "module", "content_type", "register_address", "page_start", "page_end"]}, indent=2))
                    print(chunk["text"][:1600])
                    break
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
