# 📋 Gravity Rule Documentation

Gravity uses a sequence-based pipeline. Rules are applied in the order they appear.

| Rule | Description | Parameters |
|:---|:---|:---|
| **Strip Prefix** | Removes specific text from the start of the filename. | `prefix` |
| **Strip Suffix** | Removes specific text from the end of the filename. | `suffix` |
| **Regex Replace** | Powerful pattern-based replacement. | `pattern`, `replacement` |
| **Literal** | Inserts specific text at a chosen position. | `text`, `position` (Start, End, Index) |
| **Counter** | Appends an auto-incrementing number. | `start`, `step`, `padding`, `separator` |
| **Case Transform** | Changes the capitalization of the text. | `transform` (lower, UPPER, Title) |
| **Date Insertion** | Inserts timestamps into the filename. | `format`, `source` (Current, Created, Modified, EXIF) |

---
*Pro Tip: Use 'Regex Replace -> \d+' with an empty replacement to quickly clean up randomized file numbers.*
