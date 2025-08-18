<#
.SYNOPSIS
  Configure Git line-ending policy from .gitattributes and renormalize.

.DESCRIPTION
  - Reads the repo's root .gitattributes.
  - Detects the last rule for '*' and looks for eol={lf|crlf}.
  - Sets core.eol and core.autocrlf to match:
      eol=lf   -> core.eol=lf   & core.autocrlf=input
      eol=crlf -> core.eol=crlf & core.autocrlf=true
    (If no eol is found, leaves those settings unchanged.)
  - Sets core.safecrlf=true (defensive).
  - Runs: git add --renormalize .
  - Prints a preview of staged files.
  - Exits 0 on success / benign no-op; 1 on real error.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][Alias('Path')]
    [string]$RepoPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Args)
    $out = & git @Args 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "git $($Args -join ' ') failed ($code):`n$out" }
    return $out
}

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git not found on PATH."
    }

    $repoFull = Resolve-Path -LiteralPath $RepoPath
    Push-Location $repoFull
    try {
        $inside = (& git rev-parse --is-inside-work-tree) 2>$null
        if ($LASTEXITCODE -ne 0 -or $inside.Trim() -ne "true") {
            throw "Path '$repoFull' is not inside a git work tree."
        }

        # --- A) Read .gitattributes and set EOL policy ---
        $ga = Join-Path (Get-Location) ".gitattributes"
        if (-not (Test-Path -LiteralPath $ga)) {
            Write-Host "No .gitattributes found. Nothing to configure. Skipping config & renormalize."
        } else {
            Write-Verbose "Reading $ga"
            $lines = Get-Content -LiteralPath $ga -Encoding UTF8

            # Find the *last* '*' rule (closest to end wins)
            $starLine = $null
            for ($i = $lines.Length - 1; $i -ge 0; $i--) {
                $ln = $lines[$i].Trim()
                if ($ln -eq '' -or $ln.StartsWith('#')) { continue }
                $tokens = [System.Text.RegularExpressions.Regex]::Split($ln, '\s+')
                if ($tokens.Count -lt 2) { continue }
                if ($tokens[0] -eq '*') { $starLine = $ln; break }
            }

            $desiredEol  = $null  # 'lf' or 'crlf'
            $desiredAuto = $null  # 'input' or 'true'

            if ($starLine) {
                Write-Verbose "Matched '*' rule: $starLine"
                $attrs = [System.Text.RegularExpressions.Regex]::Split($starLine.Trim(), '\s+')
                $attrTokens = $attrs[1..($attrs.Length-1)]
                foreach ($tok in $attrTokens) {
                    if ($tok -match '^eol=(?<val>lf|crlf)$') {
                        $desiredEol = $Matches['val'].ToLower()
                    }
                }
                if ($desiredEol -eq 'lf')   { $desiredAuto = 'input' }
                if ($desiredEol -eq 'crlf') { $desiredAuto = 'true'  }
            } else {
                Write-Verbose "No '*' rule found; leaving core.eol/autocrlf unchanged."
            }

            # Always set safecrlf=true (defensive)
            $currentSafe = (& git config --get core.safecrlf) 2>$null
            if ($currentSafe -ne 'true') {
                if ($PSCmdlet.ShouldProcess((Get-Location), "git config core.safecrlf true")) {
                    Invoke-Git @('config','core.safecrlf','true') | Out-Null
                }
            } else {
                Write-Verbose "core.safecrlf already 'true'"
            }

            if ($desiredEol) {
                $currentEol  = (& git config --get core.eol) 2>$null
                $currentAuto = (& git config --get core.autocrlf) 2>$null

                if ($currentEol -ne $desiredEol) {
                    if ($PSCmdlet.ShouldProcess((Get-Location), "git config core.eol $desiredEol")) {
                        Invoke-Git @('config','core.eol', $desiredEol) | Out-Null
                    }
                } else {
                    Write-Verbose "core.eol already '$currentEol'"
                }

                if ($desiredAuto -and $currentAuto -ne $desiredAuto) {
                    if ($PSCmdlet.ShouldProcess((Get-Location), "git config core.autocrlf $desiredAuto")) {
                        Invoke-Git @('config','core.autocrlf', $desiredAuto) | Out-Null
                    }
                } else {
                    if ($desiredAuto) { Write-Verbose "core.autocrlf already '$currentAuto'" }
                }
            }
        }

        # --- B) Renormalize to apply attributes ---
        if (Test-Path -LiteralPath $ga) {
            if ($PSCmdlet.ShouldProcess((Get-Location), "git add --renormalize .")) {
                Invoke-Git @('add','--renormalize','.') | Out-Null
            }

            # Refresh index and report staged files
            if ($PSCmdlet.ShouldProcess((Get-Location), "git update-index -q --refresh")) {
                Invoke-Git @('update-index','-q','--refresh') | Out-Null
            }

            $stagedRaw = (& git diff --cached --name-only)
            $stagedList = @()
            if ($stagedRaw) {
                $stagedList = $stagedRaw -split "`r?`n" | Where-Object { $_ -ne '' }
            }

            if (-not $stagedList -or $stagedList.Count -eq 0) {
                Write-Host "Renormalization found no changes. Done."
            } else {
                $count = $stagedList.Count
                $preview = $stagedList | Select-Object -First 50
                Write-Host ("Renormalized files staged ({0} total):" -f $count)
                $preview | ForEach-Object { Write-Host "  $_" }
                if ($count -gt $preview.Count) {
                    Write-Host ("  ... and {0} more." -f ($count - $preview.Count))
                }
                Write-Host "Review and commit when ready."
            }
        }

        $global:LASTEXITCODE = 0
        exit 0
    }
    finally {
        Pop-Location
    }
}
catch {
    $msg = $_.Exception.Message
    if ($msg -match 'NativeCommandError') { $msg = $_.ToString() }
    Write-Host "ERROR: $msg"
    $global:LASTEXITCODE = 1
    exit 1
}
