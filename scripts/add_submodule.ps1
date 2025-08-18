<#
.SYNOPSIS
  Add (or re-point) a git submodule with branch control, preflight checks, and safety guards.

.EXAMPLE
  .\add_submodule.ps1 -TargetRepoPath "X:\proj" -SubmodulePath "extern/WaveCore" `
    -SubmoduleUrl "https://github.com/you/WaveCore.git" -SubmoduleName "WaveCore" `
    -Branch "dev" -Recursive

.EXAMPLE
  # Update an existing submodule to track a new branch + URL (no working tree delete)
  .\add_submodule.ps1 -TargetRepoPath . -SubmodulePath extern/WaveCore `
    -SubmoduleUrl git@github.com:you/WaveCore.git -SubmoduleName WaveCore `
    -Branch release -Update
#>

[CmdletBinding(SupportsShouldProcess)]
param(
# Path to the superproject (the repo that will host the submodule)
    [Parameter(Mandatory)][Alias('repo','path')]
    [string]$TargetRepoPath,

# Path where the submodule will live inside the repo (relative or absolute)
    [Parameter(Mandatory)][Alias('dest')]
    [string]$SubmodulePath,

# Clone URL for the submodule (HTTPS or SSH)
    [Parameter(Mandatory)][Alias('url')]
    [string]$SubmoduleUrl,

# Logical name in .gitmodules; defaults to the path if not set
    [Alias('name')]
    [string]$SubmoduleName,

# Branch to track (sets .gitmodules submodule.<name>.branch). If empty, uses remote default.
    [Alias('b')]
    [string]$Branch = 'main',

# Recursively initialize/update nested submodules
    [switch]$Recursive,

# Use a shallow clone for the submodule
    [switch]$Shallow,

# If the submodule already exists, update its URL/branch instead of failing
    [switch]$Update,

# Force operations that would otherwise bail out (e.g., re-adding in a dirty tree)
    [switch]$Force
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

    $allArgs = @('-C', $TargetRepoPath) + $Args

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
            else { Write-Output $line } 
        }
    }

    if ($code -ne 0) {
        throw "git $($processInfo.Arguments) failed ($code)"
    }

    return $stdout
}

try {
    # Normalize/derive parameters
    if (-not $SubmoduleName) { $SubmoduleName = $SubmodulePath }

    # Preflight
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git not found on PATH."
    }

    $target = Resolve-Path -LiteralPath $TargetRepoPath -ErrorAction Stop

    Push-Location $target
    try {
        if ((Invoke-Git @('rev-parse','--is-inside-work-tree')).Trim() -ne 'true') {
            throw "Target path '$target' is not inside a git work tree."
        }

        # Enforce clean tree unless -Force or -Update (submodule add modifies index & .gitmodules)
        $status = Invoke-Git @('status','--porcelain')
        if ($status) {
            Write-Host "DEBUG: Dirty files seen by add_submodule.ps1:"
            $status | ForEach-Object { Write-Host "  $_" }
        }
        if ($status -and -not $Force -and -not $Update) {
            Write-Warning "Working tree not clean. Use -Force to proceed anyway."
            throw "Aborting due to uncommitted changes."
        }

        # Check destination path state
        $dest = Join-Path (Get-Location) $SubmodulePath
        if (Test-Path $dest) {
            $entries = Get-ChildItem -Force -LiteralPath $dest | Where-Object { $_.Name -notin @('.','..') }
            if ($entries) {
                throw "Destination '$SubmodulePath' exists and is not empty. Remove or choose a different path."
            }
        }

        # Remote/branch preflight (if Branch provided)
        if ($Branch) {
            $ls = & git ls-remote --heads $SubmoduleUrl $Branch 2>&1
            $code = $LASTEXITCODE
            if ($code -ne 0) {
                throw "Cannot access remote '$SubmoduleUrl' (exit=$code):`n$ls"
            }
            if (-not $ls) {
                throw "Remote branch '$Branch' does not exist at '$SubmoduleUrl'."
            }
        } else {
            Write-Verbose "No branch provided; will track the submodule's default branch."
        }

        # Detect whether submodule already exists (by .gitmodules path entry)
        $alreadyConfigured = $false
        $gm = Join-Path (Get-Location) '.gitmodules'
        if (Test-Path $gm) {
            try {
                $cfgByPath = Invoke-Git @('config','-f','.gitmodules','--get-regexp',"^submodule\..*\.path$")
                $alreadyConfigured = $cfgByPath -match [Regex]::Escape($SubmodulePath)
            } catch { $alreadyConfigured = $false }
        }

        if ($alreadyConfigured -and -not $Update) {
            throw "A submodule is already configured at path '$SubmodulePath'. Use -Update to modify URL/branch, or remove it first."
        }

        if ($alreadyConfigured -and $Update) {
            if ($PSCmdlet.ShouldProcess($SubmodulePath, "Update submodule URL/branch")) {
                # Update URL and branch in .gitmodules (and local config)
                Invoke-Git @('submodule','set-url','--', $SubmodulePath, $SubmoduleUrl)

                if ($Branch) {
                    Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.branch", $Branch)
                } else {
                    # Clear explicit branch if caller chose to follow default
                    & git config -f .gitmodules --unset "submodule.$SubmoduleName.branch" 2>$null
                }

                Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.path",  $SubmodulePath)
                Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.url",   $SubmoduleUrl)

                # Sync config to local .git/config
                Invoke-Git @('submodule','sync','--', $SubmodulePath)

                # Fetch & checkout the tracking branch inside the submodule
                $upd = @('submodule','update','--init','--remote','--', $SubmodulePath)
                if ($Recursive) { $upd = @('submodule','update','--init','--recursive','--remote','--', $SubmodulePath) }
                Invoke-Git $upd | Out-Null

                # Stage and commit metadata changes
                Invoke-Git @('add','.gitmodules', $SubmodulePath)
                $msg = "Updated submodule $SubmoduleName → url=$SubmoduleUrl" + ($(if($Branch) { ", branch=$Branch" } else { "" }))
                Invoke-Git @('commit','-m', $msg) | Out-Null
                Write-Host $msg
            }

            $global:LASTEXITCODE = 0
            exit 0
        }

        # Build add options
        $addArgs = @('submodule','add','--name', $SubmoduleName)
        if ($Branch)   { $addArgs += @('-b', $Branch) }
        if ($Shallow)  { $addArgs += @('--depth','1') } # shallow add
        if ($Force)    { $addArgs += @('--force') }
        $addArgs += @($SubmoduleUrl, $SubmodulePath)

        if ($PSCmdlet.ShouldProcess($SubmodulePath, "Add submodule" + ($(if($Branch) { " on branch '$Branch'" } else { "" })))) {
            # 1) Add the submodule
            Invoke-Git $addArgs | Out-Null

            # 2) Make sure .gitmodules explicitly records the branch (some git versions already do)
            if ($Branch) {
                Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.branch", $Branch)
            } else {
                & git config -f .gitmodules --unset "submodule.$SubmoduleName.branch" 2>$null
            }
            Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.url",    $SubmoduleUrl)
            Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.path",   $SubmodulePath)

            # 3) Initialize/update (optionally recursive, and follow remote)
            $upd = @('submodule','update','--init','--remote','--', $SubmodulePath)
            if ($Recursive) {
                $upd = @('submodule','update','--init','--recursive','--remote','--', $SubmodulePath)
            }
            Invoke-Git $upd | Out-Null

            # 4) Stage changes
            Invoke-Git @('add','.gitmodules', $SubmodulePath) | Out-Null

            # 5) Commit
            $commitMsg = "Add submodule $SubmoduleName" + ($(if($Branch) { " (branch=$Branch)" } else { "" }))
            Invoke-Git @('commit','-m', $commitMsg) | Out-Null

            Write-Host "Submodule '$SubmoduleName' added at '$SubmodulePath'" + ($(if($Branch) { " tracking '$Branch'." } else { "." }))
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

    if ($PSBoundParameters.ContainsKey('Verbose')) { Write-Verbose $_.ToString() }
    else {Write-Host "ERROR: $msg"}

    $global:LASTEXITCODE = 1
    exit 1
}
