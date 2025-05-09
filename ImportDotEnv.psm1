# DotEnv.psm1

# Requires -Version 5.1

using namespace System.IO
using namespace System.Management.Automation

$script:originalEnvironmentVariables = @{} # Stores { VarName = OriginalValueOrNull }
$script:previousEnvFiles = @()
$script:previousWorkingDirectory = $PWD.Path
$script:e = [char]27
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
  param(
    [string]$Directory = "."
  )

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

function Format-EnvFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$EnvFile,
    [Parameter(Mandatory)]
    [string]$BasePath
  )

  # This function now only handles loading. Unloading/restoration is done in Import-DotEnv.
  if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
    return
  }

  $formattedPath = Format-EnvFilePath -Path $EnvFile -BasePath $BasePath
  Write-Host "Processing .env file ${formattedPath}:" -ForegroundColor Cyan

  $lineNumber = 0
  switch -Regex -File $EnvFile {
    '^\s*#.*' { $lineNumber++; continue } # Skip comments, count line
    '^\s*$' { $lineNumber++; continue }   # Skip empty lines, count line

    '^([^=]+)=(.*)$' {
      $lineNumber++
      $varName = $Matches[1].Trim()
      $varValue = $Matches[2].Trim()

      # Store original value IF NOT ALREADY STORED FOR THIS LOAD CYCLE
      if (-not $script:originalEnvironmentVariables.ContainsKey($varName)) {
        # If the variable doesn't exist according to Test-Path, its original state is $null.
        # Otherwise, capture its current value (which could be an empty string).
        if (-not (Test-Path "Env:\$varName")) {
          $script:originalEnvironmentVariables[$varName] = $null
          Write-Debug "MODULE Format-EnvFile: Storing original value for '$varName' as `$null (Test-Path was false)."
        } else {
          $script:originalEnvironmentVariables[$varName] = [Environment]::GetEnvironmentVariable($varName)
          Write-Debug "MODULE Format-EnvFile: Storing original value for '$varName': '$($script:originalEnvironmentVariables[$varName])' (Test-Path was true)."
        }
      }
      [Environment]::SetEnvironmentVariable($varName, $varValue)
      Write-Debug "MODULE Format-EnvFile: Set '$varName' to '$varValue'. Current value in env: '$([Environment]::GetEnvironmentVariable($varName))'"

      $fileUrl = "vscode://file/${EnvFile}:${lineNumber}"
      $hyperlink = "$script:e]8;;$fileUrl$script:e\$varName$script:e]8;;$script:e\"

      Write-Host "  $script:itemiser Setting environment variable: " -NoNewline
      Write-Host $hyperlink -ForegroundColor Green -NoNewline
      Write-Host " (from line ${lineNumber})"
    }
    default { $lineNumber++ } # Count other lines not matching the pattern
  }
}

function Import-DotEnv {
  [CmdletBinding()]
  param(
    [string]$Path = "."
  )
  Write-Debug "MODULE Import-DotEnv: Called with Path '$Path'. Current PWD: $($PWD.Path)"

  try {
    $resolvedPath = Convert-Path -Path $Path -ErrorAction Stop
  }
  catch {
    $resolvedPath = $PWD.Path
    Write-Debug "MODULE Import-DotEnv: Path '$Path' resolved to PWD '$resolvedPath' due to error: $($_.Exception.Message)"
  }

  $currentEnvFiles = Get-EnvFilesUpstream -Directory $resolvedPath

  # If Get-EnvFilesUpstream terminated unexpectedly (e.g., due to an internal error),
  # $currentEnvFiles might be $null. Compare-Object requires a collection for -DifferenceObject.
  if ($null -eq $currentEnvFiles) {
    Write-Debug "MODULE Import-DotEnv: Get-EnvFilesUpstream returned null for '$resolvedPath'. Defaulting to empty array."
    $currentEnvFiles = @() # Default to an empty array
  }
  Write-Debug "MODULE Import-DotEnv: Resolved path '$resolvedPath'. Found $($currentEnvFiles.Count) .env files upstream: $($currentEnvFiles -join ', ')"
  Write-Debug "MODULE Import-DotEnv: Previous files count: $($script:previousEnvFiles.Count) ('$($script:previousEnvFiles -join ', ')'). Previous PWD: '$($script:previousWorkingDirectory)'"

  $comparison = Compare-Object -ReferenceObject $script:previousEnvFiles -DifferenceObject $currentEnvFiles
  if (-not $comparison -and $script:previousWorkingDirectory -eq $resolvedPath) {
    Write-Debug "MODULE Import-DotEnv: No changes detected for '$resolvedPath'. Returning."
    return
  }

  # --- Unload Phase: Restore variables managed by the previous state ---
  if ($script:originalEnvironmentVariables.Count -gt 0) {
    # This check might be too simple if we always want to clear
    Write-Host "`nRestoring environment from previous configuration:" -ForegroundColor Yellow
    # Clone keys because we might be modifying the collection if we were to remove, though here we just clear after.
    $varsToRestore = $script:originalEnvironmentVariables.Keys | ForEach-Object { $_ }
    foreach ($varName in $varsToRestore) {
      $originalValue = $script:originalEnvironmentVariables[$varName]
      # Explicitly handle $null for unsetting
      if ($null -eq $originalValue) {
        Write-Debug "MODULE Import-DotEnv (Unload): Restoring '$varName'. Original value was type: null, IsNull: $true, Value: '$originalValue'"
        Write-Debug "MODULE Import-DotEnv (Unload): Calling [Environment]::SetEnvironmentVariable('$varName', `$null) to remove it."
        [Environment]::SetEnvironmentVariable($varName, $null)
        # Also try to remove it via PowerShell's provider to be sure
        if (Test-Path "Env:\$varName") {
            Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue
        }
      } else {
        Write-Debug "MODULE Import-DotEnv (Unload): Restoring '$varName'. Original value was type: $($originalValue.GetType().Name), IsNull: $($null -eq $originalValue), Value: '$originalValue'"
        Write-Debug "MODULE Import-DotEnv (Unload): Calling [Environment]::SetEnvironmentVariable('$varName', '$originalValue') to restore it."
        [Environment]::SetEnvironmentVariable($varName, $originalValue)
      }
      Write-Debug "MODULE Import-DotEnv (Unload): After SetEnvironmentVariable for '$varName', current env value is '$([Environment]::GetEnvironmentVariable($varName))', IsNull: $($null -eq [Environment]::GetEnvironmentVariable($varName))"

      # Construct a hyperlink that could trigger a search in VS Code for the variable name
      $searchUrl = "vscode://search/search?query=$([System.Uri]::EscapeDataString($varName))"
      $hyperlinkedVarName = "$script:e]8;;$searchUrl$script:e\$varName$script:e]8;;$script:e\"

      $restoredActionText = if ($null -eq $originalValue) { "Unset" } else { "Restored" }
      Write-Host "  $script:itemiser $restoredActionText environment variable: " -NoNewline
      Write-Host $hyperlinkedVarName -ForegroundColor Yellow
    }
  }
  $script:originalEnvironmentVariables.Clear() # Prepare for the new state

  # --- Load Phase ---
  if ($currentEnvFiles.Count -gt 0) {
    Write-Debug "MODULE Import-DotEnv (Load Phase): Entering load phase."
    Write-Debug "MODULE Import-DotEnv (Load Phase): currentEnvFiles Type: $($currentEnvFiles.GetType().FullName)"
    Write-Debug "MODULE Import-DotEnv (Load Phase): currentEnvFiles Content: $($currentEnvFiles | Out-String)"
    Write-Debug "MODULE Import-DotEnv (Load Phase): About to loop through $($currentEnvFiles.Count) files."
    Write-Host "`nLoading new environment configuration:" -ForegroundColor Cyan
    foreach ($file in $currentEnvFiles) {
      Write-Debug "MODULE Import-DotEnv (Load Phase): Processing file '$file'"

      # Format-EnvFile now handles populating $script:originalEnvironmentVariables and setting new values.
      Format-EnvFile -EnvFile $file -BasePath $resolvedPath
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

  # DEBUG: Inspect module's own exported commands at the start of this function
  $currentModule = $MyInvocation.MyCommand.Module # Use $MyInvocation to get the current module
  if ($currentModule) {
    Write-Debug "Enable-ImportDotEnvCdIntegration: Module '$($currentModule.Name)' found via `$MyInvocation.MyCommand.Module. Checking ExportedCommands..."
    if ($currentModule.ExportedCommands.ContainsKey('Invoke-ImportDotEnvSetLocationWrapper')) {
      Write-Debug "Enable-ImportDotEnvCdIntegration: 'Invoke-ImportDotEnvSetLocationWrapper' IS in ExportedCommands."
    } else {
      Write-Warning "Enable-ImportDotEnvCdIntegration: CRITICAL - 'Invoke-ImportDotEnvSetLocationWrapper' IS NOT in ExportedCommands. Available: $($currentModule.ExportedCommands.Keys -join ', ')"
    }
  } else {
    Write-Warning "Enable-ImportDotEnvCdIntegration: CRITICAL - Module could not be determined via `$MyInvocation.MyCommand.Module."
  }

  Write-Host "Enabling ImportDotEnv integration for 'Set-Location', 'cd', and 'sl' commands..." -ForegroundColor Yellow
  Write-Host "These commands will now also trigger .env file processing." -ForegroundColor Yellow
  Write-Host "To disable, run 'Disable-ImportDotEnvCdIntegration'." -ForegroundColor Yellow

  # The target for the alias is the fully qualified name of our wrapper function
  $currentModuleNameForEnable = $MyInvocation.MyCommand.Module.Name # Use a distinct variable name
  if (-not $currentModuleNameForEnable) {
    Write-Error "Enable-ImportDotEnvCdIntegration: Could not determine current module name. Aborting."
    return
  }
  $wrapperFunctionFullName = "$currentModuleNameForEnable\Invoke-ImportDotEnvSetLocationWrapper"
  Write-Debug "Enable-ImportDotEnvCdIntegration: Determined wrapper function full name: '$wrapperFunctionFullName'"

  # --- Phase 1: Cleanup existing commands ---
  Write-Debug "Enable-ImportDotEnvCdIntegration: Phase 1 - Cleanup"
  $existingSetLocation = Get-Command Set-Location -ErrorAction SilentlyContinue
  if ($existingSetLocation -and $existingSetLocation.CommandType -eq [System.Management.Automation.CommandTypes]::Alias) {
    Write-Debug "Enable-ImportDotEnvCdIntegration: Removing existing Set-Location alias."
    Remove-Alias -Name Set-Location -Scope Global -Force -ErrorAction SilentlyContinue
  }

  foreach ($cmdName in @('cd', 'sl')) {
    Write-Debug "Enable-ImportDotEnvCdIntegration: Attempting to remove '$cmdName' (alias and function if they exist)."
    # Be very explicit for 'cd'
    if ($cmdName -eq 'cd') { Get-Command $cmdName -All -ErrorAction SilentlyContinue | ForEach-Object { Write-Debug "Enable-ImportDotEnvCdIntegration: Found existing '$cmdName': Type $($_.CommandType), Def: $($_.Definition)" } }
    Remove-Alias -Name $cmdName -Scope Global -Force -ErrorAction SilentlyContinue
    Remove-Item "Function:\Global:$cmdName" -Force -ErrorAction SilentlyContinue
    if ($cmdName -eq 'cd') {
        $stillExists = Get-Command $cmdName -ErrorAction SilentlyContinue
        if ($stillExists) { Write-Debug "Enable-ImportDotEnvCdIntegration: WARNING - '$cmdName' still exists after removal attempt: Type $($stillExists.CommandType)"}
    }
  }

  # --- Phase 2: Define new commands/aliases ---
  Write-Debug "Enable-ImportDotEnvCdIntegration: Phase 2 - Definition"
  Write-Debug "About to Set-Alias Set-Location. Value: '$wrapperFunctionFullName' (Type: $($wrapperFunctionFullName.GetType().Name))"

  # Debug: Check if the target command is resolvable *before* setting the alias
  $resolvedTargetCmd = Get-Command $wrapperFunctionFullName -ErrorAction SilentlyContinue
  if (-not $resolvedTargetCmd) {
    Write-Warning "Enable-ImportDotEnvCdIntegration: CRITICAL - Target command '$wrapperFunctionFullName' could not be resolved before setting alias."
  }

  Set-Alias -Name Set-Location -Value $wrapperFunctionFullName -Scope Global -Force -Option ReadOnly, AllScope

  # For 'cd' and 'sl', make them aliases to the wrapper, similar to Set-Location.
  # This simplifies cleanup compared to defining them as functions.
  foreach ($aliasCmdName in @('cd', 'sl')) {
    Write-Debug "Enable-ImportDotEnvCdIntegration: Defining '$aliasCmdName' as alias to '$wrapperFunctionFullName'."
    Write-Debug "Enable-ImportDotEnvCdIntegration: Pre-Set-Alias cleanup for '$aliasCmdName'. Current state: $(Get-Command $aliasCmdName -ErrorAction SilentlyContinue | Select-Object Name, CommandType, Definition | Format-List | Out-String)"
    # Remove any existing alias or function for this command name
    Remove-Alias -Name $aliasCmdName -Scope Global -Force -ErrorAction SilentlyContinue
    Remove-Item "Function:\Global:$aliasCmdName" -Force -ErrorAction SilentlyContinue

    Set-Alias -Name $aliasCmdName -Value $wrapperFunctionFullName -Scope Global -Force -Option ReadOnly,AllScope
    Write-Debug "Enable-ImportDotEnvCdIntegration: Successfully Set-Alias '$aliasCmdName' to '$wrapperFunctionFullName'. Current '$aliasCmdName' type: $((Get-Command $aliasCmdName -ErrorAction SilentlyContinue).CommandType)"
    if ($aliasCmdName -eq 'cd') {
        $cdCmdDetailsAfterEnable = Get-Command cd -ErrorAction SilentlyContinue
        Write-Host "INFO: 'cd' (Alias) details - Name: $($cdCmdDetailsAfterEnable.Name), Type: $($cdCmdDetailsAfterEnable.CommandType), Definition: $($cdCmdDetailsAfterEnable.Definition), Options: $($cdCmdDetailsAfterEnable.Options)" -ForegroundColor DarkGray
    }
  }

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

  # For cd (was a function calling our wrapper)
  $cdCmdInfoForDisable = Get-Command "cd" -ErrorAction SilentlyContinue
  Write-Debug "Disable-ImportDotEnvCdIntegration: Checking 'cd' (Phase 1). Found: Name '$($cdCmdInfoForDisable.Name)', Type '$($cdCmdInfoForDisable.CommandType)', Module: '$($cdCmdInfoForDisable.Module.Name)', Options: '$($cdCmdInfoForDisable.Options)'."
  if ($cdCmdInfoForDisable -and $cdCmdInfoForDisable.CommandType -eq [System.Management.Automation.CommandTypes]::Function) {
    Write-Debug "Disable-ImportDotEnvCdIntegration: 'cd' is a function. ScriptBlock (first 100 chars): $($cdCmdInfoForDisable.ScriptBlock.ToString().Substring(0, [System.Math]::Min(100, $cdCmdInfoForDisable.ScriptBlock.ToString().Length)))"
    Write-Debug "Disable-ImportDotEnvCdIntegration: Comparing with regex for wrapper: $([regex]::Escape($wrapperFunctionFullName))"
  }

  if ($cdCmdInfoForDisable -and $cdCmdInfoForDisable.CommandType -eq [System.Management.Automation.CommandTypes]::Function -and $cdCmdInfoForDisable.ScriptBlock.ToString() -match ([regex]::Escape($wrapperFunctionFullName))) {
    Write-Debug "Disable-ImportDotEnvCdIntegration: 'cd' function matches wrapper. Attempting Remove-Item Function:\Global:cd."
    Remove-Item "Function:\Global:cd" -Force -ErrorAction SilentlyContinue
    Write-Debug " - 'cd' (ImportDotEnv function proxy) removed."
    $proxiesRemoved = $true
  } else {
    if ($cdCmdInfoForDisable -and $cdCmdInfoForDisable.CommandType -eq [System.Management.Automation.CommandTypes]::Function) {
        Write-Warning "Disable-ImportDotEnvCdIntegration: 'cd' is a function, but its scriptblock did not match the expected wrapper in Phase 1. It will be targeted for removal in Phase 2 if it's still a function then."
    }
  }

  # For sl (was an alias to our wrapper)
  $slCmdInfoForDisableSl = Get-Command "sl" -ErrorAction SilentlyContinue # Renamed to avoid conflict
  if ($slCmdInfoForDisableSl -and $slCmdInfoForDisableSl.CommandType -eq [System.Management.Automation.CommandTypes]::Alias -and $slCmdInfoForDisableSl.Definition -eq $wrapperFunctionFullName) {
    Remove-Alias -Name "sl" -Scope Global -Force -ErrorAction SilentlyContinue
    Write-Debug " - 'sl' (ImportDotEnv alias proxy) removed."
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
  } elseif ($finalSetLocation.Source -ne "Microsoft.PowerShell.Management" -or $finalSetLocation.CommandType -ne [System.Management.Automation.CommandTypes]::Cmdlet) {
    Write-Warning " - 'Set-Location' may not be correctly restored. Expected Cmdlet from Microsoft.PowerShell.Management. Found Type: $($finalSetLocation.CommandType), Source: $($finalSetLocation.Source)."
  } else {
    Write-Debug " - 'Set-Location' confirmed as original cmdlet."
  }

  # Ensure cd and sl are aliases pointing to Set-Location
  foreach ($aliasName in @("cd", "sl")) {
    Write-Debug "Disable-ImportDotEnvCdIntegration: Restoring '$aliasName' as alias to Set-Location (Phase 2)."
    $cmdBeforeRestore = Get-Command $aliasName -ErrorAction SilentlyContinue
    Write-Debug "Disable-ImportDotEnvCdIntegration: State of '$aliasName' before Phase 2 restoration: Type '$($cmdBeforeRestore.CommandType)', Def/Module '$($cmdBeforeRestore.Definition)/$($cmdBeforeRestore.Module.Name)', Options '$($cmdBeforeRestore.Options)'"

    # Remove any function that might be named $aliasName
    if ($cmdBeforeRestore.CommandType -eq [System.Management.Automation.CommandTypes]::Function -and $cmdBeforeRestore.Options -match 'ReadOnly') {
        Write-Debug "Disable-ImportDotEnvCdIntegration: Clearing ReadOnly option from function '$aliasName' before removal."
        Set-Item "Function:\Global:$aliasName" -Options None -Force -ErrorAction SilentlyContinue
    }
    Remove-Item "Function:\Global:$aliasName" -Force -ErrorAction SilentlyContinue
    # Explicit check if the function was actually removed
    $functionStillExists = Get-Command $aliasName -CommandType Function -ErrorAction SilentlyContinue
    if ($functionStillExists) {
        Write-Warning "Disable-ImportDotEnvCdIntegration: Function '$($functionStillExists.Name)' (Type: $($functionStillExists.CommandType), Module: $($functionStillExists.Module.Name), Options: $($functionStillExists.Options)) STILL EXISTS after Remove-Item in Phase 2 for alias '$aliasName'."
    } else {
        Write-Debug "Disable-ImportDotEnvCdIntegration: Function for '$aliasName' confirmed REMOVED after Remove-Item in Phase 2."
    }
    # Set the alias
    Set-Alias -Name $aliasName -Value "Set-Location" -Scope Global -Option AllScope -Force -ErrorAction SilentlyContinue
    $finalAlias = Get-Command $aliasName -ErrorAction SilentlyContinue # Re-fetch after attempting to set alias
    if ($null -eq $finalAlias) {
        Write-Warning " - CRITICAL: '$aliasName' command is missing after attempting to restore default alias."
    } elseif ($finalAlias.CommandType -ne [System.Management.Automation.CommandTypes]::Alias -or $finalAlias.Definition -ne "Set-Location") {
        Write-Warning " - '$aliasName' may not be correctly restored as an alias to Set-Location. Found Type: $($finalAlias.CommandType), Definition: $($finalAlias.Definition)."
    } else {
        Write-Debug " - '$aliasName' confirmed as alias to Set-Location."
    }
  }

  # --- Unload any currently active .env variables ---
  $variablesUnloaded = $false
  if ($script:originalEnvironmentVariables.Count -gt 0) {
    Write-Host "`nUnloading active .env variables as integration is being disabled:" -ForegroundColor Yellow
    $varsToRestore = $script:originalEnvironmentVariables.Keys | ForEach-Object { $_ } # Clone keys
    foreach ($varName in $varsToRestore) {
      $originalValue = $script:originalEnvironmentVariables[$varName]
      if ($null -eq $originalValue) {
        Write-Debug "MODULE Disable-ImportDotEnvCdIntegration (Unload): Restoring '$varName' to non-existent."
        [Environment]::SetEnvironmentVariable($varName, $null)
        if (Test-Path "Env:\$varName") { Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue }
      } else {
        Write-Debug "MODULE Disable-ImportDotEnvCdIntegration (Unload): Restoring '$varName' to '$originalValue'."
        [Environment]::SetEnvironmentVariable($varName, $originalValue)
      }
      $searchUrl = "vscode://search/search?query=$([System.Uri]::EscapeDataString($varName))"
      $hyperlinkedVarName = "$script:e]8;;$searchUrl$script:e\$varName$script:e]8;;$script:e\"
      $restoredActionText = if ($null -eq $originalValue) { "Unset" } else { "Restored" }
      Write-Host "  $script:itemiser $restoredActionText environment variable: " -NoNewline
      Write-Host $hyperlinkedVarName -ForegroundColor Yellow
    }
    $script:originalEnvironmentVariables.Clear()
    $script:previousEnvFiles = @()
    $script:previousWorkingDirectory = "RESET_BY_DISABLE_INTEGRATION_HOOK" # Distinct marker
    Write-Debug "MODULE Disable-ImportDotEnvCdIntegration: Cleared originalEnvironmentVariables and reset previousEnvFiles/previousWorkingDirectory."
    $variablesUnloaded = $true
  }

  # Final message
  if ($proxiesRemoved) {
    Write-Host "ImportDotEnv 'Set-Location' integration disabled, default command behavior restored." -ForegroundColor Magenta
  } else {
    Write-Host "ImportDotEnv 'Set-Location' integration was not active or already disabled." -ForegroundColor Magenta
  }
  if ($variablesUnloaded) {
      Write-Host "Any active .env variables have been unloaded." -ForegroundColor Magenta
  }
}

Export-ModuleMember -Function Import-DotEnv,
    Enable-ImportDotEnvCdIntegration,
    Disable-ImportDotEnvCdIntegration,
    Invoke-ImportDotEnvSetLocationWrapper
