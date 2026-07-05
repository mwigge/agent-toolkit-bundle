---
name: pptx
description: Use when generating, parsing, extracting from, or editing a .pptx PowerPoint presentation from an agent context. Covers reading slide text, building decks from layouts, placeholders, text/tables/charts/images, and template reuse with python-pptx.
---

# PPTX: Read, Create, and Edit Presentations

`.pptx` is Office Open XML. `python-pptx` is the go-to library. The core model: a **presentation** has **slides**, each built from a **slide layout**, each layout has **placeholders** (title, body, picture) you populate. Working *with* layouts beats absolute positioning.

Install: `pip install python-pptx` (imported as `pptx`).

## Read and Extract

```python
from pptx import Presentation
prs = Presentation("deck.pptx")

for i, slide in enumerate(prs.slides):
    for shape in slide.shapes:
        if shape.has_text_frame:
            for para in shape.text_frame.paragraphs:
                text = "".join(run.text for run in para.runs)
        if shape.has_table:
            rows = [[c.text for c in row.cells] for row in shape.table.rows]
```

- Text lives in shapes with a text frame; not every shape has one — guard with `shape.has_text_frame`.
- `shape.text` is a convenience for all text in a shape; use `paragraphs`/`runs` when you need per-run formatting.
- Speaker notes: `slide.notes_slide.notes_text_frame.text` (check `slide.has_notes_slide` first).

## Create a Deck from Layouts

```python
from pptx import Presentation
from pptx.util import Inches, Pt

prs = Presentation()                       # or Presentation("brand-template.pptx")
title_layout = prs.slide_layouts[0]        # 0=Title, 1=Title+Content, 5=Title Only, 6=Blank
slide = prs.slides.add_slide(title_layout)
slide.placeholders[0].text = "Quarterly Review"   # title placeholder
slide.placeholders[1].text = "Q3 2026"            # subtitle

content = prs.slides.add_slide(prs.slide_layouts[1])
content.shapes.title.text = "Highlights"
body = content.placeholders[1].text_frame
body.text = "Revenue up 12%"
for line in ("Churn down 3%", "NPS 62"):
    p = body.add_paragraph()
    p.text = line
    p.level = 1                            # indent level for bullets

prs.save("out.pptx")
```

Start from a branded template (`Presentation("template.pptx")`) to inherit fonts, colours, and master slides — then only add slides. This is how you match a house style without re-styling every shape.

## Tables, Charts, Images

```python
from pptx.util import Inches
from pptx.chart.data import CategoryChartData
from pptx.enum.chart import XL_CHART_TYPE

# Table
rows, cols = 3, 2
tbl = slide.shapes.add_table(rows, cols, Inches(1), Inches(1.5), Inches(6), Inches(2)).table
tbl.cell(0, 0).text = "Metric"

# Native (editable) chart
data = CategoryChartData()
data.categories = ["Q1", "Q2", "Q3"]
data.add_series("Revenue", (0.9, 1.1, 1.2))
slide.shapes.add_chart(XL_CHART_TYPE.COLUMN_CLUSTERED, Inches(1), Inches(1), Inches(6), Inches(4), data)

# Image
slide.shapes.add_picture("chart.png", Inches(1), Inches(1), width=Inches(6))
```

Prefer native charts (`add_chart`) over pasting an image when the user may want to edit the data. Use an image (e.g. a matplotlib export) when you need a chart type or styling python-pptx cannot produce.

## Gotchas

- Placeholder indices vary by layout — `slide.placeholders` is not always `[0]=title, [1]=body`. Iterate and read `placeholder_format.idx` / `.type` to find the right one, or use `slide.shapes.title`.
- All positions/sizes are EMU; always wrap in `Inches()`, `Pt()`, or `Emu()` — raw ints are English Metric Units (914400 per inch).
- `python-pptx` cannot render slides to images/PDF, cannot run transitions/animations, and has limited support for editing existing charts' data. To render, use LibreOffice headless (`soffice --headless --convert-to pdf deck.pptx`).
- Adding a paragraph: the text frame starts with one empty paragraph — set `.text` on it first, then `add_paragraph()` for each subsequent line, or you get a leading blank bullet.
- Deleting a slide is not a first-class API; you manipulate `prs.slides._sldIdLst` XML directly. Prefer building the deck you want rather than pruning.
