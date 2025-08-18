<#
.SYNOPSIS
  Stage and commit changes in a repo safely (only commits if there are changes).

.EXAMPLES
  .\git_commit_changes.ps1 -RepoPath "X:\Resonance" -Message "Project Forge: Stage 1 -- repository structure" -Add "."
  .\git_commit_changes.ps1 -RepoPath "X:\Resonance" -Message "Project Forge: Stage 2 -- frameworks" -Add "frameworks","CMakePresets.json"
  .\git_commit_changes.ps1 -RepoPath "X:\Resonance" -Message "Project Forge: Stage 3 -- pre-submodules checkpoint" -Add "."
  .\git_commit_changes.ps1 -RepoPath . -Message "Project Forge: Update" -Add "." -OnlyIfChanges
  .\git_commit_changes.ps1 -RepoPath . -Amend -Add "."
  .\git_commit_changes.ps1 -RepoPath . -Message "Project Forge: Update" -Add "." -Push -Remote origin -Branch main
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][Alias('Path')]
    [string]$RepoPath,

# What to stage; default '.' (you can pass multiple)
    [string[]]$Add = @("."),

# Commit message (ignored if -Amend and no -Message provided)
    [string]$Message = $(throw "Commit message required"),

# Only do anything if there are changes (untracked or modified)
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
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Quote-Arg {
    param([Parameter(Mandatory)][string]$Arg)
    if ($Arg -match '[\s"`()]') {
        return '"' + ($Arg -replace '"', '\"') + '"'
    }
    return $Arg
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Args)

    $allArgs = @('-C', $RepoPath) + $Args

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "git"
    $processInfo.Arguments = ($allArgs | ForEach-Object { Quote-Arg $_ }) -join " "
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError  = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $code = $process.ExitCode

    if ($stdout) { Write-Output $stdout }

    if ($stderr) {
        foreach ($line in $stderr -split "`r?`n") {
            if (-not $line.Trim()) { continue }
            if ($line -match '(?i)warning:') { Write-Warning $line }
            elseif ($line -match '(?i)error:') { Write-Error $line }
            else { Write-Output $line }  # progress like "Cloning into ..."
        }
    }

    if ($code -ne 0) {
        throw "git $($processInfo.Arguments) failed ($code)"
    }

    return $stdout
}

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git not found on PATH."
    }

    $repoFull = Resolve-Path -LiteralPath $RepoPath

    # Verify repo
    $inside = Invoke-Git @('rev-parse','--is-inside-work-tree')
    if ($inside.Trim() -ne "true") {
        throw "Path '$repoFull' is not inside a git work tree."
    }

    # Stage requested paths (use -A so renames/deletes are captured)
    if ($PSCmdlet.ShouldProcess("$repoFull", "git add $($Add -join ', ')")) {
        foreach ($p in $Add) {
            Invoke-Git @('add','-A','--', $p) | Out-Null
        }
    }

    # Robust staged detection
    Invoke-Git @('update-index','-q','--refresh') | Out-Null
    $stagedList   = Invoke-Git @('diff','--cached','--name-only')
    $hasStaged    = -not [string]::IsNullOrWhiteSpace($stagedList)

    $untracked    = Invoke-Git @('ls-files','--others','--exclude-standard')
    $hasUntracked = -not [string]::IsNullOrWhiteSpace($untracked)

    if ($OnlyIfChanges -and -not $hasStaged -and -not $hasUntracked) {
        Write-Host "No changes to commit. Skipping."
        $global:LASTEXITCODE = 0
        exit 0
    }

    if (-not $hasStaged -and $hasUntracked) {
        if ($PSCmdlet.ShouldProcess("$repoFull", "git add untracked (.)")) {
            Invoke-Git @('add','-A','--','.') | Out-Null
            Invoke-Git @('update-index','-q','--refresh') | Out-Null
            $stagedList = Invoke-Git @('diff','--cached','--name-only')
            $hasStaged  = -not [string]::IsNullOrWhiteSpace($stagedList)
        }
    }

    if (-not $hasStaged) {
        if ($OnlyIfChanges) {
            Write-Host "No staged changes to commit. Skipping."
            $global:LASTEXITCODE = 0
            exit 0
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
        try {
            $out = Invoke-Git $commitArgs
            Write-Host $out
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -match 'nothing to commit' -or $msg -match 'nothing added to commit') {
                Write-Host "No effective changes to commit after staging. Skipping."
                $global:LASTEXITCODE = 0
                exit 0
            }
            throw
        }
    }

    if ($Push) {
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

    $global:LASTEXITCODE = 0
    exit 0
}
catch {
    $msg = $_.Exception.Message
    if ($msg -match 'NativeCommandError') { $msg = $_.ToString() }

    if ($PSBoundParameters.ContainsKey('Verbose')) { Write-Verbose $_.ToString() }
    else { Write-Host "ERROR: $msg" }

    $global:LASTEXITCODE = 1
    exit 1
}
