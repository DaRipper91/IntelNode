---
id: a1b2c3d4
title: "Refactor: Externalize Bootstrap Scripts and Clean Workflow Strings"
status: "Done"
priority: High
order: 20
created: 2026-03-08
updated: 2026-03-08
links:
  - url: ../linear_ticket_parent.md
    title: Parent Ticket
---

# Description

## Problem to solve
`lib/workflow.dart` is cluttered with hardcoded shell strings. Bootstrap scripts are hidden inside `assets/patch.tar.gz`.

## Solution
Move hardcoded logic and scripts into dedicated asset files and refactor Dart code.

## Implementation Details
- Extract `start-arch.sh` and `start-desktop` to `assets/scripts/`.
- Clean up hardcoded strings in `Workflow`.
- Fix `duplicate_ignore` warnings.
