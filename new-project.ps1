# new-project.ps1
# Creates a new n8n subproject with Claude Code context

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName
)

# Värit outputille
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Error { Write-Host $args -ForegroundColor Red }

# Tarkista että ollaan oikeassa hakemistossa
$currentPath = Get-Location
if ($currentPath.Path -notlike "*\n8n") {
    Write-Error "ERROR: Aja tämä skripti n8n-kansiossa!"
    Write-Info "Usage: cd C:\Coding\Github\n8n"
    Write-Info "       .\new-project.ps1 ProjectName"
    exit 1
}

# Tarkista että template on olemassa
if (-not (Test-Path "_templates\claude_skeleton\.claude")) {
    Write-Error "ERROR: Template ei löydy: _templates\claude_skeleton\.claude"
    exit 1
}

# Tarkista että projekti ei ole jo olemassa
if (Test-Path $ProjectName) {
    Write-Error "ERROR: Projekti '$ProjectName' on jo olemassa!"
    exit 1
}

Write-Info "==================================="
Write-Info "Creating new project: $ProjectName"
Write-Info "==================================="

# 1. Luo projektikansio
Write-Info "`n[1/5] Creating project folder..."
New-Item -ItemType Directory -Path $ProjectName | Out-Null
Write-Success "✓ Created: $ProjectName/"

# 2. Kopioi Claude Code template
Write-Info "`n[2/5] Copying Claude Code template..."
Copy-Item -Recurse "_templates\claude_skeleton\.claude" "$ProjectName\"
Write-Success "✓ Copied: $ProjectName\.claude/"

# 3. Luo README.md
Write-Info "`n[3/5] Creating README.md..."
$readmeContent = @"
# $ProjectName

[Brief description of what this project does]

## Prerequisites

- [List required tools and services]

## Setup

[Setup instructions]

## Usage

[How to use this project]

## Documentation

See `.claude/` directory for detailed documentation:
- \`architecture.md\` - System design
- \`instructions.md\` - Getting started guide
- \`workflows.md\` - Workflow documentation
- \`conventions.md\` - Coding standards
"@

$readmeContent | Out-File "$ProjectName\README.md" -Encoding UTF8
Write-Success "✓ Created: $ProjectName\README.md"

# 4. Luo .gitkeep alikansioille (jos haluat)
Write-Info "`n[4/5] Creating project structure..."
New-Item -ItemType Directory -Path "$ProjectName\scripts" -Force | Out-Null
New-Item -ItemType Directory -Path "$ProjectName\docs" -Force | Out-Null
Write-Success "✓ Created: $ProjectName\scripts/, $ProjectName\docs/"

# 5. Avaa VS Code
Write-Info "`n[5/5] Opening in VS Code..."
code "$ProjectName"
Write-Success "✓ Opened VS Code"

# Näytä seuraavat vaiheet
Write-Info "`n==================================="
Write-Success "✓ Project created successfully!"
Write-Info "==================================="
Write-Info "`nNext steps:"
Write-Info "1. Customize .claude/instructions.md (replace 'Outlook' references)"
Write-Info "2. Update .claude/architecture.md with your system design"
Write-Info "3. Update README.md with project description"
Write-Info "4. Start coding!"
Write-Info "`nTo commit:"
Write-Info "   cd $ProjectName"
Write-Info "   git add ."
Write-Info "   git commit -m 'feat: initialize $ProjectName project'"
Write-Info "   git push"