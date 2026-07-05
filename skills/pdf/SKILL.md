---
name: pdf
description: Use when generating, parsing, extracting from, splitting, merging, or filling a .pdf from an agent context. Covers text/table extraction, form filling, page manipulation, and PDF creation with the go-to Python libraries (pypdf, pdfplumber, reportlab).
---

# PDF: Read, Extract, and Create

PDF is a fixed-layout format — there is no reliable document model, so "read" and "write" are different problems solved by different libraries. Pick by task.

## Library Selection

| Task | Library | Why |
|------|---------|-----|
| Extract text (simple) | `pypdf` | Pure-Python, no system deps, fast for basic text |
| Extract text/tables with layout | `pdfplumber` | Word/char positions, table detection, bounding boxes |
| Split / merge / rotate / extract pages | `pypdf` | `PdfReader` / `PdfWriter` page ops |
| Read/fill AcroForm fields | `pypdf` | `reader.get_fields()`, `writer.update_page_form_field_values()` |
| Create a PDF from scratch | `reportlab` | Full layout engine — canvas + Platypus flowables |
| HTML/CSS -> PDF | `weasyprint` | When the source is already HTML; honours CSS paged media |
| Scanned / image-only PDF | `pdf2image` + `pytesseract` | Rasterise then OCR — there is no embedded text to extract |

Install: `pip install pypdf pdfplumber reportlab`. WeasyPrint and pdf2image need system libraries (`libpango`, `poppler`).

## Extract Text and Tables

```python
# Simple text extraction
from pypdf import PdfReader
reader = PdfReader("doc.pdf")
text = "\n".join(page.extract_text() or "" for page in reader.pages)

# Layout-aware text + tables
import pdfplumber
with pdfplumber.open("doc.pdf") as pdf:
    page = pdf.pages[0]
    text = page.extract_text()
    tables = page.extract_tables()   # list of list-of-rows
    words = page.extract_words()     # each with x0/x1/top/bottom
```

- `extract_text()` returns `None` (not `""`) for pages with no text layer — always guard with `or ""`.
- If extraction returns empty on every page, the PDF is image-only (scanned). Rasterise with `pdf2image` and OCR with `pytesseract`; do not keep retrying pypdf.
- Table detection is heuristic. Tune `pdfplumber`'s `table_settings` (`vertical_strategy`, `horizontal_strategy`) when columns merge or split.

## Manipulate Pages (split, merge, rotate)

```python
from pypdf import PdfReader, PdfWriter

# Merge
writer = PdfWriter()
for path in ("a.pdf", "b.pdf"):
    for page in PdfReader(path).pages:
        writer.add_page(page)
with open("merged.pdf", "wb") as f:
    writer.write(f)

# Extract a page range
reader = PdfReader("in.pdf")
writer = PdfWriter()
for page in reader.pages[2:5]:
    writer.add_page(page)
```

## Fill Form Fields (AcroForm)

```python
from pypdf import PdfReader, PdfWriter
reader = PdfReader("form.pdf")
writer = PdfWriter(clone_from=reader)
writer.update_page_form_field_values(
    writer.pages[0], {"applicant_name": "Ada Lovelace", "agree": "/Yes"}
)
# Make the filled values render everywhere
writer.set_need_appearances_writer(True)
```

Checkbox/radio values are the field's export value (often `/Yes`), not `True`. Inspect with `reader.get_fields()` first.

## Create a PDF

```python
# Structured document (recommended) via Platypus flowables
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Table, Spacer
from reportlab.lib.styles import getSampleStyleSheet

styles = getSampleStyleSheet()
doc = SimpleDocTemplate("out.pdf", pagesize=A4)
doc.build([
    Paragraph("Quarterly Report", styles["Title"]),
    Spacer(1, 12),
    Table([["Metric", "Value"], ["Revenue", "1.2M"]]),
])
```

Use the `canvas` API only for absolute-positioned drawing; use Platypus flowables for anything that flows across pages.

## Gotchas

- Coordinates originate at the **bottom-left**; y increases upward (the opposite of screen coordinates).
- `pypdf` cannot reflow or edit existing text content — it manipulates pages and form fields, not paragraphs. To "edit" text you regenerate the page.
- Extracted text order follows the PDF's content stream, not visual reading order — multi-column layouts may interleave. Use `pdfplumber` word coordinates to re-sort if order matters.
- Encrypted PDFs: call `reader.decrypt(password)` before reading.
- Never trust extracted numbers from tables without spot-checking — merged cells and rotated text corrupt table extraction silently.
