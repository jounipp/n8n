# Repository Guidelines

## Project Structure & Module Organization
- `n8n/wf/n8n_outlook/*.json` — n8n workflows for Outlook processing.
- `n8n/wf/n8n_outlook/db_outlook/` — SQL utilities and diagrams (e.g., `*_rows.sql`, `wf_logic.png`).
- `n8n/wf/n8n_outlook/build_batch_prompt_cache_HYBRID.js` — helper Node.js script.
- `n8n/wf/n8n_outlook/read_doc.py` — small Python helper.
- `Schema_outlook.sql` and Markdown docs provide schema and integration notes.

## Build, Test, and Development Commands
- No global build step; scripts are standalone.
- Run Node script: `node n8n/wf/n8n_outlook/build_batch_prompt_cache_HYBRID.js`
- Run Python helper: `python n8n/wf/n8n_outlook/read_doc.py`
- SQL: execute in a non‑prod database via your preferred client (wrap tests in transactions).
- Workflows: import/export `.json` via n8n Editor UI; verify nodes, credentials, and sample runs.

## Coding Style & Naming Conventions
- Workflows: use descriptive names prefixed by domain, e.g., `Outlook_*`. Keep node names actionable.
- JavaScript: 2‑space indent, camelCase, single quotes; prefer small pure functions. If available, format with Prettier.
- Python: 4‑space indent, snake_case, docstrings for scripts; keep side effects in `if __name__ == "__main__":`.
- SQL: UPPERCASE keywords, snake_case identifiers; keep files as `verb_object.sql` (e.g., `classification_rules_rows.sql`).

## Testing Guidelines
- Workflows: test with representative inputs in n8n, disable external side‑effects when possible; export sanitized flows (no credentials).
- Scripts: add dry‑run flags or sample inputs; log key actions. Validate against a small sample before bulk runs.
- SQL: run on staging; use `BEGIN; ... ROLLBACK;` during tests; add `LIMIT` for previews.

## Commit & Pull Request Guidelines
- Commits: follow Conventional Commits where practical, e.g., `feat(workflow): add Outlook sync step`, `fix(sql): correct rules snapshot`.
- PRs: include purpose, scope, before/after notes, screenshots of workflow diffs/executions, and DB impact (if SQL changes). Link related issues or tasks.

## Security & Configuration Tips
- Never commit secrets. Use n8n credentials store and environment variables. Sanitize exported workflows.
- Keep large binaries out of version control; prefer links or generated assets.

## Agent‑Specific Instructions
- Scope: this file applies to the entire repo. Keep changes minimal and focused; do not rename/move workflow files without discussion.
- Prefer adding new flows over overwriting existing ones; update docs when behavior changes.

