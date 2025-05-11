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
    $absolutePath = [Path]::GetFullPath($Path)
    $absoluteBasePath = [Path]::GetFullPath($BasePath)
  }
  catch {
    return $Path
  }

  if ($absolutePath -eq $absoluteBasePath) {
    return "."
  }

  $separator = [Path]::DirectorySeparatorChar
  $splitOptions = [StringSplitOptions]::RemoveEmptyEntries

  $pathSegments = $absolutePath.Split([Path]::DirectorySeparatorChar, $splitOptions)
  $baseSegments = $absoluteBasePath.Split([Path]::DirectorySeparatorChar, $splitOptions)

  $commonLength = 0
  $minLength = [Math]::Min($pathSegments.Count, $baseSegments.Count)

  while ($commonLength -lt $minLength -and
    $pathSegments[$commonLength] -eq $baseSegments[$commonLength]) {
    $commonLength++
  }

  if ($commonLength -eq 0) {
    return $absolutePath
  }

  $relativePath = New-Object System.Text.StringBuilder
  for ($i = $commonLength; $i -lt $baseSegments.Count; $i++) {
    [void]$relativePath.Append("..$separator")
  }

  for ($i = $commonLength; $i -lt $pathSegments.Count; $i++) {
    [void]$relativePath.Append($pathSegments[$i])
    if ($i -lt $pathSegments.Count - 1) {
      [void]$relativePath.Append($separator)
    }
  }

  return $relativePath.ToString()
}

function Get-EnvFilesUpstream {
  [CmdletBinding()]
  param([string]$Directory = ".")

  # ▼ Add path normalization ▼
  $currentDir = [Path]::GetFullPath($Directory).TrimEnd('\').ToLower()
  # ▲ Ensures consistent path formatting ▲

  try {
    $resolvedPath = Convert-Path -Path $Directory -ErrorAction Stop
  }
  catch {
    $resolvedPath = $PWD.Path
  }

  $envFiles = @()
  $currentDir = $resolvedPath

  while ($currentDir) {
    $envPath = Join-Path $currentDir ".env"
    if (Test-Path -LiteralPath $envPath -PathType Leaf) {
      $envFiles += $envPath
    }
    $parentDir = Split-Path -Path $currentDir -Parent
    # Break loop cleanly when reaching root
    if ($parentDir -eq $currentDir) { break }
    $currentDir = $parentDir
  }

  if ($envFiles.Count -gt 0) {
    [Array]::Reverse($envFiles)
  }
  # Ensure it always returns an array
  return $envFiles
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

# --- Helper function to get effective environment variables from a list of .env files ---
function Get-EnvVarsFromFiles {
  param([string[]]$Files, [string]$BasePath) # BasePath is for context if needed, not directly used in this version
  $vars = @{}
  foreach ($file in $Files) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
    $lines = Get-Content -Path $file -Encoding UTF8 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
      if ($line -match '^[ \t]*#') { continue } # Skip comments
      if ($line -match '^[ \t]*$') { continue }   # Skip empty lines
      if ($line -match '^([^=]+)=(.*)$') {
        $varName = $Matches[1].Trim()
        $varValue = $Matches[2].Trim()
        $vars[$varName] = $varValue # Later files override earlier ones for the same variable
      }
    }
  }
  return $vars
}

function Import-DotEnv {
  [CmdletBinding(DefaultParameterSetName = 'Load')]
  param(
    [Parameter(ParameterSetName = 'Load', Position = 0, ValueFromPipelineByPropertyName = $true)]
    [string]$Path,

    [Parameter(ParameterSetName = 'Unload')]
    [switch]$Unload,

    [Parameter(ParameterSetName = 'List')]
    [switch]$List
  )

  if ($PSCmdlet.ParameterSetName -eq 'Unload') {
    Write-Debug "MODULE Import-DotEnv: Called with -Unload switch."
    # Determine variables set by the last active .env configuration
    $varsFromLastLoad = Get-EnvVarsFromFiles -Files $script:previousEnvFiles -BasePath $script:previousWorkingDirectory

    if ($varsFromLastLoad.Count -gt 0) {
      Write-Host "`nUnloading active .env configuration..." -ForegroundColor Yellow

      foreach ($varName in $varsFromLastLoad.Keys) {
        # Restore to the true original value stored by the module
        if (-not $script:trueOriginalEnvironmentVariables.ContainsKey($varName)) {
            Write-Debug "MODULE Import-DotEnv (-Unload): No true original value recorded for '$varName'. Skipping restoration for it."
            continue
        }
        $originalValue = $script:trueOriginalEnvironmentVariables[$varName]
        if ($null -eq $originalValue) {
          Write-Debug "MODULE: Removing '$varName' (original value was null)"
          # Remove from .NET environment (Process scope only)
          [Environment]::SetEnvironmentVariable($varName, $null, 'Process')
          # Always attempt to remove from Env: drive at least once
          # NOTE: Never pass -Scope to Remove-Item for Env: drive! It is not supported and will throw.
          Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue
          $existsAfter = Test-Path "Env:\$varName"
          $dotNetValAfter = [Environment]::GetEnvironmentVariable($varName, 'Process')
          Write-Debug "MODULE Import-DotEnv (Unload): Final removal status for $varName - Exists in Env: $existsAfter, .NET value: '$dotNetValAfter'"
        }
        else {
          [Environment]::SetEnvironmentVariable($varName, $originalValue, 'Process')
        }
        $searchUrl = "vscode://search/search?query=$([System.Uri]::EscapeDataString($varName))"
        $hyperlinkedVarName = "$script:e]8;;$searchUrl$script:e\$varName$script:e]8;;$script:e\"
        $restoredActionText = if ($null -eq $originalValue) { "Unset" } else { "Restored" }
        Write-Host "  $script:itemiser $restoredActionText environment variable: " -NoNewline
        Write-Host $hyperlinkedVarName -ForegroundColor Yellow
      }
      # DO NOT CLEAR $script:trueOriginalEnvironmentVariables here. It holds the actual pre-module state.
      # $script:trueOriginalEnvironmentVariables.Clear() # This line is removed.
      $script:previousEnvFiles = @()
      $script:previousWorkingDirectory = "STATE_AFTER_EXPLICIT_UNLOAD" # Mark state
      Write-Host "Environment restored. Module state reset." -ForegroundColor Green
    }
    else {
      Write-Host "No active .env configuration found by the module to unload." -ForegroundColor Magenta
    }
    return
  }

  if ($PSCmdlet.ParameterSetName -eq 'List') {
    Write-Debug "MODULE Import-DotEnv: Called with -List switch."
    if (-not $script:previousEnvFiles -or $script:previousEnvFiles.Count -eq 0 -or $script:previousWorkingDirectory -eq "STATE_AFTER_EXPLICIT_UNLOAD") {
      Write-Host "No .env configuration is currently active or managed by ImportDotEnv." -ForegroundColor Magenta
      return
    }

    # Get the final effective values of variables as per the last load
    $effectiveVars = Get-EnvVarsFromFiles -Files $script:previousEnvFiles -BasePath $script:previousWorkingDirectory

    # Build a map of variable names to the list of files that define them
    $varToDefiningFilesMap = @{}
    foreach ($file in $script:previousEnvFiles) {
      if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
      $lines = Get-Content -Path $file -Encoding UTF8 -ErrorAction SilentlyContinue
      foreach ($line in $lines) {
        if ($line -match '^[ \t]*#') { continue }
        if ($line -match '^[ \t]*$') { continue }
        if ($line -match '^([^=]+)=(.*)$') {
          $varName = $Matches[1].Trim()
          if (-not $varToDefiningFilesMap.ContainsKey($varName)) {
            $varToDefiningFilesMap[$varName] = [System.Collections.Generic.List[string]]::new()
          }
          $varToDefiningFilesMap[$varName].Add($file)
        }
      }
    }

    $outputObjects = @()
    foreach ($varName in ($effectiveVars.Keys | Sort-Object)) {
      $varValue = $effectiveVars[$varName]

      # Create hyperlink for Name
      $searchUrl = "vscode://search/search?query=$([System.Uri]::EscapeDataString($varName))"
      $hyperlinkedVarName = "$($script:e)]8;;$searchUrl$($script:e)\$varName$($script:e)]8;;$($script:e)\"

      $definedInFilesDisplayString = ""
      if ($varToDefiningFilesMap.ContainsKey($varName)) {
        $relativePathsWithItemiser = @()
        foreach ($filePath in $varToDefiningFilesMap[$varName]) {
          $relativePathsWithItemiser += "  $(Get-RelativePath -Path $filePath -BasePath $PWD.Path)" # Removed itemiser, added indent
        }
        $definedInFilesDisplayString = $relativePathsWithItemiser -join [System.Environment]::NewLine
      }

      $outputObjects += [PSCustomObject]@{
        Name        = $hyperlinkedVarName
        # Value       = $varValue # Removed Value column
        'Defined In'= $definedInFilesDisplayString
      }
    }

    if ($outputObjects.Count -gt 0) {
      $outputObjects | Format-Table -AutoSize
    } else {
      Write-Host "No effective variables found in the active configuration." -ForegroundColor Yellow
    }
    # Write-Host "--------------------------------------------------" -ForegroundColor Cyan
    return
  }

  # --- Load Parameter Set Logic (existing logic) ---
  Write-Debug "MODULE Import-DotEnv: Called with Path '$Path' (Load set). Current PWD: $($PWD.Path)"
  if ($PSCmdlet.ParameterSetName -eq 'Load' -and (-not $PSBoundParameters.ContainsKey('Path'))) {
    $Path = "."
    Write-Debug "MODULE Import-DotEnv: Path not bound for 'Load' set, defaulted to '$Path'."
  }
  try {
    $resolvedPath = Convert-Path -Path $Path -ErrorAction Stop
  }
  catch {
    $resolvedPath = $PWD.Path
    Write-Debug "MODULE Import-DotEnv: Path '$Path' resolved to PWD '$resolvedPath' due to error: $($_.Exception.Message)"
  }

  $currentEnvFiles = Get-EnvFilesUpstream -Directory $resolvedPath
  # if ($null -eq $currentEnvFiles) { # Assuming Get-EnvFilesUpstream ALWAYS returns an array (even if empty)
  #   Write-Debug "MODULE Import-DotEnv: Get-EnvFilesUpstream call resulted in null for '$resolvedPath'. This is unexpected. Defaulting to empty array."
  #   $currentEnvFiles = @()
  # }
  Write-Debug "MODULE Import-DotEnv: Resolved path '$resolvedPath'. Found $($currentEnvFiles.Count) .env files upstream: $($currentEnvFiles -join ', ')"
  Write-Debug "MODULE Import-DotEnv: Previous files count: $($script:previousEnvFiles.Count) ('$($script:previousEnvFiles -join ', ')'). Previous PWD: '$($script:previousWorkingDirectory)'"

  # --- New: Build hashtables of previous and current env states ---
  $prevVars = Get-EnvVarsFromFiles -Files $script:previousEnvFiles -BasePath $script:previousWorkingDirectory
  $currVars = Get-EnvVarsFromFiles -Files $currentEnvFiles -BasePath $resolvedPath

  # --- Unload Phase: Only unset variables that are in prevVars but not in currVars, or changed value ---
  Write-Debug "MODULE Import-DotEnv (Unload Phase): Current trueOriginalEnvironmentVariables keys: $($script:trueOriginalEnvironmentVariables.Keys -join ', ')"
  $varsToUnset = @()
  foreach ($var in $prevVars.Keys) {
    if (-not $currVars.ContainsKey($var) -or $currVars[$var] -ne $prevVars[$var]) {
      $varsToUnset += $var
    }
  }
  if ($varsToUnset.Count -gt 0) {
    # Group variables to unset by their originating .env file
    $varToFileMap = @{}
    foreach ($file in $script:previousEnvFiles) {
      if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
      $lines = Get-Content -Path $file -Encoding UTF8 -ErrorAction SilentlyContinue
      $lineNumber = 0
      foreach ($line in $lines) {
        $lineNumber++
        if ($line -match '^[ \t]*#') { continue }
        if ($line -match '^[ \t]*$') { continue }
        if ($line -match '^([^=]+)=(.*)$') {
          $varName = $Matches[1].Trim()
          if ($varsToUnset -contains $varName) {
            if (-not $varToFileMap.ContainsKey($file)) { $varToFileMap[$file] = @() }
            $varToFileMap[$file] += $varName
          }
        }
      }
    }
    # Find any vars not associated with a file (e.g. removed from all .env files)
    $varsWithFile = $varToFileMap.Values | ForEach-Object { $_ } | Sort-Object -Unique
    $varsNoFile = $varsToUnset | Where-Object { $varsWithFile -notcontains $_ }
    if ($varToFileMap.Count -gt 0) {
      foreach ($file in $script:previousEnvFiles) {
        if (-not $varToFileMap.ContainsKey($file)) { continue }
        $varsForFile = $varToFileMap[$file]
        if ($varsForFile.Count -eq 0) { continue } # Only print header if there are actions
        $formattedPath = Format-EnvFilePath -Path $file -BasePath $PWD
        Write-Host "$script:itemiserA Restoring .env file ${formattedPath}:" -ForegroundColor Yellow
        foreach ($varName in $varsForFile) {
          $originalValue = $script:trueOriginalEnvironmentVariables[$varName]
          Write-Debug "MODULE Import-DotEnv (Unload Phase): For var '$varName' from file '$formattedPath', original value from trueOriginals is '$originalValue'."
          if ($null -eq $originalValue) {
            [Environment]::SetEnvironmentVariable($varName, $null, 'Process')
            Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue
            $retryCount = 0
            while ($retryCount -lt 2 -and (Test-Path "Env:\$varName")) {
              Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue
              $retryCount++
              # Removed Start-Sleep for performance
            }
          } else {
            [Environment]::SetEnvironmentVariable($varName, $originalValue)
          }
          $searchUrl = "vscode://search/search?query=$([System.Uri]::EscapeDataString($varName))"
          $hyperlinkedVarName = "$script:e]8;;$searchUrl$script:e\$varName$script:e]8;;$script:e\"
          $restoredActionText = if ($null -eq $originalValue) { "Unset" } else { "Restored" }
          Write-Host "  $script:itemiser $restoredActionText environment variable: " -NoNewline
          Write-Host $hyperlinkedVarName -ForegroundColor Yellow
        }
      }
    }
    if ($varsNoFile.Count -gt 0) {
      Write-Host "Restoring environment variables not associated with any .env file:" -ForegroundColor Yellow
      foreach ($varName in $varsNoFile) {
        $originalValue = $script:trueOriginalEnvironmentVariables[$varName]
        Write-Debug "MODULE Import-DotEnv (Unload Phase): For var '$varName' (no file association), original value from trueOriginals is '$originalValue'."
        if ($null -eq $originalValue) {
          [Environment]::SetEnvironmentVariable($varName, $null, 'Process')
          Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue
          $retryCount = 0
          while ($retryCount -lt 2 -and (Test-Path "Env:\$varName")) {
            Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue
            $retryCount++
            # Removed Start-Sleep for performance
          }
        } else {
          [Environment]::SetEnvironmentVariable($varName, $originalValue)
        }
        $searchUrl = "vscode://search/search?query=$([System.Uri]::EscapeDataString($varName))"
        $hyperlinkedVarName = "$script:e]8;;$searchUrl$script:e\$varName$script:e]8;;$script:e\"
        $restoredActionText = if ($null -eq $originalValue) { "Unset" } else { "Restored" }
        Write-Host "  $script:itemiser $restoredActionText environment variable: " -NoNewline
        Write-Host $hyperlinkedVarName -ForegroundColor Yellow
      }
    }
    # --- Restore any original env vars not already handled (e.g. global/pre-existing vars) ---
    # The $varsToUnset (partitioned into $varsWithFile and $varsNoFile) should cover all variables
    # from the previous .env configuration ($prevVars) that need to be restored.
    # This block for "unhandledVars" is likely redundant if $varsToUnset is comprehensive and correctly
    # uses $script:trueOriginalEnvironmentVariables for restoration values.
    # $handledVars = @($varsWithFile + $varsNoFile) # These are all from $varsToUnset
    # $unhandledVars = $script:trueOriginalEnvironmentVariables.Keys | Where-Object { $handledVars -notcontains $_ -and $prevVars.ContainsKey($_) }
    # if ($unhandledVars.Count -gt 0) {
    #   Write-Host "Restoring pre-existing environment variables (unhandled by file association):" -ForegroundColor Yellow
    #   foreach ($varName in $unhandledVars) {
    #     $originalValue = $script:trueOriginalEnvironmentVariables[$varName]
    #     if ($null -eq $originalValue) {
    #       [Environment]::SetEnvironmentVariable($varName, $null, 'Process')
    #       Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue
    #       $retryCount = 0
    #       while ($retryCount -lt 3 -and (Test-Path "Env:\$varName")) {
    #         Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue
    #         $retryCount++
    #         Start-Sleep -Milliseconds 100
    #       }
    #     } else {
    #       [Environment]::SetEnvironmentVariable($varName, $originalValue)
    #     }
    #     $searchUrl = "vscode://search/search?query=$([System.Uri]::EscapeDataString($varName))"
    #     $hyperlinkedVarName = "$script:e]8;;$searchUrl$script:e\$varName$script:e]8;;$script:e\"
    #     $restoredActionText = if ($null -eq $originalValue) { "Unset" } else { "Restored" }
    #     Write-Host "  $script:itemiser $restoredActionText environment variable: " -NoNewline
    #     Write-Host $hyperlinkedVarName -ForegroundColor Yellow
    #   }
    # }
  }
  # DO NOT CLEAR $script:trueOriginalEnvironmentVariables. This is the critical change for differential behavior.
  # $script:trueOriginalEnvironmentVariables.Clear() # This line is removed.

  Write-Debug "MODULE Import-DotEnv (Load Phase - Start): Current trueOriginalEnvironmentVariables keys before capture: $($script:trueOriginalEnvironmentVariables.Keys -join ', ')"
  # --- Load Phase: Ensure all variables in currVars are set to their correct value (even if previously shadowed) ---
  if ($currentEnvFiles.Count -gt 0) {
    # First, collect all variables that will be set by any .env file in this load cycle (regardless of diff)
    $allVarsToSet = @{
    }
    $fileVarLineMap = @{
    }
    foreach ($file in $currentEnvFiles) {
      if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
      $lines = Get-Content -Path $file -Encoding UTF8 -ErrorAction SilentlyContinue
      $lineNumber = 0
      foreach ($line in $lines) {
        $lineNumber++
        if ($line -match '^[ \t]*#') { continue }
        if ($line -match '^[ \t]*$') { continue }
        if ($line -match '^([^=]+)=(.*)$') {
          $varName = $Matches[1].Trim()
          $allVarsToSet[$varName] = $true
        }
      }
    }
    # Capture original values for all variables to be set, only if not already stored
    foreach ($varName in $allVarsToSet.Keys) {
      if (-not $script:trueOriginalEnvironmentVariables.ContainsKey($varName)) {
        $currentEnvValue = [Environment]::GetEnvironmentVariable($varName, 'Process')
        # Distinguish between not set (null) and set to empty string ('')
        if (-not (Test-Path "Env:\$varName")) {
          Write-Debug "MODULE Import-DotEnv (Load Phase - Capture): Storing original for '$varName' as `$null (not set)."
          $script:trueOriginalEnvironmentVariables[$varName] = $null
        } else {
          Write-Debug "MODULE Import-DotEnv (Load Phase - Capture): Storing original for '$varName' as '$currentEnvValue'."
          $script:trueOriginalEnvironmentVariables[$varName] = $currentEnvValue
        }
      }
    }
    Write-Debug "MODULE Import-DotEnv (Load Phase - End Capture): Current trueOriginalEnvironmentVariables keys after capture: $($script:trueOriginalEnvironmentVariables.Keys -join ', ')"
    # Now, for every variable in currVars, ensure it is set to the correct value (even if previously shadowed)
    foreach ($varName in $currVars.Keys) {
      $desiredValue = $currVars[$varName]
      $currentValue = [Environment]::GetEnvironmentVariable($varName, 'Process')
      if ($currentValue -ne $desiredValue) {
        [Environment]::SetEnvironmentVariable($varName, $desiredValue)
      }
    }
    # Continue with the existing logic for output and per-file reporting
    $alreadySet = @{
    }
    foreach ($file in $currentEnvFiles) {
      if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
      $lines = Get-Content -Path $file -Encoding UTF8 -ErrorAction SilentlyContinue
      $lineNumber = 0
      $varsToSet = @()
      $varLineMap = @{
      }
      foreach ($line in $lines) {
        $lineNumber++
        if ($line -match '^[ \t]*#') { continue }
        if ($line -match '^[ \t]*$') { continue }
        if ($line -match '^([^=]+)=(.*)$') {
          $varName = $Matches[1].Trim()
          $varValue = $Matches[2].Trim()
          if ($alreadySet.ContainsKey($varName)) { continue } # Only set once per load
          if (-not $prevVars.ContainsKey($varName) -or $prevVars[$varName] -ne $varValue) {
            $varsToSet += $varName
            $varLineMap[$varName] = $lineNumber
          }
        }
      }
      if ($varsToSet.Count -gt 0) {
        $formattedPath = Format-EnvFilePath -Path $file -BasePath $script:previousWorkingDirectory
        Write-Host "$script:itemiserA Processing .env file ${formattedPath}:" -ForegroundColor Cyan
        foreach ($varName in $varsToSet) {
          $lineNumber = $varLineMap[$varName]
          $varValue = $currVars[$varName]
          $fileUrl = "vscode://file/${file}:${lineNumber}"
          $hyperlink = "$script:e]8;;$fileUrl$script:e\$varName$script:e]8;;$script:e\"
          Write-Host "  $script:itemiser Setting environment variable: " -NoNewline
          Write-Host $hyperlink -ForegroundColor Green -NoNewline
          Write-Host " (from line ${lineNumber})"
          $alreadySet[$varName] = $true
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

  # Determine the parameter set used for the wrapper and add appropriate parameters
  if ($PSCmdlet.ParameterSetName -eq 'Path') {
    # Add Path only if it was explicitly bound.
    # Set-Location can be called with no arguments (goes to home) or with a path resolving to a PSDrive.
    # If $Path was bound (even to $null or empty string from an expression), it should be in $PSBoundParameters.
    if ($PSBoundParameters.ContainsKey('Path')) {
      $slArgs.Path = $Path
    }
  }
  elseif ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
    # LiteralPath is mandatory in its set, so it will always be in $PSBoundParameters if this set is used.
    $slArgs.LiteralPath = $LiteralPath
  }

  # Add optional parameters if they were bound
  if ($PSBoundParameters.ContainsKey('PassThru')) {
    $slArgs.PassThru = $PassThru # $PassThru is a switch, its value will be $true if present
  }
  if ($PSBoundParameters.ContainsKey('StackName')) {
    $slArgs.StackName = $StackName
  }

  # Forward common parameters if they were used on the wrapper
  $CommonParameters = @('Verbose', 'Debug', 'ErrorAction', 'ErrorVariable', 'WarningAction', 'WarningVariable',
    'OutBuffer', 'OutVariable', 'PipelineVariable', 'InformationAction', 'InformationVariable')
  foreach ($commonParam in $CommonParameters) {
    if ($PSBoundParameters.ContainsKey($commonParam)) {
      $slArgs[$commonParam] = $PSBoundParameters[$commonParam]
    }
  }
  # Handle SupportsShouldProcess common parameters
  if ($PSBoundParameters.ContainsKey('WhatIf')) { $slArgs.WhatIf = $PSBoundParameters.WhatIf }
  if ($PSBoundParameters.ContainsKey('Confirm')) { $slArgs.Confirm = $PSBoundParameters.Confirm }

  # Pre-calculate the debug string to avoid complex expressions directly in Write-Debug
  # Also, correctly iterate hashtable key-value pairs using GetEnumerator()
  $debugArgsString = ($slArgs.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" } | Sort-Object) -join '; '
  Write-Debug "Invoke-ImportDotEnvSetLocationWrapper: Calling Microsoft.PowerShell.Management\Set-Location with args: $debugArgsString"
  # Call the original Set-Location cmdlet
  # Ensure we call the cmdlet from the Microsoft.PowerShell.Management module
  # to avoid recursion if Set-Location is aliased to this wrapper.
  Microsoft.PowerShell.Management\Set-Location @slArgs

  Import-DotEnv -Path $PWD.Path # And our logic
}

# Helper function to create the scriptblock for cd/sl wrappers
function New-SetLocationWrapperScriptBlock {
  param([string]$TargetFunctionFullName)

  # This scriptblock defines a function that correctly captures Set-Location's parameters
  # and forwards them to the target function (Invoke-ImportDotEnvSetLocationWrapper).
  return [scriptblock]::Create(@"
[CmdletBinding(DefaultParameterSetName='Path', SupportsShouldProcess=`$true, ConfirmImpact='Medium')]
param(
    [Parameter(ParameterSetName='Path', Position=0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [string]`$Path,

    [Parameter(ParameterSetName='LiteralPath', Mandatory, ValueFromPipelineByPropertyName)]
    [Alias('PSPath')]
    [string]`$LiteralPath,

    [Parameter()]
    [switch]`$PassThru,

    [Parameter()]
    [string]`$StackName
)
& $TargetFunctionFullName @PSBoundParameters
"@)
}

function Enable-ImportDotEnvCdIntegration {
  [CmdletBinding()]
  param()

  $currentModuleForEnable = $MyInvocation.MyCommand.Module # Use a distinct variable name
  if (-not $currentModuleForEnable) {
    Write-Warning "Enable-ImportDotEnvCdIntegration: CRITICAL - Module could not be determined via `$MyInvocation.MyCommand.Module."
    Write-Error "Aborting Enable-ImportDotEnvCdIntegration: Module context not found." # More assertive stop
    return
  }
  Write-Debug "Enable-ImportDotEnvCdIntegration: Module '$($currentModuleForEnable.Name)' found. Checking ExportedCommands..."

  if (-not $currentModuleForEnable.ExportedCommands.ContainsKey('Invoke-ImportDotEnvSetLocationWrapper')) {
    Write-Warning "Enable-ImportDotEnvCdIntegration: CRITICAL - 'Invoke-ImportDotEnvSetLocationWrapper' IS NOT in ExportedCommands of module '$($currentModuleForEnable.Name)'. Available: $($currentModuleForEnable.ExportedCommands.Keys -join ', ')"
    Write-Error "Aborting Enable-ImportDotEnvCdIntegration: Required wrapper function 'Invoke-ImportDotEnvSetLocationWrapper' is not exported." # More assertive stop
    return
  }
  Write-Debug "Enable-ImportDotEnvCdIntegration: 'Invoke-ImportDotEnvSetLocationWrapper' IS in ExportedCommands."

  Write-Host "Enabling ImportDotEnv integration for 'Set-Location', 'cd', and 'sl' commands..." -ForegroundColor Yellow
  Write-Host "These commands will now also trigger .env file processing." -ForegroundColor Yellow
  Write-Host "To disable, run 'Disable-ImportDotEnvCdIntegration'." -ForegroundColor Yellow

  # The target for the alias is the fully qualified name of our wrapper function
  # We use $currentModuleForEnable.Name which we've already validated exists.
  $wrapperFunctionFullName = "$($currentModuleForEnable.Name)\Invoke-ImportDotEnvSetLocationWrapper"
  Write-Debug "Enable-ImportDotEnvCdIntegration: Determined wrapper function full name: '$wrapperFunctionFullName'"

  # --- Phase 1: Cleanup existing commands ---
  Write-Debug "Enable-ImportDotEnvCdIntegration: Phase 1 - Cleanup"
  $existingSetLocation = Get-Command Set-Location -ErrorAction SilentlyContinue
  if ($existingSetLocation -and $existingSetLocation.CommandType -eq [System.Management.Automation.CommandTypes]::Alias) {
    Write-Debug "Enable-ImportDotEnvCdIntegration: Removing existing Set-Location alias."
    if (Get-Alias -Name Set-Location -ErrorAction SilentlyContinue) {
      Remove-Item -Path Alias:\Set-Location -Force -ErrorAction SilentlyContinue
    }
  }

  # --- Phase 2: Define new commands/aliases ---
  Write-Debug "Enable-ImportDotEnvCdIntegration: Phase 2 - Definition"
  Write-Debug "About to Set-Alias Set-Location. Value: '$wrapperFunctionFullName' (Type: $($wrapperFunctionFullName.GetType().Name))"

  # Check if Get-Command can resolve the fully qualified name at this moment.
  # This is a check for PowerShell's command resolution cache. Failure here is not necessarily fatal
  # if the function is confirmed exported, as Set-Alias defers full resolution to invocation time.
  $resolvedTargetCmd = Get-Command $wrapperFunctionFullName -ErrorAction SilentlyContinue
  if (-not $resolvedTargetCmd) {
    Write-Debug "Enable-ImportDotEnvCdIntegration: NOTE - Get-Command could not resolve '$wrapperFunctionFullName' at this exact moment. This can be a transient command cache issue. Alias will likely still work if function is exported."
  }

  Set-Alias -Name Set-Location -Value $wrapperFunctionFullName -Scope Global -Force -Option ReadOnly, AllScope

  # Process .env files for the current directory immediately upon enabling
  Write-Debug "Enable-ImportDotEnvCdIntegration: Processing .env for current directory: $($PWD.Path)"
  Import-DotEnv -Path $PWD.Path

  Write-Host "ImportDotEnv 'Set-Location', 'cd', 'sl' integration enabled!" -ForegroundColor Green
}

function Disable-ImportDotEnvCdIntegration {
  [CmdletBinding()]
  param()

  Write-Host "Disabling ImportDotEnv integration for 'Set-Location', 'cd', and 'sl'..." -ForegroundColor Yellow
  $currentModuleName = $MyInvocation.MyCommand.Module.Name
  if (-not $currentModuleName) {
    # This can happen if the function is dot-sourced or called in a way that $MyInvocation.MyCommand.Module is not populated.
    # Fallback to a hardcoded name, or error out if strictness is required.
    Write-Warning "Disable-ImportDotEnvCdIntegration: Could not determine current module name dynamically. Falling back to 'ImportDotEnv'."
    $currentModuleName = "ImportDotEnv" # Fallback assumption
  }
  $wrapperFunctionFullName = "$currentModuleName\Invoke-ImportDotEnvSetLocationWrapper"
  $proxiesRemoved = $false # Renamed for clarity

  # Phase 1: Remove our specific proxies if they exist
  Write-Debug "Disable-ImportDotEnvCdIntegration: Phase 1 - Removing proxies."

  # For Set-Location (was an alias to our wrapper)
  $slCmdInfoForDisable = Get-Command "Set-Location" -ErrorAction SilentlyContinue
  Write-Debug "Disable-ImportDotEnvCdIntegration: Checking Set-Location. Found: Type '$($slCmdInfoForDisable.CommandType)', Definition '$($slCmdInfoForDisable.Definition)'. Expected Wrapper: '$wrapperFunctionFullName'."
  if ($slCmdInfoForDisable -and $slCmdInfoForDisable.CommandType -eq [System.Management.Automation.CommandTypes]::Alias -and $slCmdInfoForDisable.Definition -eq $wrapperFunctionFullName) {
    Remove-Alias -Name "Set-Location" -Scope Global -Force -ErrorAction SilentlyContinue
    Write-Debug " - 'Set-Location' (ImportDotEnv alias proxy) removed."
    $proxiesRemoved = $true
  }

  # Phase 2: Ensure default states are robustly restored
  Write-Debug "Disable-ImportDotEnvCdIntegration: Phase 2 - Ensuring default command states."

  # Ensure Set-Location is the original cmdlet
  # Remove any alias or function that might be obscuring the original cmdlet
  Write-Debug "Disable-ImportDotEnvCdIntegration: Restoring Set-Location to original cmdlet."
  Remove-Alias -Name "Set-Location" -Scope Global -Force -ErrorAction SilentlyContinue
  Remove-Item "Function:\Global:Set-Location" -Force -ErrorAction SilentlyContinue
  $finalSetLocation = Get-Command "Set-Location" -ErrorAction SilentlyContinue
  if ($null -eq $finalSetLocation) {
    Write-Warning " - CRITICAL: 'Set-Location' command is missing after attempting to restore defaults."
  }
  elseif ($finalSetLocation.Source -ne "Microsoft.PowerShell.Management" -or $finalSetLocation.CommandType -ne [System.Management.Automation.CommandTypes]::Cmdlet) {
    Write-Warning " - 'Set-Location' may not be correctly restored. Expected Cmdlet from Microsoft.PowerShell.Management. Found Type: $($finalSetLocation.CommandType), Source: $($finalSetLocation.Source)."
  }
  else {
    Write-Debug " - 'Set-Location' confirmed as original cmdlet."
  }

  # By design now, Disable-ImportDotEnvCdIntegration does not unload variables.
  # It only removes the command hooks.
  # The module's state ($script:originalEnvironmentVariables, $script:previousEnvFiles, etc.)
  # remains as it was, so a subsequent Import-DotEnv call will behave correctly
  # based on that last known state.

  # Final message
  if ($proxiesRemoved) {
    Write-Host "ImportDotEnv 'Set-Location' integration disabled, default command behavior restored." -ForegroundColor Magenta
  }
  else {
    Write-Host "ImportDotEnv 'Set-Location' integration was not active or already disabled." -ForegroundColor Magenta
  }
  Write-Host "Active .env variables (if any) remain loaded. Use 'Import-DotEnv -Unload' to unload them, or 'Import-DotEnv -Path <new_path>' to change." -ForegroundColor Magenta
}

Export-ModuleMember -Function Import-DotEnv,
Enable-ImportDotEnvCdIntegration,
Disable-ImportDotEnvCdIntegration,
Invoke-ImportDotEnvSetLocationWrapper
