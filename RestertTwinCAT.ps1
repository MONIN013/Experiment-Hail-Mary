param(
    [string]$Configuration = "Release",
    [string]$Platform = "TwinCAT RT (x64)",
    [switch]$RebuildSolution = $false,
    [switch]$SkipVisualStudioSync = $false,
    [switch]$ActivateConfiguration = $true,
    [switch]$RestartTwinCAT = $true
)


# powershell -NoProfile -ExecutionPolicy Bypass -File .\RestertTwinCAT.ps1


Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$SolutionPath = Join-Path $RepoRoot "ExperimentHailMary.sln"
$LoggerProjectPath = Join-Path $RepoRoot "ExperimentLogger\ExperimentLogger.vcxproj"
$SolutionConfiguration = "$Configuration|$Platform"

function Resolve-Vs2019MsBuild {
    $candidates = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "Visual Studio 2019 MSBuild was not found. Install VS2019 Build Tools or update Resolve-Vs2019MsBuild in this script."
}

function Add-MarshalHelperType {
    if ("MarshalHelper" -as [type]) {
        return
    }

    $source = @"
using System;
using System.Runtime.InteropServices;

public class MarshalHelper {
    [DllImport("ole32.dll")]
    private static extern int CLSIDFromProgID([MarshalAs(UnmanagedType.LPWStr)] string lpszProgID, out Guid pclsid);

    [DllImport("oleaut32.dll", PreserveSig = false)]
    private static extern void GetActiveObject(ref Guid rclsid, IntPtr pvReserved, [MarshalAs(UnmanagedType.IUnknown)] out object ppunk);

    public static object GetActiveObject(string progId) {
        Guid clsid;
        CLSIDFromProgID(progId, out clsid);
        object obj;
        GetActiveObject(ref clsid, IntPtr.Zero, out obj);
        return obj;
    }
}
"@
    Add-Type -TypeDefinition $source
}

function Get-ActiveVisualStudio2019 {
    Add-MarshalHelperType
    try {
        return [MarshalHelper]::GetActiveObject("VisualStudio.DTE.16.0")
    }
    catch {
        return $null
    }
}

function Test-DteSolutionAvailable {
    param([Parameter(Mandatory = $true)]$Dte)

    try {
        return ($null -ne $Dte.Solution)
    }
    catch {
        return $false
    }
}

function New-VisualStudio2019 {
    $dte = New-Object -ComObject "VisualStudio.DTE.16.0"
    $dte.MainWindow.Visible = $true
    return $dte
}

function Get-VisualStudio2019ForAutomation {
    $dte = Get-ActiveVisualStudio2019
    if ($null -ne $dte -and (Test-DteSolutionAvailable -Dte $dte)) {
        return $dte
    }

    if ($null -ne $dte) {
        Write-Warning "Active VS2019 DTE did not expose a Solution object. Starting a fresh VS2019 automation instance."
    }

    return New-VisualStudio2019
}

function Get-SolutionConfigurationName {
    param([Parameter(Mandatory = $true)]$ConfigurationObject)

    $name = [string]$ConfigurationObject.Name
    $platformName = ""
    try {
        $platformName = [string]$ConfigurationObject.PlatformName
    }
    catch {
        $platformName = ""
    }

    if ($platformName.Length -gt 0 -and -not $name.Contains("|")) {
        return "$name|$platformName"
    }
    return $name
}

function Wait-DteSolutionBuild {
    param(
        [Parameter(Mandatory = $true)]$Dte,
        [int]$TimeoutSeconds = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $solution = $Dte.Solution
            if ($null -ne $solution) {
                $solutionBuild = $solution.SolutionBuild
                if ($null -ne $solutionBuild -and $null -ne $solutionBuild.ActiveConfiguration) {
                    return $solutionBuild
                }
            }
        }
        catch {
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for Visual Studio solution build automation to become available."
}

function Set-VisualStudioActiveConfiguration {
    param(
        [Parameter(Mandatory = $true)]$Dte,
        [Parameter(Mandatory = $true)][string]$ConfigurationName,
        [Parameter(Mandatory = $true)][string]$SolutionPath
    )

    $openSolutionPath = ""
    try {
        $openSolutionPath = [string]$Dte.Solution.FullName
    }
    catch {
        $openSolutionPath = ""
    }

    if ($openSolutionPath.Length -eq 0) {
        Write-Host "Opening solution in Visual Studio 2019: $SolutionPath"
        $Dte.Solution.Open($SolutionPath)
    }

    $solutionBuild = Wait-DteSolutionBuild -Dte $Dte

    $activeBefore = Get-SolutionConfigurationName $solutionBuild.ActiveConfiguration
    Write-Host "VS2019 ActiveConfiguration before: $activeBefore"

    $configs = $solutionBuild.SolutionConfigurations
    for ($i = 1; $i -le $configs.Count; $i++) {
        $config = $configs.Item($i)
        if ((Get-SolutionConfigurationName $config) -eq $ConfigurationName) {
            $config.Activate()
            $solutionBuild = Wait-DteSolutionBuild -Dte $Dte
            $activeAfter = Get-SolutionConfigurationName $solutionBuild.ActiveConfiguration
            Write-Host "VS2019 ActiveConfiguration after:  $activeAfter"
            return
        }
    }

    throw "Solution configuration '$ConfigurationName' was not found in Visual Studio."
}

function Get-TcSysManager {
    param([Parameter(Mandatory = $true)]$Dte)

    try {
        return $Dte.GetObject("TcSysManager")
    }
    catch {
        throw "TcSysManager automation object is not available. Open the TwinCAT XAE solution in Visual Studio 2019 and try again. $($_.Exception.Message)"
    }
}

function Invoke-TwinCatActivateConfiguration {
    param(
        [Parameter(Mandatory = $true)]$Dte,
        [Parameter(Mandatory = $true)][string]$ConfigurationName,
        [Parameter(Mandatory = $true)][string]$SolutionPath,
        [switch]$Restart
    )

    Set-VisualStudioActiveConfiguration `
        -Dte $Dte `
        -ConfigurationName $ConfigurationName `
        -SolutionPath $SolutionPath

    $sysManager = Get-TcSysManager -Dte $Dte

    Write-Host "Activating TwinCAT configuration..."
    $sysManager.ActivateConfiguration()
    Write-Host "TwinCAT Activate Configuration completed."

    if ($Restart) {
        Write-Host "Restarting TwinCAT runtime..."
        $sysManager.StartRestartTwinCAT()
        Write-Host "TwinCAT runtime restart requested."
    }
}

function Invoke-MsBuild {
    param(
        [Parameter(Mandatory = $true)][string]$MsBuildPath,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$Configuration,
        [Parameter(Mandatory = $true)][string]$Platform
    )

    Write-Host "ReBuild: $ProjectPath"
    Write-Host "MSBuild: $MsBuildPath"
    Write-Host "Configuration: $Configuration"
    Write-Host "Platform: $Platform"

    & $MsBuildPath $ProjectPath `
        "/t:Rebuild" `
        "/p:Configuration=$Configuration" `
        "/p:Platform=$Platform" `
        "/m"

    if ($LASTEXITCODE -ne 0) {
        throw "MSBuild failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $SolutionPath)) {
    throw "Solution not found: $SolutionPath"
}
if (-not (Test-Path -LiteralPath $LoggerProjectPath)) {
    throw "ExperimentLogger project not found: $LoggerProjectPath"
}

$msbuild = Resolve-Vs2019MsBuild
$dte = $null

if (-not $SkipVisualStudioSync) {
    $dte = Get-VisualStudio2019ForAutomation
    if ($null -eq $dte) {
        Write-Warning "Visual Studio 2019 is not running. Skipping DTE ActiveConfiguration sync."
    }
    else {
        Set-VisualStudioActiveConfiguration `
            -Dte $dte `
            -ConfigurationName $SolutionConfiguration `
            -SolutionPath $SolutionPath
    }
}

if ($RebuildSolution) {
    Invoke-MsBuild `
        -MsBuildPath $msbuild `
        -ProjectPath $SolutionPath `
        -Configuration $Configuration `
        -Platform $Platform
}
else {
    Invoke-MsBuild `
        -MsBuildPath $msbuild `
        -ProjectPath $LoggerProjectPath `
        -Configuration $Configuration `
        -Platform $Platform
}

if ($ActivateConfiguration -or $RestartTwinCAT) {
    if ($null -eq $dte -or -not (Test-DteSolutionAvailable -Dte $dte)) {
        $dte = Get-VisualStudio2019ForAutomation
    }
    if ($null -eq $dte) {
        throw "Visual Studio 2019 is not running. Start the TwinCAT XAE solution, then rerun this script with -ActivateConfiguration."
    }

    Invoke-TwinCatActivateConfiguration `
        -Dte $dte `
        -ConfigurationName $SolutionConfiguration `
        -SolutionPath $SolutionPath `
        -Restart:$RestartTwinCAT
}
