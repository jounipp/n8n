# Claude Code Template

Template for creating new Claude Code-enabled projects.

This template is based on the Outlook project structure.

## Usage
```powershell
# 1. Create new project
cd C:\Coding\Github\n8n
mkdir NewProject

# 2. Copy template
Copy-Item -Recurse _templates\claude_skeleton\.claude NewProject\

# 3. Customize ALL files for your project:
code NewProject\.claude\instructions.md
code NewProject\.claude\architecture.md
code NewProject\.claude\workflows.md

# Replace "Outlook" references with your project name
# Update architecture, workflows, etc.
```

## What to customize:

When creating a new project, update these files:

1. **instructions.md**
   - Project name and description
   - Prerequisites
   - Setup instructions
   
2. **architecture.md**
   - System components
   - Data flow
   - API integrations

3. **workflows.md**
   - Your actual workflows
   - Execution patterns

4. **conventions.md**
   - Project-specific coding standards (if any)

5. **changelog.md**
   - Start fresh or keep template format

## Note

The template contains Outlook project examples. 
Use them as reference and replace with your own content.