# PromptVault JSON Format (version 1)

PromptVault exports, imports, and backs up prompts as plain UTF-8 JSON so your data is never
locked in. The same format is used for **Export**, **Import**, and **Back Up / Restore**.

## Full archive

```json
{
  "format": "promptvault.archive",
  "version": 1,
  "exportedAt": "2026-11-27T10:15:00Z",
  "generator": "PromptVault 1.0",
  "folders": [
    { "id": "6F1C…", "name": "Coding", "symbol": "chevron.left.forwardslash.chevron.right", "parentId": null, "sortIndex": 0 },
    { "id": "9A2B…", "name": "Code Review", "symbol": "ladybug", "parentId": "6F1C…", "sortIndex": 0 }
  ],
  "prompts": [
    {
      "id": "1D4E…",
      "title": "Thorough Code Review",
      "description": "Structured review covering bugs, performance, readability, and security.",
      "content": "Review the following {{language}} code…\n\n{{code}}",
      "folderId": "9A2B…",
      "folder": "Coding / Code Review",
      "tags": ["review", "quality"],
      "isFavorite": true,
      "isTemplate": false,
      "variables": [
        { "name": "language", "defaultValue": "Swift", "description": "", "isRequired": true },
        { "name": "code", "defaultValue": "", "description": "Paste the code to review", "isRequired": true }
      ],
      "createdAt": "2026-11-01T09:00:00Z",
      "updatedAt": "2026-11-20T16:42:10Z",
      "usageCount": 12,
      "lastUsedAt": "2026-11-26T08:03:51Z",
      "versions": [
        { "id": "C0FF…", "title": "Code Review", "description": "", "content": "Review this code…", "variables": [], "savedAt": "2026-11-10T12:00:00Z" }
      ]
    }
  ]
}
```

### Top level

| Field | Type | Notes |
|---|---|---|
| `format` | string | Always `"promptvault.archive"`. |
| `version` | integer | Format version. Files with a newer version than the app supports are rejected rather than half-imported. |
| `exportedAt` | ISO 8601 date | When the file was written. |
| `generator` | string? | App name and version that wrote the file. |
| `folders` | array | Flattened folder tree; parents are listed before children. |
| `prompts` | array | The prompts. |

### Folder

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Stable identifier (generated if missing). |
| `name` | string | **Required.** |
| `symbol` | string | SF Symbol name. Default `"folder"`. |
| `parentId` | UUID? | Parent folder, or `null` for top level. |
| `sortIndex` | integer | Order among siblings. Default `0`. |

### Prompt

| Field | Type | Default | Notes |
|---|---|---|---|
| `id` | UUID? | new UUID | Used to match prompts when re-importing. |
| `title` | string | first line of `content` | Alias: `name`. |
| `content` | string | `""` | The prompt text. Aliases: `prompt`, `text`. A prompt needs a title or content. |
| `description` | string | `""` | Short description. Alias: `summary`. |
| `folderId` | UUID? | `null` | Refers to `folders[].id`. |
| `folder` | string? | `null` | Folder path such as `"Coding / Code Review"`. Used when `folderId` is missing or unknown; missing folders are created. |
| `tags` | [string] | `[]` | A leading `#` is stripped, and spaces become `-`. |
| `isFavorite` | bool | `false` | |
| `isTemplate` | bool | `false` | |
| `variables` | [Variable] | `[]` | Metadata for `{{placeholders}}` in `content`. |
| `createdAt` / `updatedAt` / `lastUsedAt` | ISO 8601 date? | now / createdAt / null | Also accepts `YYYY-MM-DD` dates and Unix timestamps. |
| `usageCount` | integer | `0` | |
| `versions` | [Version] | `[]` | Previous versions, newest first. |

### Variable

| Field | Type | Default |
|---|---|---|
| `name` | string | **required**; must match a `{{name}}` in the content |
| `defaultValue` | string | `""` |
| `description` | string | `""` (shown as a hint in the fill-in form) |
| `isRequired` | bool | `true` |

## Minimal hand-written files

Import also accepts a **bare array** or a **single object**. This is enough:

```json
[
  { "title": "Tweet Thread", "content": "Turn this into a 5-tweet thread:\n\n{{clipboard}}", "folder": "Writing / Social" },
  { "name": "Rubber Duck", "prompt": "Ask me questions until I find the bug myself.", "tags": ["#debugging"] }
]
```

## Placeholder syntax

| Syntax | Meaning |
|---|---|
| `{{name}}` | A fill-in variable. Names start with a letter or `_` and may contain letters, digits, spaces, `_`, `-`, `.`. |
| `{{clipboard}}` | The clipboard contents when the prompt is used. |
| `{{date}}`, `{{time}}`, `{{datetime}}`, `{{weekday}}`, `{{year}}` | The current date/time in your locale. |
| `\{{name}}` | An escaped placeholder, copied literally as `{{name}}` (useful for Handlebars/Mustache). |

## Import rules

- **Merge (Import):** prompts whose `id` already exists are updated only if the imported
  `updatedAt` is newer. The replaced text is kept as a version, so nothing is lost. Prompts
  without an `id` are skipped when one with the same title and content already exists, so
  importing the same file twice is safe. Folders are matched by `id`, then by name under
  the same parent.
- **Replace (Restore from Backup):** the library is replaced by the archive. PromptVault first
  writes a backup of the current library.
