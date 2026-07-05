---
name: docx
description: Use when generating, parsing, extracting from, or editing a .docx Word document from an agent context. Covers reading paragraphs/tables, creating documents, styles, headings, tables, images, and templating with python-docx.
---

# DOCX: Read, Create, and Edit Word Documents

`.docx` is an Office Open XML zip archive with a real document object model. `python-docx` is the go-to library for both reading and writing — unlike PDF, editing in place is well supported.

Install: `pip install python-docx` (imported as `docx`).

## Read and Extract

```python
from docx import Document
doc = Document("report.docx")

# Paragraph text
full_text = "\n".join(p.text for p in doc.paragraphs)

# Tables
for table in doc.tables:
    for row in table.rows:
        cells = [cell.text for cell in row.cells]

# Headings only
headings = [p.text for p in doc.paragraphs if p.style.name.startswith("Heading")]
```

- `doc.paragraphs` gives *body* paragraphs only. Text inside tables, headers, footers, and text boxes is **not** included — iterate `doc.tables`, `section.header`, and `section.footer` separately.
- Reading order of interleaved paragraphs and tables is not preserved by the two separate lists. If exact order matters, walk `doc.element.body` children and dispatch on tag (`w:p` vs `w:tbl`).

## Create a Document

```python
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()
doc.add_heading("Quarterly Report", level=0)     # 0 = title
doc.add_heading("Summary", level=1)

p = doc.add_paragraph("Revenue grew ")
p.add_run("12%").bold = True
p.add_run(" year over year.")

# Table
table = doc.add_table(rows=1, cols=2)
table.style = "Light Grid Accent 1"
hdr = table.rows[0].cells
hdr[0].text, hdr[1].text = "Metric", "Value"
row = table.add_row().cells
row[0].text, row[1].text = "Revenue", "1.2M"

doc.add_picture("chart.png", width=Inches(5))
doc.save("out.docx")
```

## Runs, Styles, and Formatting

Formatting lives on **runs**, not paragraphs — a paragraph is a list of runs, each with its own font. To bold part of a sentence you split it into runs.

```python
run = paragraph.add_run("important")
run.bold = True
run.italic = True
run.font.size = Pt(14)
run.font.color.rgb = RGBColor(0xC0, 0x00, 0x00)
```

Prefer named **styles** over inline formatting for consistency: `doc.add_paragraph("...", style="Intense Quote")`. Use the built-in style names ("Heading 1", "List Bullet", "Normal") — a style must exist in the document's template or assignment raises `KeyError`.

## Templating (fill a prepared .docx)

The cleanest approach for report generation is a hand-designed template with `{{ placeholders }}` filled by `docxtpl` (Jinja2 for docx), which preserves all styling:

```python
from docxtpl import DocxTemplate
tpl = DocxTemplate("template.docx")
tpl.render({"customer": "Acme", "total": "1,240"})
tpl.save("invoice.docx")
```

For simple find-replace without a template engine, replace text at the **run** level, not the paragraph level — replacing `paragraph.text` destroys all run formatting.

## Gotchas

- Editing `paragraph.text = "..."` collapses the paragraph to a single run and loses inline formatting. Modify individual runs instead.
- `python-docx` cannot render, repaginate, or convert to PDF — it only reads/writes the XML. For PDF output use LibreOffice headless (`soffice --headless --convert-to pdf`) or a rendering service.
- `add_heading(level=0)` is the document Title, `level=1..9` are Heading 1..9.
- Images are embedded by path at insert time; there is no relinking. Sizes given without `width`/`height` use the image's native DPI.
- Merged table cells: use `cell_a.merge(cell_b)`; reading merged cells returns the same text for every underlying grid position.
