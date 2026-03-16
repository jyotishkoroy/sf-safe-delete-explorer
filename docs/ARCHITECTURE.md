# Architecture

## Overview

SafeDelete Explorer uses a single Apex service and a single Lightning Web Component bundle.

```text
LWC (safeDeleteExplorer)
    -> Apex preview service
        -> Schema describe
        -> Custom Metadata rule lookup
        -> guarded count queries
    -> render summary cards, badges, table, and acknowledgments
    -> optional UI API delete action
```

## Key decisions

### 1. No custom objects

The app does not persist preview results or risk settings in custom objects. This avoids unnecessary schema footprint and keeps deployment simple.

### 2. Custom Metadata instead of hard-coded per-org branching

`SafeDeleteRule__mdt` is used for optional tuning. It is deployable, package-friendly, and admin-readable.

### 3. Query-budget guardrail

Counting every child relationship on every object can exceed governor limits in large orgs. The service prioritizes higher-risk relationships first and marks lower-priority rows as not evaluated when the query budget is exhausted.

### 4. Delete is opt-in

The component is useful even in preview-only mode. Delete execution is off by default to keep initial deployment conservative.

## Risk scoring inputs

The app combines:

- cascade-delete metadata
- restricted-delete metadata
- rule-based overrides
- heuristics for files, approvals, activities, and junction-like children
- related-record counts when available

## Limits and trade-offs

- Counts are relationship-level, not field-level impact graphs.
- Some special relationships may be inaccessible or non-queryable depending on org features and permissions.
- The app is intentionally metadata-first and not a full dependency graph engine.
