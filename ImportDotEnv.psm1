# DotEnv.psm1

# Requires -Version 5.1

using namespace System.IO
using namespace System.Management.Automation

$script:originalEnvironmentVariables = @{} # Stores { VarName = OriginalValueOrNull }
$script:previousEnvFiles = @()
$script:previousWorkingDirectory = $PWD.Path
$script:e = [char]27
$script:itemiser = [char]0x21B3

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
        $script:originalEnvironmentVariables[$varName] = [Environment]::GetEnvironmentVariable($varName)
        Write-Debug "MODULE Format-EnvFile: Storing original value for '$varName': '$($script:originalEnvironmentVariables[$varName])'"
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
      Write-Debug "MODULE Import-DotEnv (Unload): Restoring '$varName'. Original value was type: $($originalValue.GetType().Name), IsNull: $($null -eq $originalValue), Value: '$originalValue'"
      if ($null -eq $originalValue) {
        Write-Debug "MODULE Import-DotEnv (Unload): Calling [Environment]::SetEnvironmentVariable('$varName', `$null) to remove it."
        [Environment]::SetEnvironmentVariable($varName, $null)
        # Also try to remove it via PowerShell's provider to be sure
        if (Test-Path "Env:\$varName") {
            Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue
        }
      } else {
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

    # Call the original Set-Location cmdlet
    # Ensure we call the cmdlet from the Microsoft.PowerShell.Management module
    # to avoid recursion if Set-Location is aliased to this wrapper.
    Microsoft.PowerShell.Management\Set-Location @PSBoundParameters

    # Call our custom logic
    Import-DotEnv -Path $PWD.Path
}

function Enable-ImportDotEnvCdIntegration {
  [CmdletBinding()]
  param()

  Write-Host "Enabling ImportDotEnv integration for 'Set-Location', 'cd', and 'sl' commands." -ForegroundColor Yellow
  Write-Host "These commands will now also trigger .env file processing." -ForegroundColor Yellow
  Write-Host "To disable, run 'Disable-ImportDotEnvCdIntegration'." -ForegroundColor Yellow

  # The target for the alias is the fully qualified name of our wrapper function
  $wrapperFunctionFullName = "ImportDotEnv\Invoke-ImportDotEnvSetLocationWrapper"

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

  # Optional: Brief pause or no-op to allow command system to settle (highly speculative)
  # Start-Sleep -Milliseconds 10

  # --- Phase 2: Define new commands/aliases ---
  Write-Debug "Enable-ImportDotEnvCdIntegration: Phase 2 - Definition"
  Write-Host "DEBUG: About to Set-Alias Set-Location. Value: '$wrapperFunctionFullName' (Type: $($wrapperFunctionFullName.GetType().Name))"
  Set-Alias -Name Set-Location -Value $wrapperFunctionFullName -Scope Global -Force -Option ReadOnly, AllScope

  # For cd and sl, define them as global functions that call the wrapper.
  # This is often more robust for overriding built-in aliases.
  # The scriptblock uses the fully qualified name to ensure it calls the correct function.
  # Ensure the function is ReadOnly and AllScope to mimic alias behavior.
  Write-Debug "Enable-ImportDotEnvCdIntegration: Defining 'cd' as function."
  $cdFunctionScriptBlock = [scriptblock]::Create("$wrapperFunctionFullName @PSBoundParameters")

  # Extremely explicit cleanup for 'cd' right before defining it as a function
  Write-Debug "Enable-ImportDotEnvCdIntegration: Pre-Set-Item cleanup for 'cd'. Current state: $(Get-Command cd -ErrorAction SilentlyContinue | Select-Object Name, CommandType, Definition | Format-List | Out-String)"
  Remove-Alias -Name cd -Scope Global -Force -ErrorAction SilentlyContinue
  Remove-Item Function:\Global:cd -Force -ErrorAction SilentlyContinue
  Write-Debug "Enable-ImportDotEnvCdIntegration: Post-explicit-cleanup for 'cd'. Current state: $(Get-Command cd -ErrorAction SilentlyContinue | Select-Object Name, CommandType, Definition | Format-List | Out-String)"

  # Special handling for 'cd' due to its stickiness
  $currentCd = Get-Command cd -ErrorAction SilentlyContinue
  if ($currentCd -and $currentCd.CommandType -eq [System.Management.Automation.CommandTypes]::Alias) {
    Write-Debug "Enable-ImportDotEnvCdIntegration: 'cd' is an alias. Removing it before defining function."
    Remove-Alias -Name cd -Scope Global -Force -ErrorAction SilentlyContinue
  }
  try {
    Set-Item -Path "Function:\Global:cd" -Value $cdFunctionScriptBlock -Force -Options ReadOnly, AllScope -ErrorAction Stop | Out-Null
    Write-Debug "Enable-ImportDotEnvCdIntegration: Successfully Set-Item Function:\Global:cd. Current 'cd' type: $((Get-Command cd -ErrorAction SilentlyContinue).CommandType)"
  } catch {
    Write-Error "Enable-ImportDotEnvCdIntegration: FAILED to Set-Item Function:\Global:cd. Error: $($_.Exception.Message)"
    $cdAfterFail = Get-Command cd -ErrorAction SilentlyContinue
    Write-Debug "Enable-ImportDotEnvCdIntegration: Current 'cd' type after failed Set-Item: $($cdAfterFail.CommandType), Definition: $($cdAfterFail.Definition)"
  }

  Write-Debug "Enable-ImportDotEnvCdIntegration: Defining 'sl' as function."
  $slFunctionScriptBlock = [scriptblock]::Create("$wrapperFunctionFullName @PSBoundParameters")
  Set-Item -Path "Function:\Global:sl" -Value $slFunctionScriptBlock -Force -Options ReadOnly, AllScope | Out-Null # Use Set-Item


  Write-Host "ImportDotEnv 'Set-Location', 'cd', 'sl' integration enabled." -ForegroundColor Green
}

function Disable-ImportDotEnvCdIntegration {
  [CmdletBinding()]
  param()

  Write-Host "Disabling ImportDotEnv integration for 'Set-Location', 'cd', and 'sl'." -ForegroundColor Yellow

  $wrapperFunctionFullName = "ImportDotEnv\Invoke-ImportDotEnvSetLocationWrapper"
  $restoredDefaultAliases = $false

  foreach ($commandName in @("Set-Location", "cd", "sl")) {
    $cmdInfo = Get-Command $commandName -ErrorAction SilentlyContinue # Rely on default resolution, -Scope Global might be problematic here
    if ($null -eq $cmdInfo) {
        Write-Host " - '$($commandName)' command not found in Global scope."
        continue
    }

    if ($cmdInfo.CommandType -eq [System.Management.Automation.CommandTypes]::Alias -and $cmdInfo.Definition -eq $wrapperFunctionFullName) {
      Remove-Alias -Name $commandName -Scope Global -Force # This should only apply to Set-Location now
      Write-Host " - '$($commandName)' alias (ImportDotEnv proxy to '$wrapperFunctionFullName') removed."
      $restoredDefaultAliases = $true
      # For Set-Location itself, removing the alias is enough to restore the cmdlet.
    } elseif ($cmdInfo.CommandType -eq [System.Management.Automation.CommandTypes]::Function -and ($commandName -in ('cd', 'sl'))) {
        # Check if the function body calls our wrapper
        if ($cmdInfo.ScriptBlock.ToString() -match ([regex]::Escape($wrapperFunctionFullName))) {
            Remove-Item "Function:\Global:$commandName" -Force -ErrorAction SilentlyContinue
            Write-Host " - '$($commandName)' function (ImportDotEnv proxy) removed."
            # Restore default alias for cd and sl to point to Set-Location (cmdlet)
            Set-Alias -Name $commandName -Value Set-Location -Scope Global -Option AllScope -Force
            Write-Host " - '$($commandName)' alias restored to default (Set-Location)."
            $restoredDefaultAliases = $true
        } else {
            Write-Host " - '$($commandName)' function definition does not match expected proxy."
        }
    } else {
      Write-Host " - '$($commandName)' command was not managed by ImportDotEnv or already restored."
    }
  }

  if ($restoredDefaultAliases) {
    Write-Host "ImportDotEnv 'Set-Location' integration disabled. Default command behavior restored."
  } else {
    Write-Host "ImportDotEnv 'Set-Location' integration was not active or already disabled."
  }
}

Export-ModuleMember -Function Get-EnvFilesUpstream,
Import-DotEnv,
Enable-ImportDotEnvCdIntegration,
Disable-ImportDotEnvCdIntegration,
Invoke-ImportDotEnvSetLocationWrapper
