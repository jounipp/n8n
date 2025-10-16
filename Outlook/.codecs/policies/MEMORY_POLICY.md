# MEMORY POLICY
max_context_tokens: 2000
reserve_completion_tokens: 1500
include_sources:
  - Outlook/.codecs/docs/ARCHITECTURE.md
  - Outlook/.codecs/docs/INSTRUCTIONS.md
  - Outlook/.codecs/docs/CONVENTIONS.md
  - Outlook/.codecs/docs/WORKFLOWS.md
eviction:
  - drop_empty: true
  - prefer_latest: true
write_rules:
  - no_new_files: true
  - only_edit_in_dot_codecs: true
