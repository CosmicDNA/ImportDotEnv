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
  if ($script:originalEnvironmentVariables.Count -gt 0) { # This check might be too simple if we always want to clear
    Write-Host "`nRestoring environment from previous configuration:" -ForegroundColor Yellow
    # Clone keys because we might be modifying the collection if we were to remove, though here we just clear after.
    $varsToRestore = $script:originalEnvironmentVariables.Keys | ForEach-Object { $_ }
    foreach ($varName in $varsToRestore) {
      $originalValue = $script:originalEnvironmentVariables[$varName]
      [Environment]::SetEnvironmentVariable($varName, $originalValue) # This correctly unsets if $originalValue is $null

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
# Set-Location is already exported by the .psd1 if it's defined in the .psm1
# Ensure it's defined if not already. If it was previously here and removed, it should be added back.
# Assuming Set-Location is defined as it was:

function Set-Location {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path
    )
    Write-Debug "MODULE Set-Location: OVERRIDE CALLED with Path '$Path'. Current PWD before MSFT Set-Location: $($PWD.Path)"

    Microsoft.PowerShell.Management\Set-Location -Path $Path # This changes $PWD
    Write-Debug "MODULE Set-Location: After MSFT Set-Location. New PWD: $($PWD.Path). Calling Import-DotEnv for original target Path '$Path'."
    $filesFoundBySetLocation = Get-EnvFilesUpstream -Directory $Path
    Write-Debug "MODULE Set-Location: Get-EnvFilesUpstream for '$Path' found: $($filesFoundBySetLocation -join ', ')"
    Import-DotEnv -Path $Path # Call with the original target path
}

Export-ModuleMember -Function Get-EnvFilesUpstream, Import-DotEnv, Set-Location