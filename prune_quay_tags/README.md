# Quay Tag Pruner

A simple Bash script to list and delete [Quay.io](https://quay.io) repository image tags matching a given pattern that are older than a specified cutoff date. Supports dry-run mode to preview which tags *would* be deleted without actually removing them.

---

## Table of Contents

- [Features](#features)  
- [Prerequisites](#prerequisites)  
- [Installation](#installation)  
- [Usage](#usage)  
  - [Required Arguments](#required-arguments)  
  - [Date Filters](#date-filters)  
  - [Token Authorization](#token-authorization)
  - [Dry-Run Mode](#dry-run-mode)  
- [Examples](#examples)  
- [Authentication](#authentication)  
- [Script Output](#script-output)  
- [Exit Codes](#exit-codes)  
- [Deleting Tags](#deleting-tags)
- [License](#license)

---
## Features

- **Filter** tags by name.  
- **Filter** tags by age: either “N days old” or “before a specific date”.  
- **Dry‑run** mode to preview which tags would be deleted.  
- **Automatic** login detection via Docker, Podman, or Skopeo credential files.  
- **Private** repositories supported via token authorization to get tags.
- **Pagination** support for repositories with many tags.  

---

## Prerequisites

Make sure the following commands are installed and available in your `PATH`:

- [skopeo](https://github.com/containers/skopeo)  
- [jq](https://stedolan.github.io/jq/)  
- `curl`  
- GNU `date` (for `-d` parsing)  

---

## Usage
```
./quay-tag-pruner.sh \
  --repo    <org/repo> \
  --filter  <string> \
  [--days N | --before YYYY-MM-DD] \
  [--token <string>] \
  [--dry-run]
```

### Required Arguments

* `--repo <org/repo>`  
Quay repository path (e.g. myorg/myproject).

* `--filter <string>`  
Regular expression to match tag names (e.g. ^on-pr-).

### Date Filters
(one required)
* `--days N`  
Delete tags older than N days.

* `--before YYYY-MM-DD`  
Delete tags modified before the given date.

### Token Authorization
* `--token <string>`  
A token string, used when accessing private repositories.  
**Not** required for publicly accessible repositories.

### Dry Run Mode
* `--dry-run`  
Only print which tags would be deleted; do not perform any deletions.

## Examples

**Preview** deletion of tags starting with on-pr- older than 30 days:

```
./quay-tag-pruner.sh \
  --repo myorg/myrepo \
  --filter 'on-pr-' \
  --days 30 \
  --dry-run
```

**Delete** tags matching release- modified before April 1, 2025:

```
./quay-tag-pruner.sh \
  --repo myorg/myrepo \
  --filter 'release-' \
  --before 2025-04-01
```

**Delete** tags matching release- modified before April 1, 2025, from a private repo

```
./quay-tag-pruner.sh \
  --repo myorg/myrepo \
  --filter 'release-' \
  --before 2025-04-01 \
  --token 'THIS0IS1A3FAKE4TOKEN'
```

## Authentication
The script checks for existing Quay.io credentials in:

1. Docker (`~/.docker/config.json`)
2. Podman/containers (`~/.config/containers/auth.json`)
3. Skopeo runtime (`$XDG_RUNTIME_DIR/containers/auth.json`)

If no credentials are found, log in with one of:

**Docker**
```
$ docker login quay.io
```
**Podman**
```
$ podman login quay.io
```
**Skopeo**
```
$ skopeo login quay.io
```

## Script Output
✅ deleted — tag deleted successfully  
❌ failed — deletion attempted but failed  
💡 would be deleted — in dry‑run mode  
🔢 Total matching tags found  
✅ Total tags deleted

Each line is formatted as:
```
<tag-name> <YYYY-MM-DD HH:MM:SS TZ> <status>
```

## Exit Codes
* 0 — Successful completion
* 1 — Missing required argument or dependency, or authentication failure
* \>1 — Unexpected error during execution

## Deleting tags
In Quay, when you delete a tag (whether via the API, the UI, or using a tool such as this), you are only removing the reference (the tag) to an image manifest. The underlying manifest and layer blobs remain in the registry until Quay’s garbage‐collection process reclaims them.

> **NOTE**: What follows are few important notes regarding this script and deleting tags.

* **Tag removal is immediate**  
Once the DELETE call succeeds, the tag no longer appears in the tag listing and you can’t pull it by name anymore.

* **Manifests live on until unreferenced**  
If the deleted tag was the last one pointing at a given manifest, it becomes “orphaned.” Quay does not immediately purge the orphaned data.

* **Reversion window (“time machine”)**  
By default Quay holds deleted and expired tags (and their data) for 14 days, during which you can restore them via the UI or API (assuming your administrator hasn’t shortened that window).

* **Asynchronous garbage collection**  
Quay runs a background GC job that scans for unreferenced manifests and then physically deletes their blobs from storage.

**So, in practice**:
* DELETE tag → tag disappears immediately.
* Quay GC (within its next cycle) → orphaned manifests and layers get cleaned up.
* Before GC completes → you can still “undelete” or revert a tag if needed.

## License
This project is released under the Apache License, Version 2.0.