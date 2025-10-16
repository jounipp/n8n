$ErrorActionPreference = 'Stop'

$files = Get-ChildItem -Path (Join-Path $PSScriptRoot '.') -Recurse -Filter *.json -File

foreach ($f in $files) {
  try {
    $raw = Get-Content -Raw -Path $f.FullName
    $wf = $raw | ConvertFrom-Json

    $name = $wf.name
    $active = $wf.active
    $nodeCount = ($wf.nodes | Measure-Object).Count

    $types = @()
    if ($wf.nodes) { $types = $wf.nodes | ForEach-Object { $_.type } | Sort-Object -Unique }
    $triggers = $types | Where-Object { $_ -match 'trigger|webhook|cron' }

    $credentials = @()
    if ($wf.nodes) {
      $wf.nodes | ForEach-Object {
        if ($_.credentials) {
          $_.credentials.PSObject.Properties | ForEach-Object {
            $credObj = $_.Value
            if ($credObj -and $credObj.name) { $credentials += $credObj.name }
          }
        }
      }
    }
    $credentials = $credentials | Sort-Object -Unique

    $urls = @()
    if ($wf.nodes) {
      $wf.nodes | ForEach-Object {
        if ($_.type -match 'httpRequest') {
          $u = $_.parameters.url
          if ($u) { $urls += $u }
        }
        if ($_.type -match 'webhook') {
          $p = $_.parameters.path
          if ($p) { $urls += ('/webhook/' + $p) }
        }
      }
    }
    $urls = $urls | Sort-Object -Unique

    $hasEnv = [regex]::IsMatch($raw, '\{\{\s*\$env\.')

    [pscustomobject]@{
      File        = $f.FullName
      Name        = $name
      Active      = $active
      Nodes       = $nodeCount
      Triggers    = ($triggers -join ', ')
      Credentials = ($credentials -join ', ')
      Endpoints   = ($urls -join ', ')
      UsesEnv     = $hasEnv
    } | Format-List
    "`n"
  }
  catch {
    [pscustomobject]@{
      File  = $f.FullName
      Error = $_.Exception.Message
    } | Format-List
    "`n"
  }
}

