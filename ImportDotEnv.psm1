using namespace System.IO
using namespace System

function Get-RelativePath {
  param (
    [string]$Path,
    [string]$BasePath
  )

  $separator = [Path]::DirectorySeparatorChar

  $absolutePath = [Path]::GetFullPath($Path)
  $absoluteBasePath = [Path]::GetFullPath($BasePath)

  $pathSegments = $absolutePath -split [regex]::Escape($separator)
  $basePathSegments = $absoluteBasePath -split [regex]::Escape($separator)

  $commonLength = (
    0..([math]::Min($pathSegments.Length, $basePathSegments.Length) - 1)
  ).Where({ $pathSegments[$_] -eq $basePathSegments[$_] }).Count

  if ($commonLength -eq 0) {
    return $absolutePath
  }
  else {
    $relativePath = @(".") + ($pathSegments[$commonLength..($pathSegments.Length - 1)])
  }

  return $relativePath -join $separator
}

$script:previousEnvFiles = @()
$script:previousWorkingDirectory = (Get-Location).Path

function Get-EnvFilesUpstream {
  param (
    [string]$Directory = "."
  )

  try {
    $resolvedPath = Resolve-Path -Path $Directory -ErrorAction Stop
  }
  catch {
    $resolvedPath = (Get-Location).Path
  }

  $envFiles = @()
  $currentDir = $resolvedPath

  while ($currentDir) {
    $envPath = Join-Path $currentDir ".env"
    if (Test-Path $envPath -PathType Leaf) {
      $envFiles += $envPath
    }

    $parentDir = Split-Path $currentDir -Parent
    if ($parentDir -eq $currentDir) { break }
    $currentDir = $parentDir
  }

  # Fix 1: Reverse order to prioritize child -> parent -> root
  [array]::Reverse($envFiles)
  return $envFiles
}

$script:e = [char]27
$script:itemiser = [char]0x21B3

function Format-EnvFilePath {
  param (
    [string]$Path,
    [string]$BasePath
  )

  $relativePath = Get-RelativePath -Path $Path -BasePath $BasePath
  $corePath = Split-Path $relativePath -Parent
  $corePath = $corePath -replace '^\.\\', ''
  return $relativePath -replace ([regex]::Escape($corePath), "$script:e[1m$corePath$script:e[22m")
}

function Format-EnvFile {
  param (
    [string]$EnvFile,
    [string]$BasePath,
    [string]$Action,
    [string]$ForegroundColor
  )

  if (Test-Path $EnvFile -PathType Leaf) {
    $formattedPath = Format-EnvFilePath -Path $EnvFile -BasePath $BasePath
    Write-Host "$Action .env file ${formattedPath}:" -ForegroundColor $ForegroundColor

    $content = Get-Content $EnvFile
    $lineNumber = 0

    foreach ($line in $content) {
      $lineNumber++
      $line = $line -replace '\s*#.*', ''
      if ($line -match '^(.*)=(.*)$') {
        $variableName = $matches[1].Trim()

        if ($Action -eq "Load") {
          $valueToSet = $matches[2].Trim()
          $color = "Green"
          $actionText = "Setting"
        }
        else {
          $valueToSet = $null
          $color = "Red"
          $actionText = "Unsetting"
        }

        [Environment]::SetEnvironmentVariable($variableName, $valueToSet)
        $fileUrl = "vscode://file/${EnvFile}:$lineNumber"
        $hyperlink = "$script:e]8;;$fileUrl$script:e\$variableName$script:e]8;;$script:e\"

        Write-Host "$script:itemiser $actionText environment variable: " -NoNewline
        Write-Host $hyperlink -ForegroundColor $color
      }
    }
  }
}

function Format-EnvFiles {
  param (
    [array]$EnvFiles,
    [string]$BasePath,
    [string]$Action,
    [string]$Message,
    [string]$ForegroundColor
  )

  if ($EnvFiles) {
    $listOutput = "The following .env files were ${Message}:`n"
    foreach ($envFile in $EnvFiles) {
      $formattedPath = Format-EnvFilePath -Path $envFile -BasePath $BasePath
      $listOutput += "$script:itemiser $formattedPath`n"
    }
    Write-Host $listOutput -ForegroundColor DarkGray

    foreach ($envFile in $EnvFiles) {
      Format-EnvFile -EnvFile $envFile -BasePath $BasePath `
        -Action $Action -ForegroundColor $ForegroundColor
    }
  }
}

function Import-DotEnv {
  param (
    [string]$Path = "."
  )

  try {
    $resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop
  }
  catch {
    $resolvedPath = (Get-Location).Path
  }

  $currentEnvFiles = Get-EnvFilesUpstream -Directory $resolvedPath

  # Handle null/empty scenarios
  $currentNormalized = @($currentEnvFiles | ForEach-Object { $_.ToLowerInvariant() })
  $previousNormalized = @($script:previousEnvFiles | ForEach-Object { $_.ToLowerInvariant() })

  # Create empty arrays if null
  if ($null -eq $currentNormalized) { $currentNormalized = @() }
  if ($null -eq $previousNormalized) { $previousNormalized = @() }

  $comparison = Compare-Object -ReferenceObject $previousNormalized -DifferenceObject $currentNormalized

  if ($comparison) {
    # Unload all previous
    if ($script:previousEnvFiles) {
      Format-EnvFiles -EnvFiles $script:previousEnvFiles -BasePath $script:previousWorkingDirectory `
        -Action "Unload" -Message "removed" -ForegroundColor Yellow
    }

    # Load new set
    if ($currentEnvFiles) {
      Format-EnvFiles -EnvFiles $currentEnvFiles -BasePath $resolvedPath `
        -Action "Load" -Message "added" -ForegroundColor Cyan
    }

    $script:previousEnvFiles = $currentEnvFiles
    $script:previousWorkingDirectory = $resolvedPath
  }
}

function Set-Location {
  param (
    [string]$Path
  )

  Microsoft.PowerShell.Management\Set-Location $Path
  Import-DotEnv
}

Export-ModuleMember -Function Get-EnvFilesUpstream, Import-DotEnv, Set-Location