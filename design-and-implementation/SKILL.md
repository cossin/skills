---
name: design-and-implementation
description: Use for software design, implementation, technical choices, and review recommendations. Apply business invariants, existing-system constraints, and engineering safeguards in proportion to risk.
---

# Design and implementation

- Balance business goals, correctness, availability, maintainability, and total cost. Match design depth to risk: complete small changes directly; explain key tradeoffs before substantial changes.
- Understand the existing system first. Prefer existing capabilities, mature components, and established practices. Consult authoritative sources for important or unfamiliar decisions; explain applicability and distinguish verified facts from assumptions.
- Define business invariants and acceptable delays, deviations, and failure states. Proceed with reasonable assumptions for reversible, low-risk decisions; clarify uncertainties that materially change business semantics or consequences.
- Choose the simplest solution that meets known requirements. Add dependencies, abstractions, or infrastructure only when their benefits justify implementation, operating, and maintenance costs.
- Limit consistency and atomicity promises to what the underlying mechanisms actually guarantee. Handle uncertainty across boundaries through explicit states, recovery, or coordination; do not assume global, immediate, absolute consistency is required or achievable.
- Keep transactions, locks, and critical paths short and minimize coupling to external dependencies. Add checks or coordination only when they strengthen actual guarantees; avoid redundant checks that merely add latency or failure points.
- Base restrictions, thresholds, and blocking behavior on business rules, security requirements, platform limits, or measured evidence. Do not turn speculation or arbitrary values into business constraints. Account for false positives, blocked legitimate work, and availability costs.
- Match safeguards to risk. Within required correctness and security boundaries, prefer narrowly scoped, recoverable measures. When blocking is necessary, define its conditions, scope, and recovery path.
- Address relevant timeout, duplicate, concurrency, dependency, and partial-failure risks. Retry only within defined bounds and when repetition is safe. Verify unknown outcomes before retrying; do not suppress failures or report false success.
- When reliable automation is impossible, preserve a traceable pending state and necessary context. Provide a human handling path, a responsible owner, and a recovery procedure. Make alerts actionable and deduplicated, and protect sensitive data; logging alone is not a fallback.
- Validate normal, failure, and recovery paths according to risk, including business invariants and unintended rejection of legitimate work. For significant releases, address monitoring, compatibility, migration, and rollback.
- Report changes, key tradeoffs, actual validation, and remaining limitations concisely. Do not claim unverified capabilities or equate more checks, restrictions, or procedural complexity with quality.

Apply these principles where relevant and proportionate to risk; do not build a complete fault-tolerance framework for every change.
