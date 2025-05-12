# DotEnv.psm1

# Requires -Version 5.1

using namespace System.IO
using namespace System.Management.Automation

$script:trueOriginalEnvironmentVariables = @{} # Stores { VarName = OriginalValueOrNull } - a persistent record of pre-module values
$script:previousEnvFiles = @()
$script:previousWorkingDirectory = $PWD.Path
$script:e = [char]27
$script:itemiserA = [char]0x2022
$script:itemiser = [char]0x21B3

# $DebugPreference = 'Continue'

function Get-RelativePath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$BasePath
  )

  try {
    $absTarget = [System.IO.Path]::GetFullPath($Path)
    $absBase = [System.IO.Path]::GetFullPath($BasePath)

    if ($absTarget.Equals($absBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "."
    }

    # Ensure BasePath for Uri ends with a directory separator.
    $uriBaseNormalized = $absBase
    if (-not $uriBaseNormalized.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $uriBaseNormalized += [System.IO.Path]::DirectorySeparatorChar
    }
    $baseUri = [System.Uri]::new($uriBaseNormalized)
    $targetUri = [System.Uri]::new($absTarget)

    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString())

    return $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
  }
  catch {
    Write-Warning "Get-RelativePath: Error calculating relative path for Target '$Path' from Base '$BasePath'. Error: $($_.Exception.Message). Falling back to original target path."
    return $Path
  }
}

# Cannot be local as this is mocked in Import-DotEnv tests
function Get-EnvFilesUpstream {
  [CmdletBinding()]
  param([string]$Directory = ".")

  $currentDirNormalized = ""
  try {
    $currentDirNormalized = [System.IO.Path]::GetFullPath($Directory).TrimEnd([System.IO.Path]::DirectorySeparatorChar).ToLowerInvariant()
    $resolvedPath = Convert-Path -Path $Directory -ErrorAction Stop
  }
  catch {
    Write-Warning "Get-EnvFilesUpstream: Error resolving path '$Directory'. Error: $($_.Exception.Message). Defaulting to PWD."
    $resolvedPath = $PWD.Path
    $currentDirNormalized = [System.IO.Path]::GetFullPath($resolvedPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar).ToLowerInvariant()
  }

  $envFiles = [System.Collections.Generic.List[string]]::new()
  $currentSearchDir = $resolvedPath

  while ($currentSearchDir) {
    $envPath = Join-Path $currentSearchDir ".env"
    if (Test-Path -LiteralPath $envPath -PathType Leaf) {
      $envFiles.Add($envPath)
    }
    $parentDir = Split-Path -Path $currentSearchDir -Parent
    if ($parentDir -eq $currentSearchDir -or [string]::IsNullOrEmpty($parentDir)) { break }
    $currentSearchDir = $parentDir
  }

  if ($envFiles.Count -gt 0) {
    $envFiles.Reverse()
  }
  return [string[]]$envFiles
}

function Format-EnvFilePath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$BasePath
  )

  $relativePath = Get-RelativePath -Path $Path -BasePath $BasePath
  $corePath = Split-Path -Path $relativePath -Parent

  if (-not [string]::IsNullOrEmpty($corePath)) {
    $boldCore = "${script:e}[1m${corePath}${script:e}[22m"
    $relativePath = $relativePath.Replace($corePath, $boldCore)
  }

  return $relativePath
}

function Format-VarHyperlink {
    param(
        [string]$VarName,
        [string]$FilePath,
        [int]$LineNumber
    )
    # Ensure FilePath is absolute for the hyperlink
    $absFilePath = try { Resolve-Path -LiteralPath $FilePath -ErrorAction Stop } catch { $FilePath }
    $fileUrl = "vscode://file/$($absFilePath):${LineNumber}"
    return "$script:e]8;;$fileUrl$script:e\$VarName$script:e]8;;$script:e\"
}

# --- Helper function to get effective environment variables from a list of .env files ---
function Get-EnvVarsFromFiles {
    param(
        [string[]]$Files,
        [string]$BasePath # BasePath is for context, not directly used in var aggregation here
    )

  function Parse-EnvFile {
      param([string]$FilePath)
      $vars = @{}
      if (-not ([System.IO.File]::Exists($FilePath))) {
          Write-Debug "Parse-EnvFile: File '$FilePath' does not exist."
          return $vars
      }
      try {
          $lines = [System.IO.File]::ReadLines($FilePath)
      } catch {
          Write-Warning "Parse-EnvFile: Error reading file '$FilePath'. Error: $($_.Exception.Message)"
          return $vars
      }
      $lineNumber = 0
      foreach ($line in $lines) {
          $lineNumber++
          if ([string]::IsNullOrWhiteSpace($line)) { continue }
          $trimmed = $line.TrimStart()
          if ($trimmed.StartsWith('#')) { continue }
          $split = $line.Split('=', 2)
          if ($split.Count -eq 2) {
              $varName = $split[0].Trim()
              $varValue = $split[1].Trim()
              $vars[$varName] = @{ Value = $varValue; Line = $lineNumber; SourceFile = $FilePath }
          }
      }
      return $vars
  }

    if ($Files.Count -eq 0) {
        return @{}
    }

    if ($Files.Count -eq 1) {
        # Fast path for a single file. Parse-EnvFile returns the rich structure.
        return Parse-EnvFile -FilePath $Files[0]
    }

    # For multiple files, use RunspacePool for parallel parsing.
    $finalEffectiveVars = @{}
    $parsedResults = New-Object "object[]" $Files.Count # To store results in order

    # Define the script that will be run in each runspace.
    # It includes a minimal Parse-EnvFile definition to ensure it's available and self-contained.
    $scriptBlockText = @'
param([string]$PathToParse)

# Minimal Parse-EnvFile definition for use in isolated runspaces
function Parse-EnvFileInRunspace {
    param([string]$LocalFilePath)
    $localVars = @{} # PowerShell hashtable literal is fine here, it's a PS runspace
    # Directly use System.IO.File for existence and reading to minimize dependencies
    if (-not ([System.IO.File]::Exists($LocalFilePath))) {
        return $localVars
    }
    try {
        $fileLines = [System.IO.File]::ReadLines($LocalFilePath)
    } catch {
        # Silently return empty on read error in this isolated context
        return $localVars
    }
    $lineNum = 0
    foreach ($txtLine in $fileLines) {
        $lineNum++
        if ([string]::IsNullOrWhiteSpace($txtLine)) { continue }
        $trimmedTxtLine = $txtLine.TrimStart()
        if ($trimmedTxtLine.StartsWith('#')) { continue }
        $parts = $txtLine.Split('=', 2)
        if ($parts.Count -eq 2) {
            $name = $parts[0].Trim()
            $val = $parts[1].Trim()
            # This structure needs to match what the rest of the module expects
            $localVars[$name] = @{ Value = $val; Line = $lineNum; SourceFile = $LocalFilePath }
        }
    }
    return $localVars
}

Parse-EnvFileInRunspace -LocalFilePath $PathToParse
'@

    # Determine a reasonable number of runspaces. Cap at 8 to avoid excessive resource use.
    # Fix: [Math]::Min takes only two arguments. Nest calls for three values.
    $maxRunspaces = [Math]::Min(8, [Math]::Min($Files.Count, ([System.Environment]::ProcessorCount * 2)))
    $minRunspaces = 1

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    # CreateDefault2 is generally good for providing access to common .NET types like System.IO.File

    $runspacePool = $null
    $psInstanceTrackers = [System.Collections.Generic.List[object]]::new()

    try {
        $runspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool($minRunspaces, $maxRunspaces, $iss, $Host)
        $runspacePool.Open()

        for ($i = 0; $i -lt $Files.Count; $i++) {
            $fileToParse = $Files[$i]
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $runspacePool
            $null = $ps.AddScript($scriptBlockText).AddArgument($fileToParse)

            $asyncResult = $ps.BeginInvoke()
            $psInstanceTrackers.Add([PSCustomObject]@{
                PowerShell    = $ps
                AsyncResult   = $asyncResult
                OriginalIndex = $i
                FilePath      = $fileToParse # For logging/debugging
            })
        }

        # Wait for all to complete and collect results
        foreach ($tracker in $psInstanceTrackers) {
            try {
                $outputCollection = $tracker.PowerShell.EndInvoke($tracker.AsyncResult)

                if ($tracker.PowerShell.Streams.Error.Count -gt 0) {
                    foreach($err in $tracker.PowerShell.Streams.Error){
                        Write-Warning "Error parsing file '$($tracker.FilePath)' in parallel: $($err.ToString())"
                    }
                    $parsedResults[$tracker.OriginalIndex] = @{}
                } elseif ($outputCollection -ne $null -and $outputCollection.Count -eq 1) {
                    $singleOutput = $outputCollection[0]
                    if ($singleOutput -is [System.Collections.IDictionary]) { # Directly a hashtable
                        $parsedResults[$tracker.OriginalIndex] = $singleOutput
                    } elseif ($singleOutput -is [System.Management.Automation.PSObject] -and $singleOutput.BaseObject -is [System.Collections.IDictionary]) { # PSObject wrapping a hashtable
                        $parsedResults[$tracker.OriginalIndex] = $singleOutput.BaseObject
                    } else {
                        Write-Warning "Unexpected output type from parallel parsing of '$($tracker.FilePath)'. Type: $($singleOutput.GetType().FullName)"
                        $parsedResults[$tracker.OriginalIndex] = @{}
                    }
                } else {
                    Write-Warning "No output or multiple outputs from parallel parsing of '$($tracker.FilePath)'. Output count: $($outputCollection.Count)"
                    $parsedResults[$tracker.OriginalIndex] = @{}
                }
            } catch {
                 Write-Warning "Exception during EndInvoke for file '$($tracker.FilePath)': $($_.Exception.Message)"
                 $parsedResults[$tracker.OriginalIndex] = @{} # Store empty on exception
            }
        }
    }
    finally {
        foreach ($tracker in $psInstanceTrackers) {
            if ($tracker.PowerShell) {
                $tracker.PowerShell.Dispose()
            }
        }
        if ($runspacePool) {
            $runspacePool.Close()
            $runspacePool.Dispose()
        }
    }

    # Sequentially merge the parsed results to ensure correct precedence.
    foreach ($fileScopedVarsHashtable in $parsedResults) {
        if ($null -eq $fileScopedVarsHashtable) { continue } # Skip if null (e.g. error during parsing)
        foreach ($varNameKey in $fileScopedVarsHashtable.Keys) {
            $finalEffectiveVars[$varNameKey] = $fileScopedVarsHashtable[$varNameKey]
        }
    }
    return $finalEffectiveVars
}

function Import-DotEnv {
  [CmdletBinding(DefaultParameterSetName = 'Load', HelpUri = 'https://github.com/CosmicDNA/ImportDotEnv#readme')]
  param(
    [Parameter(ParameterSetName = 'Load', Position = 0, ValueFromPipelineByPropertyName = $true)]
    [string]$Path,

    [Parameter(ParameterSetName = 'Unload')]
    [switch]$Unload,

    [Parameter(ParameterSetName = 'Help')]
    [switch]$Help,

    [Parameter(ParameterSetName = 'List')]
    [switch]$List
  )

  # --- Helper: Parse a single .env line into [name, value] or $null ---
  function Parse-EnvLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    $trimmed = $Line.TrimStart()
    if ($trimmed.StartsWith('#')) { return $null }
    $split = $Line.Split('=', 2)
    if ($split.Count -eq 2) {
      return @($split[0].Trim(), $split[1].Trim())
    }
    return $null
  }

  function Get-VarsToRestoreByFileMap {
    param(
      [string[]]$Files,
      [string[]]$VarsToRestore
    )

    function Get-EnvVarNamesFromFile {
      param([string]$FilePath)
      if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return @() }
      try {
        return [System.IO.File]::ReadLines($FilePath) | ForEach-Object {
          $parsed = Parse-EnvLine $_
          if ($null -ne $parsed) { $parsed[0] }
        } | Where-Object { $_ }
      } catch {
        Write-Warning "Get-EnvVarNamesFromFile: Error reading file '$FilePath'. Skipping. Error: $($_.Exception.Message)"
        return @()
      }
    }

    $varsToUnsetByFileMap = @{}
    foreach ($fileToScan in $Files) {
      foreach ($parsedVarName in Get-EnvVarNamesFromFile -FilePath $fileToScan) {
        if ($VarsToRestore -contains $parsedVarName) {
          if (-not $varsToUnsetByFileMap.ContainsKey($fileToScan)) { $varsToUnsetByFileMap[$fileToScan] = [System.Collections.Generic.List[string]]::new() }
          $varsToUnsetByFileMap[$fileToScan].Add($parsedVarName)
        }
      }
    }
    return $varsToUnsetByFileMap
  }

  if ($PSCmdlet.ParameterSetName -eq 'Unload') {
    Write-Debug "MODULE Import-DotEnv: Called with -Unload switch."
    $varsFromLastLoad = Get-EnvVarsFromFiles -Files $script:previousEnvFiles -BasePath $script:previousWorkingDirectory

    if ($varsFromLastLoad.Count -gt 0) {
      Write-Host "`nUnloading active .env configuration(s)..." -ForegroundColor Yellow

      $allVarsToRestore = $varsFromLastLoad.Keys
      $varsToRestoreByFileMap = Get-VarsToRestoreByFileMap -Files $script:previousEnvFiles -VarsToRestore $allVarsToRestore

      $varsCoveredByFileMap = $varsToRestoreByFileMap.Values | ForEach-Object { $_ } | Sort-Object -Unique
      $varsToRestoreNoFileAssociation = $allVarsToRestore | Where-Object { $varsCoveredByFileMap -notcontains $_ }

      Restore-EnvVars -VarsToRestoreByFileMap $varsToRestoreByFileMap -VarNames $varsToRestoreNoFileAssociation -TrueOriginalEnvironmentVariables $script:trueOriginalEnvironmentVariables -BasePath $script:previousWorkingDirectory

      $script:previousEnvFiles = @()
      $script:previousWorkingDirectory = "STATE_AFTER_EXPLICIT_UNLOAD"
      Write-Host "Environment restored. Module state reset." -ForegroundColor Green
    }
    return
  }

  if ($PSCmdlet.ParameterSetName -eq 'Help' -or $Help) {
    Write-Host @"

`e[1mImport-DotEnv Module Help`e[0m

This module allows for hierarchical loading and unloading of .env files.
It also provides integration with `Set-Location` (cd/sl) to automatically
manage environment variables as you navigate directories.

`e[1mUsage:`e[0m

  `e[1mImport-DotEnv`e[0m [-Path <string>]
    Loads .env files from the specified path (or current directory if no path given)
    and its parent directories. Variables from deeper .env files take precedence.
    Automatically unloads variables from previously loaded .env files if they are
    no longer applicable or have changed.

  `e[1mImport-DotEnv -Unload`e[0m
    Unloads all variables set by the module and resets its internal state.

  `e[1mImport-DotEnv -List`e[0m
    Lists currently active variables and the .env files defining them.

  `e[1mImport-DotEnv -Help`e[0m
    Displays this help message.

For `Set-Location` integration, use `Enable-ImportDotEnvCdIntegration` and `Disable-ImportDotEnvCdIntegration`.
"@
    return
  }

  if ($PSCmdlet.ParameterSetName -eq 'List') {
    Write-Debug "MODULE Import-DotEnv: Called with -List switch."
    if (-not $script:previousEnvFiles -or $script:previousEnvFiles.Count -eq 0 -or $script:previousWorkingDirectory -eq "STATE_AFTER_EXPLICIT_UNLOAD") {
      Write-Host "No .env configuration is currently active or managed by ImportDotEnv." -ForegroundColor Magenta
      return
    }
    $effectiveVars = Get-EnvVarsFromFiles -Files $script:previousEnvFiles -BasePath $script:previousWorkingDirectory
    function Get-VarToFilesMap($files) {
      $map = @{}
      foreach ($file in $files) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
          foreach ($line in [System.IO.File]::ReadLines($file)) {
            $parsed = Parse-EnvLine $line
            if ($parsed) {
              $var = $parsed[0]
              if (-not $map[$var]) { $map[$var] = @() }
              $map[$var] += $file
            }
          }
        }
      }
      $map
    }
    $varToFiles = Get-VarToFilesMap $script:previousEnvFiles
    $outputObjects = $effectiveVars.Keys | Sort-Object | ForEach-Object {
      $var = $_
      $files = $varToFiles[$var]
      $hyperlink = Format-VarHyperlink -VarName $var -FilePath $files[0] -LineNumber 1
      [PSCustomObject]@{
        Name = $hyperlink
        'Defined In' = ($files | ForEach-Object { "  $(Get-RelativePath -Path $_ -BasePath $PWD.Path)" }) -join [Environment]::NewLine
      }
    }
    if ($outputObjects) {
      $outputObjects | Format-Table -AutoSize
    } else {
      Write-Host "No effective variables found in the active configuration." -ForegroundColor Yellow
    }
    return
  }

  # --- Load Parameter Set Logic (Default) ---
  Write-Debug "MODULE Import-DotEnv: Called with Path '$Path' (Load set). Current PWD: $($PWD.Path)"
  if ($PSCmdlet.ParameterSetName -eq 'Load' -and (-not $PSBoundParameters.ContainsKey('Path'))) {
    $Path = "."
  }
  try {
    $resolvedPath = Convert-Path -Path $Path -ErrorAction Stop
  } catch {
    $resolvedPath = $PWD.Path
    Write-Debug "MODULE Import-DotEnv: Path '$Path' resolved to PWD '$resolvedPath' due to error: $($_.Exception.Message)"
  }

  $currentEnvFiles = Get-EnvFilesUpstream -Directory $resolvedPath
  Write-Debug "MODULE Import-DotEnv: Resolved path '$resolvedPath'. Found $($currentEnvFiles.Count) .env files upstream: $($currentEnvFiles -join ', ')"
  Write-Debug "MODULE Import-DotEnv: Previous files count: $($script:previousEnvFiles.Count) ('$($script:previousEnvFiles -join ', ')'). Previous PWD: '$($script:previousWorkingDirectory)'"

  $prevVars = Get-EnvVarsFromFiles -Files $script:previousEnvFiles -BasePath $script:previousWorkingDirectory
  $currVars = Get-EnvVarsFromFiles -Files $currentEnvFiles -BasePath $resolvedPath

  # --- Unload Phase: Unset variables that were in prevVars but not in currVars, or if their value changed ---
  $varsToUnsetOrRestore = @()
  foreach ($varNameKey in $prevVars.Keys) {
    if (-not $currVars.ContainsKey($varNameKey) -or $currVars[$varNameKey].Value -ne $prevVars[$varNameKey].Value) {
      $varsToUnsetOrRestore += $varNameKey
    }
  }

  if ($varsToUnsetOrRestore.Count -gt 0) {
    $varsToRestoreByFileMap = Get-VarsToRestoreByFileMap -Files $script:previousEnvFiles -VarsToRestore $varsToUnsetOrRestore
    $varsCoveredByFileMap = $varsToRestoreByFileMap.Values | ForEach-Object { $_ } | Sort-Object -Unique
    $varsToRestoreNoFileAssociation = $varsToUnsetOrRestore | Where-Object { $varsCoveredByFileMap -notcontains $_ }
    Restore-EnvVars -VarsToRestoreByFileMap $varsToRestoreByFileMap -VarNames $varsToRestoreNoFileAssociation -TrueOriginalEnvironmentVariables $script:trueOriginalEnvironmentVariables -BasePath $PWD.Path
  }

  # --- Load Phase ---
  if ($currentEnvFiles.Count -gt 0) {
    foreach ($varNameKey in $currVars.Keys) {
      if (-not $script:trueOriginalEnvironmentVariables.ContainsKey($varNameKey)) {
        $currentEnvValue = [Environment]::GetEnvironmentVariable($varNameKey, 'Process')
        if (-not (Test-Path "Env:\$varNameKey")) {
          $script:trueOriginalEnvironmentVariables[$varNameKey] = $null
        } else {
          $script:trueOriginalEnvironmentVariables[$varNameKey] = $currentEnvValue
        }
      }
    }

    $varsToReportAsSetOrChanged = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($varNameKey in $currVars.Keys) {
      $desiredVarInfo = $currVars[$varNameKey]
      $desiredValue = $desiredVarInfo.Value
      $currentValue = [Environment]::GetEnvironmentVariable($varNameKey, 'Process')
      if ($currentValue -ne $desiredValue) {
        [Environment]::SetEnvironmentVariable($varNameKey, $desiredValue)
      }
      $isNewToSession = (-not $prevVars.ContainsKey($varNameKey))
      $hasValueChanged = $false
      if (-not $isNewToSession -and $prevVars[$varNameKey].Value -ne $desiredValue) {
          $hasValueChanged = $true
      }
      if ($isNewToSession -or $hasValueChanged) {
        $varsToReportAsSetOrChanged.Add(@{
            Name       = $varNameKey
            Line       = $desiredVarInfo.Line
            SourceFile = $desiredVarInfo.SourceFile
        })
      }
    }

    if ($varsToReportAsSetOrChanged.Count -gt 0) {
      $groupedBySourceFile = $varsToReportAsSetOrChanged | Group-Object -Property SourceFile
      foreach ($fileGroup in $groupedBySourceFile) {
        $sourceFilePath = $fileGroup.Name
        $formattedPath = Format-EnvFilePath -Path $sourceFilePath -BasePath $resolvedPath
        Write-Host "$script:itemiserA Processing .env file ${formattedPath}:" -ForegroundColor Cyan
        foreach ($varDetail in $fileGroup.Group) {
          $hyperlink = Format-VarHyperlink -VarName $varDetail.Name -FilePath $varDetail.SourceFile -LineNumber $varDetail.Line
          Write-Host "  $script:itemiser Setting environment variable: " -NoNewline
          Write-Host $hyperlink -ForegroundColor Green -NoNewline
          Write-Host " (from line $($varDetail.Line))"
        }
      }
    }
  }

  $script:previousEnvFiles = $currentEnvFiles
  $script:previousWorkingDirectory = $resolvedPath
}

# This function will be the wrapper for Set-Location
function Invoke-ImportDotEnvSetLocationWrapper {
  [CmdletBinding(DefaultParameterSetName = 'Path', SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
  param(
    [Parameter(ParameterSetName = 'Path', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [string]$Path,
    [Parameter(ParameterSetName = 'LiteralPath', Mandatory, ValueFromPipelineByPropertyName)]
    [Alias('PSPath')]
    [string]$LiteralPath,
    [Parameter()]
    [switch]$PassThru,
    [Parameter()]
    [string]$StackName
  )

  $slArgs = @{}
  if ($PSCmdlet.ParameterSetName -eq 'Path') {
    if ($PSBoundParameters.ContainsKey('Path')) { $slArgs.Path = $Path }
  } elseif ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
    $slArgs.LiteralPath = $LiteralPath
  }
  if ($PSBoundParameters.ContainsKey('PassThru')) { $slArgs.PassThru = $PassThru }
  if ($PSBoundParameters.ContainsKey('StackName')) { $slArgs.StackName = $StackName }

  $CommonParameters = @('Verbose', 'Debug', 'ErrorAction', 'ErrorVariable', 'WarningAction', 'WarningVariable',
    'OutBuffer', 'OutVariable', 'PipelineVariable', 'InformationAction', 'InformationVariable', 'WhatIf', 'Confirm')
  foreach ($commonParam in $CommonParameters) {
    if ($PSBoundParameters.ContainsKey($commonParam)) {
      $slArgs[$commonParam] = $PSBoundParameters[$commonParam]
    }
  }

  Microsoft.PowerShell.Management\Set-Location @slArgs
  Import-DotEnv -Path $PWD.Path
}

function Enable-ImportDotEnvCdIntegration {
  [CmdletBinding()]
  param()
  $currentModuleForEnable = $MyInvocation.MyCommand.Module
  if (-not $currentModuleForEnable) {
    Write-Error "Enable-ImportDotEnvCdIntegration: Module context not found." -ErrorAction Stop
  }
  if (-not $currentModuleForEnable.ExportedCommands.ContainsKey('Invoke-ImportDotEnvSetLocationWrapper')) {
    Write-Error "Enable-ImportDotEnvCdIntegration: Required wrapper 'Invoke-ImportDotEnvSetLocationWrapper' is not exported." -ErrorAction Stop
  }

  Write-Host "Enabling ImportDotEnv integration for 'Set-Location', 'cd', and 'sl' commands..." -ForegroundColor Yellow
  $wrapperFunctionFullName = "$($currentModuleForEnable.Name)\Invoke-ImportDotEnvSetLocationWrapper"
  $existingSetLocation = Get-Command Set-Location -ErrorAction SilentlyContinue
  if ($existingSetLocation -and $existingSetLocation.CommandType -eq [System.Management.Automation.CommandTypes]::Alias) {
    if (Get-Alias -Name Set-Location -ErrorAction SilentlyContinue) {
      Remove-Item -Path Alias:\Set-Location -Force -ErrorAction SilentlyContinue
    }
  }
  Set-Alias -Name Set-Location -Value $wrapperFunctionFullName -Scope Global -Force -Option ReadOnly,AllScope
  Import-DotEnv -Path $PWD.Path
  Write-Host "ImportDotEnv 'Set-Location', 'cd', 'sl' integration enabled!" -ForegroundColor Green
}

function Disable-ImportDotEnvCdIntegration {
  [CmdletBinding()]
  param()
  Write-Host "Disabling ImportDotEnv integration for 'Set-Location', 'cd', and 'sl'..." -ForegroundColor Yellow
  $currentModuleName = $MyInvocation.MyCommand.Module.Name
  if (-not $currentModuleName) {
    Write-Warning "Disable-ImportDotEnvCdIntegration: Could not determine module name. Assuming 'ImportDotEnv'."
    $currentModuleName = "ImportDotEnv"
  }
  $wrapperFunctionFullName = "$currentModuleName\Invoke-ImportDotEnvSetLocationWrapper"
  $proxiesRemoved = $false

  $slCmdInfo = Get-Command "Set-Location" -ErrorAction SilentlyContinue
  if ($slCmdInfo -and $slCmdInfo.CommandType -eq 'Alias' -and $slCmdInfo.Definition -eq $wrapperFunctionFullName) {
    Remove-Alias -Name "Set-Location" -Scope Global -Force -ErrorAction SilentlyContinue
    $proxiesRemoved = $true
  }

  Remove-Alias -Name "Set-Location" -Scope Global -Force -ErrorAction SilentlyContinue
  Remove-Item "Function:\Global:Set-Location" -Force -ErrorAction SilentlyContinue

  $finalSetLocation = Get-Command "Set-Location" -ErrorAction SilentlyContinue
  if ($null -eq $finalSetLocation -or $finalSetLocation.Source -ne "Microsoft.PowerShell.Management" -or $finalSetLocation.CommandType -ne 'Cmdlet') {
    Write-Warning "Disable-ImportDotEnvCdIntegration: 'Set-Location' may not be correctly restored to the original cmdlet."
  }

  if ($proxiesRemoved) {
    Write-Host "ImportDotEnv 'Set-Location' integration disabled, default command behavior restored." -ForegroundColor Magenta
  } else {
    Write-Host "ImportDotEnv 'Set-Location' integration was not active or already disabled." -ForegroundColor Magenta
  }
  Write-Host "Active .env variables (if any) remain loaded. Use 'Import-DotEnv -Unload' to unload them." -ForegroundColor Magenta
}

Export-ModuleMember -Function Import-DotEnv,
Enable-ImportDotEnvCdIntegration,
Disable-ImportDotEnvCdIntegration,
Invoke-ImportDotEnvSetLocationWrapper

function Restore-EnvVars {
  param(
    [hashtable]$VarsToRestoreByFileMap = $null,
    [string[]]$VarNames = $null,
    [hashtable]$TrueOriginalEnvironmentVariables,
    [string]$BasePath = $PWD.Path
  )
  $restorationActions = @()
  if ($VarsToRestoreByFileMap) {
    foreach ($fileKey in $VarsToRestoreByFileMap.Keys) {
      foreach ($var in $VarsToRestoreByFileMap[$fileKey]) {
        $restorationActions += [PSCustomObject]@{ VarName = $var; SourceFile = $fileKey }
      }
    }
  }
  if ($VarNames) {
    $restorationActions += $VarNames | ForEach-Object { [PSCustomObject]@{ VarName = $_; SourceFile = $null } }
  }

  function Restore-EnvVar {
    param(
      [string]$VarName,
      [hashtable]$TrueOriginalEnvironmentVariables,
      [string]$SourceFile = $null
    )
    function Set-OrUnset-EnvVar {
      param(
        [string]$Name,
        [object]$Value
      )
      if ($null -eq $Value) {
        [Environment]::SetEnvironmentVariable($Name, $null, 'Process')
        Remove-Item "Env:\$Name" -Force -ErrorAction SilentlyContinue
      } else {
        [Environment]::SetEnvironmentVariable($Name, $Value)
      }
    }

    $originalValue = $TrueOriginalEnvironmentVariables[$VarName]
    Set-OrUnset-EnvVar -Name $VarName -Value $originalValue
    $restoredActionText = if ($null -eq $originalValue) { "Unset" } else { "Restored" }
    $hyperlink = if ($SourceFile) {
      Format-VarHyperlink -VarName $VarName -FilePath $SourceFile -LineNumber 1
    } else {
      $searchUrl = "vscode://search/search?query=$([System.Uri]::EscapeDataString($VarName))"
      "$script:e]8;;$searchUrl$script:e\$VarName$script:e]8;;$script:e\"
    }
    Write-Host "  $script:itemiser $restoredActionText environment variable: " -NoNewline
    Write-Host ($hyperlink ?? $VarName) -ForegroundColor Yellow
  }

  $restorationActions | Group-Object SourceFile | ForEach-Object {
    $fileKey = $_.Name
    Write-Host ($fileKey ? "$script:itemiserA Restoring .env file $(Format-EnvFilePath -Path $fileKey -BasePath $BasePath):" : "Restoring environment variables not associated with any .env file:") -ForegroundColor Yellow
    $_.Group | ForEach-Object { Restore-EnvVar -VarName $_.VarName -TrueOriginalEnvironmentVariables $TrueOriginalEnvironmentVariables -SourceFile $_.SourceFile }
  }
}
