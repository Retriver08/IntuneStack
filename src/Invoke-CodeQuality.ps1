<#
.SYNOPSIS
    IntuneStack code quality checker

.DESCRIPTION
    Run PSScriptAnalyzer and other code quality checks locally

.PARAMETER Path
    Path to analyze (default: current directory)

.PARAMETER FailOnError
    Exit with error code if issues found

.PARAMETER CheckFormatting
    Check code formatting only

.PARAMETER Fix
    Attempt to fix formatting issues automatically
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Path = ".",

    [Parameter(Mandatory = $false)]
    [switch]$FailOnError,

    [Parameter(Mandatory = $false)]
    [switch]$CheckFormatting,

    [Parameter(Mandatory = $false)]
    [switch]$Fix
)

#region Functions
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $Color = switch ($Level) {
        'Info' { 'White' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
    }

    Write-Host $Message -ForegroundColor $Color
}

function Test-PowerShellModules {
    $RequiredModules = @('PSScriptAnalyzer')

    foreach ($Module in $RequiredModules) {
        if (-not (Get-Module -ListAvailable -Name $Module)) {
            Write-Log "Installing required module: $Module" -Level Warning
            Install-Module -Name $Module -Force -Scope CurrentUser
        }
    }
}

function Invoke-PSScriptAnalyzerCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Write-Log "🔍 Running PSScriptAnalyzer..." -Level Info

    $PowerShellFiles = Get-ChildItem -Path $Path -Include "*.ps1", "*.psm1", "*.psd1" -Recurse |
        Where-Object { $_.FullName -notmatch '(node_modules|\.git|\.vscode|bin|obj)' }

    if (-not $PowerShellFiles) {
        Write-Log "No PowerShell files found to analyze" -Level Warning
        return @()
    }

    Write-Log "Found $($PowerShellFiles.Count) PowerShell files to analyze" -Level Info

    $AllResults = @()
    $SettingsPath = Join-Path $Path "PSScriptAnalyzerSettings.psd1"

    foreach ($File in $PowerShellFiles) {
        Write-Log "  Analyzing: $($File.Name)" -Level Info

        try {
            $Results = if (Test-Path $SettingsPath) {
                Invoke-ScriptAnalyzer -Path $File.FullName -Settings $SettingsPath
            } else {
                Invoke-ScriptAnalyzer -Path $File.FullName
            }

            if ($Results) {
                $AllResults += $Results

                foreach ($Result in $Results) {
                    $Level = switch ($Result.Severity) {
                        'Error' { 'Error' }
                        'Warning' { 'Warning' }
                        'Information' { 'Info' }
                    }

                    Write-Log "    [$($Result.Severity)] $($Result.RuleName): $($Result.Message) (Line: $($Result.Line))" -Level $Level
                }
            }
        } catch {
            Write-Log "    Error analyzing file: $($_.Exception.Message)" -Level Error
        }
    }

    return $AllResults
}

function Invoke-FormattingCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$Fix
    )

    Write-Log "📐 Checking PowerShell formatting..." -Level Info

    $PowerShellFiles = Get-ChildItem -Path $Path -Include "*.ps1", "*.psm1", "*.psd1" -Recurse |
        Where-Object { $_.FullName -notmatch '(node_modules|\.git|\.vscode|bin|obj)' }

    $FormattingIssues = 0

    foreach ($File in $PowerShellFiles) {
        $Content = Get-Content -Path $File.FullName -Raw

        # Check for common formatting issues
        $Issues = @()

        # Check for trailing whitespace
        if ($Content -match '\s+$') {
            $Issues += "Trailing whitespace found"
        }

        # Check for mixed line endings
        if ($Content -match '\r\n' -and $Content -match '(?<!\r)\n') {
            $Issues += "Mixed line endings (CRLF and LF)"
        }

        # Check for tabs instead of spaces
        if ($Content -match '\t') {
            $Issues += "Tabs found (should use spaces)"
        }

        if ($Issues) {
            $FormattingIssues += $Issues.Count
            Write-Log "  $($File.Name):" -Level Warning
            foreach ($Issue in $Issues) {
                Write-Log "    - $Issue" -Level Warning
            }

            if ($Fix) {
                Write-Log "    Attempting to fix formatting issues..." -Level Info

                # Fix trailing whitespace
                $Content = $Content -replace '\s+$', ''

                # Fix tabs to spaces
                $Content = $Content -replace '\t', '    '

                # Normalize line endings to LF
                $Content = $Content -replace '\r\n', "`n"

                Set-Content -Path $File.FullName -Value $Content -NoNewline
                Write-Log "    Fixed formatting issues" -Level Success
            }
        }
    }

    return $FormattingIssues
}
#endregion

#region Main Execution
try {
    Write-Log "🚀 IntuneStack Code Quality Check" -Level Success
    Write-Log "Path: $Path" -Level Info

    # Ensure required modules are installed
    Test-PowerShellModules

    $TotalIssues = 0
    $ErrorCount = 0

    if ($CheckFormatting) {
        # Only check formatting
        $FormattingIssues = Invoke-FormattingCheck -Path $Path -Fix:$Fix
        $TotalIssues += $FormattingIssues

        Write-Log "`n📊 Formatting Summary:" -Level Info
        Write-Log "  Formatting Issues: $FormattingIssues" -Level $(if ($FormattingIssues -gt 0) { 'Warning' }else { 'Success' })
    } else {
        # Full analysis
        $AnalysisResults = Invoke-PSScriptAnalyzerCheck -Path $Path
        $FormattingIssues = Invoke-FormattingCheck -Path $Path -Fix:$Fix

        $ErrorCount = ($AnalysisResults | Where-Object Severity -EQ 'Error').Count
        $WarningCount = ($AnalysisResults | Where-Object Severity -EQ 'Warning').Count
        $InfoCount = ($AnalysisResults | Where-Object Severity -EQ 'Information').Count

        $TotalIssues = $AnalysisResults.Count + $FormattingIssues

        Write-Log "`n📊 Analysis Summary:" -Level Info
        Write-Log "  PSScriptAnalyzer Issues: $($AnalysisResults.Count)" -Level Info
        Write-Log "    Errors: $ErrorCount" -Level $(if ($ErrorCount -gt 0) { 'Error' }else { 'Success' })
        Write-Log "    Warnings: $WarningCount" -Level $(if ($WarningCount -gt 0) { 'Warning' }else { 'Success' })
        Write-Log "    Information: $InfoCount" -Level Info
        Write-Log "  Formatting Issues: $FormattingIssues" -Level $(if ($FormattingIssues -gt 0) { 'Warning' }else { 'Success' })
        Write-Log "  Total Issues: $TotalIssues" -Level $(if ($TotalIssues -gt 0) { 'Warning' }else { 'Success' })
    }

    # Exit with appropriate code
    if ($FailOnError -and ($ErrorCount -gt 0 -or $TotalIssues -gt 0)) {
        Write-Log "`n❌ Code quality check failed!" -Level Error
        exit 1
    } elseif ($TotalIssues -gt 0) {
        Write-Log "`n⚠️ Code quality check completed with issues" -Level Warning
    } else {
        Write-Log "`n✅ Code quality check passed!" -Level Success
    }
} catch {
    Write-Log "💥 Code quality check failed: $($_.Exception.Message)" -Level Error
    exit 1
}
#endregion
