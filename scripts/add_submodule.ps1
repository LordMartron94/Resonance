<#
.SYNOPSIS
  Add (or re-point) a git submodule with branch control and safety checks.

.EXAMPLE
  .\Add-Submodule.ps1 -TargetRepoPath "X:\proj" -SubmodulePath "extern/WaveCore" `
    -SubmoduleUrl "https://github.com/you/WaveCore.git" -SubmoduleName "WaveCore" `
    -Branch "dev" -Recursive

.EXAMPLE
  # Update an existing submodule to track a new branch + URL (no working tree delete)
  .\Add-Submodule.ps1 -TargetRepoPath . -SubmodulePath extern/WaveCore `
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

# Branch to track (sets .gitmodules submodule.<name>.branch)
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

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Args)
    $out = & git @Args 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "git $($Args -join ' ') failed ($code):`n$out"
    }
    return $out
}

# Normalize/derive parameters
if (-not $SubmoduleName) { $SubmoduleName = $SubmodulePath }

# Pre-flight checks
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git not found on PATH."
}

$target = Resolve-Path -LiteralPath $TargetRepoPath -ErrorAction Stop

# Ensure we're in a git work tree
Push-Location $target
try {
    if ((Invoke-Git @('rev-parse','--is-inside-work-tree')).Trim() -ne 'true') {
        throw "Target path '$target' is not inside a git work tree."
    }

    # Ensure working tree is clean unless -Force or -Update (we still warn)
    $status = Invoke-Git @('status','--porcelain')
    if ($status -and -not $Force) {
        Write-Warning "Working tree not clean. Use -Force to proceed anyway."
        throw "Aborting due to uncommitted changes."
    }

    # Detect whether submodule already exists
    $subPathAbs = Resolve-Path -Path (Join-Path $target $SubmodulePath) -ErrorAction SilentlyContinue
    $alreadyConfigured = $false
    try {
        # Check .gitmodules entry for this path/name
        $gm = Join-Path $target '.gitmodules'
        if (Test-Path $gm) {
            $cfgByPath = Invoke-Git @('config','-f','.gitmodules','--get-regexp',"^submodule\..*\.path$")
            $alreadyConfigured = $cfgByPath -match [Regex]::Escape($SubmodulePath)
        }
    } catch { $alreadyConfigured = $false }

    if ($alreadyConfigured -and -not $Update) {
        throw "A submodule is already configured at path '$SubmodulePath'. Use -Update to modify URL/branch, or remove it first."
    }

    if ($alreadyConfigured -and $Update) {
        if ($PSCmdlet.ShouldProcess($SubmodulePath, "Update submodule URL/branch")) {
            # Update URL and branch in .gitmodules (and local config)
            Invoke-Git @('submodule','set-url','--', $SubmodulePath, $SubmoduleUrl)

            # Ensure submodule.<name>.branch is set in .gitmodules
            Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.branch", $Branch)
            # Keep name stable in .gitmodules (some setups use name<>path); ensure it's present
            Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.path",  $SubmodulePath)
            Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.url",   $SubmoduleUrl)

            # Sync config to local .git/config
            Invoke-Git @('submodule','sync','--', $SubmodulePath)

            # Fetch & checkout the tracking branch inside the submodule
            Invoke-Git @('submodule','update','--init', '--remote', '--', $SubmodulePath)

            if ($Recursive) {
                Invoke-Git @('submodule','update','--init','--recursive','--remote','--', $SubmodulePath)
            }

            # Stage and commit metadata changes
            Invoke-Git @('add','.gitmodules', $SubmodulePath)
            $msg = "Updated submodule $SubmoduleName → url=$SubmoduleUrl, branch=$Branch"
            Invoke-Git @('commit','-m', $msg) | Out-Null
            Write-Host $msg
        }
        return
    }

    # Build add options
    $addArgs = @('submodule','add','--name', $SubmoduleName)
    if ($Branch)   { $addArgs += @('-b', $Branch) }
    if ($Shallow)  { $addArgs += @('--depth','1') } # shallow add
    if ($Force)    { $addArgs += @('--force') }

    $addArgs += @($SubmoduleUrl, $SubmodulePath)

    if ($PSCmdlet.ShouldProcess($SubmodulePath, "Add submodule on branch '$Branch'")) {
        # 1) Add the submodule
        Invoke-Git $addArgs | Out-Null

        # 2) Make sure .gitmodules explicitly records the branch (some git versions already do)
        Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.branch", $Branch)
        Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.url",    $SubmoduleUrl)
        Invoke-Git @('config','-f','.gitmodules',"submodule.$SubmoduleName.path",   $SubmodulePath)

        # 3) Initialize/update (optionally recursive)
        $upd = @('submodule','update','--init','--remote','--', $SubmodulePath)
        Invoke-Git $upd | Out-Null

        if ($Recursive) {
            Invoke-Git @('submodule','update','--init','--recursive','--remote','--', $SubmodulePath) | Out-Null
        }

        # 4) Stage changes
        Invoke-Git @('add','.gitmodules', $SubmodulePath) | Out-Null

        # 5) Commit
        $commitMsg = "Add submodule $SubmoduleName (branch=$Branch)"
        Invoke-Git @('commit','-m', $commitMsg) | Out-Null

        Write-Host "Submodule '$SubmoduleName' added at '$SubmodulePath' tracking '$Branch'."
    }
}
finally {
    Pop-Location
}
