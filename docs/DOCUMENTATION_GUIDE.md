# Documentation Guide

This guide is the repository-wide standard for writing, changing, and reviewing documentation. It keeps guidance accurate, useful to its intended audience, and maintainable as the project evolves.

## Documentation Principles

### Write for the document's audience and purpose

Place each claim in the document that owns its subject. Keep user instructions in user-facing documentation, implemented behavior and requirements in specifications, and contributor procedures in contributor guidance. When another document needs context, summarize it briefly and link to the canonical owner instead of repeating its normative definition.

Use clear, general wording that remains true across incidental fixture, environment, and configuration changes. Include a specific example only when it clarifies a principle, and identify it as an example rather than a requirement.

### Distinguish the status of claims

State whether a claim describes:

- current implemented behavior;
- a requirement or invariant;
- planned or incomplete work;
- an illustrative example; or
- historical context.

Do not present plans as current behavior, examples as policy, or historical decisions as requirements. Public documentation is not the project roadmap. Mention desired but unimplemented behavior only when readers need the distinction, and label it clearly as future work.

### Base implementation claims on evidence

Verify technical claims against the current repository. When a claim depends on implementation details, inspect the complete production path, including the relevant source, configuration, automation, packaging, and entry points rather than inferring behavior from tests or isolated fixtures. Tests can corroborate a claim but do not by themselves establish production behavior.

Use published artifacts as evidence for claims about released binaries. If evidence is incomplete, narrow or qualify the claim and identify what still needs verification. Keep documentation aligned with both production behavior and the tests that define supported expectations.

### Preserve meaning and ownership

Make the smallest coherent change that satisfies the documentation goal. Preserve useful explanations and essential security and risk disclosures unless the task explicitly changes them. Move or link content when ownership is wrong; do not silently discard it.

Treat incidental inaccuracies outside the requested scope as separate findings or follow-up work. Correct them in the same change only when they block an accurate result or the task explicitly includes them.

### Keep navigation reliable

Use descriptive relative links for repository content. Link to the canonical source at the point where a reader needs detail, keep headings stable when they serve as link targets, and verify every added or changed link.

### Use links for navigation and deeper context

Use clear local prose and do not hyperlink terminology merely to definitions. Reserve links for navigation, source artifacts, repository or release resources, and genuinely deeper topical sections. Keep each sentence understandable on its own, and link only when following the link gives the reader useful additional context.

## Documentation Review

### Scope

Review the changed documentation and the canonical sources needed to validate its material claims. Follow links and production paths far enough to assess accuracy and ownership, while treating unrelated pre-existing issues as outside the review unless they prevent a correct change.

### Method

Compare the change with its stated purpose, intended audience, canonical owners, and current repository evidence. Check links and inspect the diff for lost meaning, duplicated policy, unsupported claims, and accidental scope expansion. Verify production and test alignment when the change describes implemented behavior.

### Goal

The goal is an accurate, navigable, durable change that preserves important information and leaves each topic with a clear canonical owner. Review should help the author reach that outcome, not merely describe the diff.

### Standard for findings

Raise a finding when the change has a material problem with:

- correctness or evidentiary support;
- preservation of useful content or meaning;
- canonical ownership or duplicated normative guidance;
- audience or document-purpose boundaries;
- security or essential risk disclosure;
- the status of planned work;
- maintainability, including wording coupled to incidental configuration;
- alignment between documented behavior, production paths, tests, and release artifacts; or
- scope control, including unrelated changes that increase risk.

Do not raise findings for cosmetic preferences without a material readability or consistency impact, unrelated pre-existing issues, unsupported speculation, unrelated redesign proposals, restatements of the diff, or non-material suggestions.

An actionable finding identifies the affected location, the material impact, the evidence or violated principle, and the smallest reasonable correction. State uncertainty explicitly and describe how to verify it; do not present a hypothesis as a defect.
