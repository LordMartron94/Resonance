<#
.SYNOPSIS
  Stage and commit changes in a repo safely (only commits if there are changes).

.EXAMPLES
  # 1) After generating structure:
  .\commit_changes.ps1 -RepoPath "X:\Resonance" -Message "Stage 1: project structure" -Add "."

  # 2) After adding frameworks:
  .\commit_changes.ps1 -RepoPath "X:\Resonance" -Message "Stage 2: frameworks" -Add "frameworks","CMakePresets.json"

  # 3) Before submodules (so tree is clean for the submodule script):
  .\commit_changes.ps1 -RepoPath "X:\Resonance" -Message "Stage 3: pre-submodules checkpoint" -Add "."

  # Commit only if changes exist (no error if nothing to do)
  .\commit_changes.ps1 -RepoPath . -Message "Update" -Add "." -OnlyIfChanges

  # Amend last commit (no new message -> reuse)
  .\commit_changes.ps1 -RepoPath . -Amend -Add "."

  # Commit and push
  .\commit_changes.ps1 -RepoPath . -Message "Update" -Add "." -Push -Remote origin -Branch main
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][Alias('Path')]
    [string]$RepoPath,

# What to stage; default '.' (you can pass multiple)
    [string[]]$Add = @("."),

# Commit message (ignored if -Amend and no -Message provided)
    [string]$Message = "",

# Only do anything if there are changes (untracked or modified).
    [switch]$OnlyIfChanges,

# Amend the previous commit instead of creating a new one
    [switch]$Amend,

# Add Signed-off-by line
    [switch]$Signoff,

# Pass --no-verify to skip hooks
    [switch]$NoVerify,

# Push after committing
    [switch]$Push,
    [string]$Remote = "origin",
    [string]$Branch = "",

# Enable GPG signing (uses your git config)
    [switch]$GpgSign
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Args)
    $out = & git @Args 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "git $($Args -join ' ') failed ($code):`n$out" }
    return $out
}

# Preflight
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git not found on PATH."
}

$repoFull = Resolve-Path -LiteralPath $RepoPath
Push-Location $repoFull
try {
    # Verify repo
    $inside = (& git rev-parse --is-inside-work-tree) 2>$null
    if ($LASTEXITCODE -ne 0 -or $inside.Trim() -ne "true") {
        throw "Path '$repoFull' is not inside a git work tree."
    }

    # Stage requested paths
    if ($PSCmdlet.ShouldProcess("$repoFull", "git add $($Add -join ', ')")) {
        # Use -A semantics so renames/deletes are captured
        foreach ($p in $Add) { Invoke-Git @('add','-A','--', $p) | Out-Null }
    }

    # Determine if there is anything to commit
    # 1) Staged changes?
    & git diff --cached --quiet
    $hasStaged = ($LASTEXITCODE -ne 0)

    # 2) Untracked files? (Only relevant if user forgot to include them in -Add and not staged)
    $untracked = (& git ls-files --others --exclude-standard)
    $hasUntracked = -not [string]::IsNullOrWhiteSpace($untracked)

    if ($OnlyIfChanges -and -not $hasStaged -and -not $hasUntracked) {
        Write-Host "No changes to commit. Skipping." -ForegroundColor Yellow
        return
    }

    if (-not $hasStaged -and $hasUntracked) {
        # User likely forgot to add untracked; fix by staging them
        if ($PSCmdlet.ShouldProcess("$repoFull", "git add untracked (.)")) {
            Invoke-Git @('add','-A','--','.') | Out-Null
            & git diff --cached --quiet
            $hasStaged = ($LASTEXITCODE -ne 0)
        }
    }

    if (-not $hasStaged) {
        if ($OnlyIfChanges) {
            Write-Host "No staged changes to commit. Skipping." -ForegroundColor Yellow
            return
        } else {
            throw "Nothing staged to commit. Use -Add to specify what to stage or pass -OnlyIfChanges."
        }
    }

    # Build commit args
    $commitArgs = @('commit')
    if ($Amend)      { $commitArgs += '--amend' }
    if ($Signoff)    { $commitArgs += '--signoff' }
    if ($NoVerify)   { $commitArgs += '--no-verify' }
    if ($GpgSign)    { $commitArgs += '--gpg-sign' }

    if (-not $Amend -or ($Amend -and $Message)) {
        if ([string]::IsNullOrWhiteSpace($Message)) {
            throw "Commit message is required (or use -Amend without -Message to reuse last message)."
        }
        $commitArgs += @('-m', $Message)
    }

    if ($PSCmdlet.ShouldProcess("$repoFull", "git $($commitArgs -join ' ')")) {
        $out = Invoke-Git $commitArgs
        Write-Host $out
    }

    if ($Push) {
        # Determine branch if not supplied
        if (-not $Branch) {
            $Branch = (Invoke-Git @('rev-parse','--abbrev-ref','HEAD')).Trim()
            if ($Branch -eq 'HEAD') {
                throw "Detached HEAD; specify -Branch to push."
            }
        }
        if ($PSCmdlet.ShouldProcess("$repoFull", "git push $Remote $Branch")) {
            Write-Host (Invoke-Git @('push', $Remote, $Branch))
        }
    }
}
finally {
    Pop-Location
}
