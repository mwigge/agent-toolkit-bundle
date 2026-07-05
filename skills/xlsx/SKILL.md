---
name: xlsx
description: Use when generating, parsing, extracting from, or editing a .xlsx Excel spreadsheet from an agent context. Covers reading/writing cells, formulas, formatting, multiple sheets, and the pandas-vs-openpyxl choice for tabular data.
---

# XLSX: Read, Create, and Edit Spreadsheets

Two libraries, two jobs. Choose deliberately:

- **`pandas`** — tabular data in/out: read a sheet into a DataFrame, analyse, write it back. Best when the file *is* a table.
- **`openpyxl`** — the cell-level engine: formatting, formulas, multiple sheets, styles, charts, precise edits. Best when you need control over the workbook, not just the data. (pandas uses openpyxl underneath for `.xlsx`.)

Install: `pip install openpyxl pandas`.

## Read Tabular Data (pandas)

```python
import pandas as pd
df = pd.read_excel("data.xlsx", sheet_name="Sales")      # sheet_name=None -> dict of all sheets
all_sheets = pd.read_excel("data.xlsx", sheet_name=None)  # {name: DataFrame}
```

- `read_excel` reads *values*, not formulas. A cell holding `=A1+B1` returns its last-computed value (or `NaN` if the file was never opened in Excel to compute it).
- Pass `dtype=str` to stop pandas coercing ID columns / zip codes to floats and dropping leading zeros.
- `header=` and `skiprows=` handle title rows above the real header.

## Read at the Cell Level (openpyxl)

```python
from openpyxl import load_workbook
wb = load_workbook("data.xlsx", data_only=True)   # data_only=True -> cached values, not formula strings
ws = wb["Sales"]
value = ws["B2"].value
for row in ws.iter_rows(min_row=2, values_only=True):
    ...
print(ws.max_row, ws.max_column)
```

- `data_only=True` returns the **cached** result of formulas — it is only populated if the file was saved by a spreadsheet app. openpyxl does **not** evaluate formulas itself.
- `data_only=False` (default) returns the formula string (`"=SUM(A1:A9)"`).

## Write Tabular Data (pandas)

```python
with pd.ExcelWriter("out.xlsx", engine="openpyxl") as writer:
    sales_df.to_excel(writer, sheet_name="Sales", index=False)
    costs_df.to_excel(writer, sheet_name="Costs", index=False)
```

Use `ExcelWriter` (not repeated `to_excel`) to put multiple DataFrames in one file. Set `index=False` unless the index is meaningful.

## Build / Edit a Workbook (openpyxl)

```python
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter

wb = Workbook()
ws = wb.active
ws.title = "Report"
ws.append(["Metric", "Value"])                 # append a row
ws["A2"], ws["B2"] = "Revenue", 1_200_000
ws["B3"] = "=SUM(B2:B2)"                        # formulas are written as strings

# Formatting
ws["A1"].font = Font(bold=True)
ws["A1"].fill = PatternFill("solid", fgColor="DDDDDD")
ws["B2"].number_format = "#,##0"
ws.column_dimensions["A"].width = 24
ws.freeze_panes = "A2"                          # freeze header row
wb.save("report.xlsx")
```

- Rows and columns are **1-indexed**. `ws.cell(row=1, column=1)` is A1; `get_column_letter(27)` -> `"AA"`.
- Formulas are stored as strings; openpyxl never computes them. The result appears only when a spreadsheet app opens and recalculates the file.
- `number_format` controls display (`"0.00%"`, `"$#,##0.00"`, `"yyyy-mm-dd"`) without changing the stored value.

## When to Use Which

| Task | Use |
|------|-----|
| Load a table, compute, save it back | pandas |
| Preserve/apply cell formatting, styles, merged cells | openpyxl |
| Multiple sheets with formulas and layout | openpyxl |
| Quick stats / joins / pivots on the data | pandas (read), openpyxl (write if styling needed) |
| Append rows to an existing styled template | openpyxl (`load_workbook` then `append`) |

## Gotchas

- Neither library evaluates formulas. If you write `=SUM(...)` and never open the file in Excel/LibreOffice, `data_only` reads return `None`. Compute in Python and write the value if a headless consumer needs it.
- `load_workbook` then `save` **drops** features openpyxl does not model (some charts, VBA macros unless `keep_vba=True`, certain conditional formats). Do not round-trip a complex workbook you cannot afford to degrade.
- Large sheets: use `load_workbook(..., read_only=True)` and `Workbook(write_only=True)` for streaming to avoid loading everything into memory.
- Dates read back as `datetime`; Excel's 1900 leap-year quirk is handled by both libraries — do not adjust manually.
- Merged cells: only the top-left cell holds the value; the rest read as `None`.
