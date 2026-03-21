# Sagapi Gamedata - Decoded Assets

> **NOTE:** This branch contains the automatically extracted and decoded Arknights game data. It is an autonomous deployment branch maintained entirely by the GitHub Actions pipeline from the `main` branch.

## Output Structure

The data is strictly organized by regional game servers:

```text
.
├── cn/               # Chinese Server (not implemented yet)
├── en/               # Global/English Server
├── jp/               # Japanese Server
├── kr/               # Korean Server
└── tw/               # Taiwanese Server
```

### Directory Contents

Inside each server directory, the processed assets are categorized as follows:

* **`*_table.json` / `*_data.json`**: Standard game database files (e.g., `character_table.json`, `skill_table.json`).
* **`levels/`**: Directory containing stage layouts, enemy wave timings, and map logic.

## Update Frequency

This branch is fully synchronized with the official game servers and updates autonomously:
* **App Updates:** Triggers immediately upon structural schema changes.
* **Hot Updates:** Runs on a scheduled basis (4~ hours) to fetch minor content patches.