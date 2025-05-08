# DotEnv.psm1

# Requires -Version 5.1

using namespace System.IO
using namespace System.Management.Automation

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

  [Array]::Reverse($envFiles)
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
    [string]$BasePath,

    [ValidateSet('Load', 'Unload')]
    [string]$Action = 'Load',

    [ConsoleColor]$ForegroundColor = 'Cyan'
  )

  if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
    return
  }

  $formattedPath = Format-EnvFilePath -Path $EnvFile -BasePath $BasePath
  Write-Host "$Action .env file ${formattedPath}:" -ForegroundColor $ForegroundColor

  $lineNumber = 0
  switch -Regex -File $EnvFile {
    '^\s*#.*' { continue } # Skip comments
    '^\s*$' { continue }   # Skip empty lines

    '^([^=]+)=(.*)$' {
      $lineNumber++
      $varName = $Matches[1].Trim()
      $varValue = $Matches[2].Trim()

      $actionText = if ($Action -eq 'Load') {
        [Environment]::SetEnvironmentVariable($varName, $varValue)
        "Setting"
      }
      else {
        [Environment]::SetEnvironmentVariable($varName, $null)
        "Unsetting"
      }

      $color = if ($Action -eq 'Load') { 'Green' } else { 'Red' }
      $fileUrl = "vscode://file/${EnvFile}:${lineNumber}"
      $hyperlink = "$script:e]8;;$fileUrl$script:e\$varName$script:e]8;;$script:e\"

      Write-Host "  $script:itemiser $actionText environment variable: " -NoNewline
      Write-Host $hyperlink -ForegroundColor $color -NoNewline
      Write-Host " (Line ${lineNumber})"
    }
  }
}

function Import-DotEnv {
  [CmdletBinding()]
  param(
    [string]$Path = "."
  )

  try {
    $resolvedPath = Convert-Path -Path $Path -ErrorAction Stop
  }
  catch {
    $resolvedPath = $PWD.Path
  }

  $currentEnvFiles = Get-EnvFilesUpstream -Directory $resolvedPath

  # If Get-EnvFilesUpstream terminated unexpectedly (e.g., due to an internal error),
  # $currentEnvFiles might be $null. Compare-Object requires a collection for -DifferenceObject.
  if ($null -eq $currentEnvFiles) {
    $currentEnvFiles = @() # Default to an empty array
  }
  $comparison = Compare-Object -ReferenceObject $script:previousEnvFiles -DifferenceObject $currentEnvFiles

  if (-not $comparison) {
    return
  }

  # Unload previous environment files
  if ($script:previousEnvFiles.Count -gt 0) {
    Write-Host "`nUnloading previous environment configuration:" -ForegroundColor Yellow
    foreach ($file in $script:previousEnvFiles) {
      Format-EnvFile -EnvFile $file -BasePath $script:previousWorkingDirectory -Action Unload -ForegroundColor Yellow
    }
  }

  # Load new environment files
  if ($currentEnvFiles.Count -gt 0) {
    Write-Host "`nLoading new environment configuration:" -ForegroundColor Cyan
    foreach ($file in $currentEnvFiles) {
      Format-EnvFile -EnvFile $file -BasePath $resolvedPath -Action Load -ForegroundColor Cyan
    }
  }

  $script:previousEnvFiles = $currentEnvFiles
  $script:previousWorkingDirectory = $resolvedPath
}

function Set-Location {
  [CmdletBinding()]
  param(
    [Parameter(Position = 0)]
    [string]$Path
  )

  Microsoft.PowerShell.Management\Set-Location -Path $Path
  Import-DotEnv -Path $Path
}

Export-ModuleMember -Function Get-EnvFilesUpstream, Import-DotEnv, Set-Location