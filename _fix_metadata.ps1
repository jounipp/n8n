$ErrorActionPreference = 'Stop'

function Ensure-Property {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$Value
  )
  $hasProp = $Object.PSObject.Properties.Name -contains $Name
  if (-not $hasProp) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    return $true
  }
  $cur = $Object.$Name
  if ($null -eq $cur -or ("$cur").Trim().Length -eq 0) {
    $Object.$Name = $Value
    return $true
  }
  return $false
}

$root = $PSScriptRoot
$files = Get-ChildItem -Path $root -Recurse -Filter *.json -File

$changes = @()

foreach ($f in $files) {
  try {
    $raw = Get-Content -Raw -Path $f.FullName
    $wf = $raw | ConvertFrom-Json
    if ($wf -isnot [pscustomobject]) { throw "Unexpected JSON root (not object) in $($f.FullName)" }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)

    $changed = $false
    $changed = (Ensure-Property -Object $wf -Name 'name' -Value $baseName) -or $changed
    $changed = (Ensure-Property -Object $wf -Name 'active' -Value $false) -or $changed

    $json = $wf | ConvertTo-Json -Depth 100

    $target = $f.FullName
    if ($f.Name -eq 'Outlook_subscriotion.json') {
      $newName = 'Outlook_subscription.json'
      $target = Join-Path $f.DirectoryName $newName
      $changes += "Rename: $($f.Name) -> $newName"
    }

    if ($changed -or ($target -ne $f.FullName)) {
      $json | Set-Content -Path $target -Encoding UTF8
      if ($target -ne $f.FullName) { Remove-Item -Path $f.FullName -Force }
      $changes += "Updated: $target"
    }
  }
  catch {
    $changes += "Error: $($f.FullName): $($_.Exception.Message)"
  }
}

$changes | ForEach-Object { $_ }

