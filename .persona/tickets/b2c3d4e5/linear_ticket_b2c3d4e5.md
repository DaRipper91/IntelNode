---
id: b2c3d4e5
title: "Implement PRoot Command Builder and Atomic Extraction"
status: "Ready for Dev"
priority: High
order: 30
created: 2026-03-08
updated: 2026-03-08
links:
  - url: ../linear_ticket_parent.md
    title: Parent Ticket
---

# Description

## Problem to solve
The `proot` command is currently a single, massive hardcoded string, making it error-prone and hard to modify. Additionally, rootfs extraction is non-atomic, which can lead to filesystem corruption if the process is interrupted.

## Solution
Implement a `ProotCommandBuilder` class to dynamically construct the command and refactor the extraction logic to use a temporary staging directory for atomic setup.

## Implementation Details
- Create `ProotCommandBuilder` in `lib/models.dart` or a new file.
- Refactor `Workflow.boot` to use the builder.
- Modify `Workflow.initForFirstTime` to extract to `containers/0_tmp` and rename to `containers/0` upon success.
