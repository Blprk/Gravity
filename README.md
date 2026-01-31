# 🌌 Gravity Rename
### *Atomic. Parallel. Paranoid.*

Gravity is a professional-grade batch renaming suite for macOS, engineered in Rust and Swift for users who demand absolute data integrity and blazing performance.

---

## 🚀 Key Pillars

### ⚡ Blazing Fast Parallelism
Powered by a Work-Stealing Parallel Engine (via Rayon), Gravity saturates all CPU cores to apply complex rule pipelines to tens of thousands of files simultaneously. Previews are generated with sub-150ms latency.

### 🛡️ Paranoid Safety
- **Two-Phase Atomic Commit**: Gravity never renames in-place. It calculates the entire transaction, validates it, then executes.
- **Rollback Journals**: Every operation generates a cryptographically unique journal. If a rename fails halfway (e.g., unplugged drive), the engine can roll back to the original state.
- **Conflict Pre-emption**: Built-in detection for:
  - Filename collisions.
  - Case-sensitivity mismatches (APFS/HFS).
  - OS Reserved names.
  - Source file movements.

### 📸 Pro Metadata Support
- **Full EXIF Integration**: Extract `DateTimeOriginal` from photos for perfect chronological sorting.
- **Filesystem Precision**: Use creation or modification timestamps with customizable formatting.

---

## 🛠 Project Architecture

| Component | Responsibility | Tech Stack |
|:---|:---|:---|
| **`gravity-core`** | High-performance rename logic & transaction engine. | Rust + Rayon |
| **`gravity-cli`** | Developer-focused interface for CI/CD and terminal workflows. | Rust + Clap |
| **`gui`** | Premium macOS experience with live-updating pipeline editor. | SwiftUI + Parallel Tasks |

---

## 📦 Build & Installation

### 1. Build the Engine
```bash
cargo build --release
```
The CLI binary will be located at `./target/release/gravity-cli`.

### 2. Package the macOS App
Run our automated packaging script to bundle the Rust engine inside the Swift app:
```bash
bash package_app.sh
```
This creates a standalone **`Gravity.app`** on your Desktop with a custom 3D icon.

---

## ⌨️ CLI Power Usage

**Preview Changes:**
```bash
gravity-cli preview --rules rules.json *.jpg
```

**Execute Atomic Rename:**
```bash
gravity-cli commit --rules rules.json *.jpg --journal-dir ./logs
```

**Undo a Previous Session:**
```bash
gravity-cli undo --journal ./logs/journal-5aec2486.json
```

---

## 🎨 Global Ruleset Support
Gravity supports a rich pipeline of transformations:
- **Regex Replace**: Full PCRE-style pattern matching.
- **Counters**: Interactive padding and step-size control.
- **Date Insertion**: EXIF and Filesystem metadata.
- **Case Control**: Title Case, UPPERCASE, and lowercase.
- **Strip/Literal**: Clean up prefixes, suffixes, or insert text at specific indices.

---

## 🤝 Contributing
Gravity is built for the "Elite Paranoid" workflow. Pull requests for new metadata sources (ID3, Video bits) are welcome.

*Designed for the 2026-Gravity Project. Developed by @BLPRK.*
