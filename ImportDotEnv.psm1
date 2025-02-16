function Get-RelativePath {
  param (
      [string]$Path,
      [string]$BasePath
  )

  $absolutePath = [System.IO.Path]::GetFullPath($Path)
  $absoluteBasePath = [System.IO.Path]::GetFullPath($BasePath)

  $uri = New-Object System.Uri($absolutePath)
  $baseUri = New-Object System.Uri($absoluteBasePath)

  $relativeUri = $baseUri.MakeRelativeUri($uri)
  $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString())

  return $relativePath
}

# Track previously loaded .env files
$script:previousEnvFiles = @()

# Track the previous working directory
$script:previousWorkingDirectory = (Get-Location).Path

if ($PSVersionTable.PSVersion.Major -ge 7) {
  $script:itemiser = "↳"
} else {
  $script:itemiser = "-"
}

function Get-EnvFilesUpstream {
  param (
    [string]$Directory = "."
  )

  # Resolve the full path of the directory
  try {
    $resolvedPath = Resolve-Path -Path $Directory -ErrorAction Stop
  } catch {
    $resolvedPath = (Get-Location).Path
  }

  # Initialize an array to store .env file paths
  $envFiles = @()

  # Start from the current directory and move up to the root
  $currentDir = $resolvedPath
  while ($currentDir) {
    $envPath = Join-Path $currentDir ".env"
    if (Test-Path $envPath -PathType Leaf) {
      # Add the .env file to the array
      $envFiles += $envPath
    }

    # Move to the parent directory
    $parentDir = Split-Path $currentDir -Parent
    if ($parentDir -eq $currentDir) {
      # Stop if we've reached the root
      break
    }
    $currentDir = $parentDir
  }

  return $envFiles
}

function Format-EnvFilePath {
  param (
    [string]$Path,
    [string]$BasePath
  )

  # Resolve the relative path

  # The RelativeBasePath parameter is available in PowerShell 7.4 and later only
  # $relativePath = Resolve-Path $Path -Relative -RelativeBasePath $BasePath
  $relativePath = Get-RelativePath -Path $Path -BasePath $BasePath

  # Extract the core path (directory containing the .env file)
  $corePath = Split-Path $relativePath -Parent
  # Remove the initial .\ from the relative path
  $corePath = $corePath -replace '^\.\\', ''
  # Format the core path in bold
  $formattedPath = $relativePath -replace ([regex]::Escape($corePath), "`e[1m$corePath`e[22m")

  return $formattedPath
}

function Format-EnvFile {
  param (
    [string]$EnvFile,
    [string]$BasePath,
    [string]$Action, # "Load" or "Unload"
    [string]$ForegroundColor # Color for the action message
  )

  # Initialize a string to store the output
  $output = ""

  if (Test-Path $EnvFile -PathType Leaf) {
    # Format the path
    $formattedPath = Format-EnvFilePath -Path $EnvFile -BasePath $BasePath

    Write-Host "$Action .env file ${formattedPath}:" -ForegroundColor $ForegroundColor

    # Read the file content once
    $content = Get-Content $EnvFile

    $lineNumber = 0
    # Process the .env file
    foreach ($line in $content) {
      $lineNumber++
      # Remove comments and trailing whitespace
      $line = $line -replace '\s*#.*', ''
      # Match lines that have key=value
      if ($line -match '^(.*)=(.*)$') {
        $variableName = $matches[1].Trim()

        if ($Action -eq "Load") {
          $variableValue = $matches[2].Trim()
          [System.Environment]::SetEnvironmentVariable($variableName, $variableValue)
          $color = "Green"
          $actionText = "Setting"
        } else {
          [System.Environment]::SetEnvironmentVariable($variableName, $null)
          $color = "Red"
          $actionText = "Unsetting"
        }

        $fileUrl = "vscode://file/${EnvFile}:$lineNumber"
        # Add the environment variable action to the output with color and hyperlink
        $e = [char] 27
        $hyperlinkStart = "$e]8;;$fileUrl$e\"
        $hyperlinkEnd = "$e]8;;$e\"
        # $output += "↳ $actionText environment variable: `e[${color}m$hyperlinkStart$variableName$hyperlinkEnd`e[0m`n"
        $variableString = "$hyperlinkStart$variableName$hyperlinkEnd"

        Write-Host "$script:itemiser $actionText environment variable: " -NoNewline
        Write-Host "$variableString" -ForegroundColor "$color"
      }
    }
  }

  # Return the output as a string
  return $output
}

function Format-EnvFiles {
  param (
    [array]$EnvFiles,
    [string]$BasePath,
    [string]$Action, # "Load" or "Unload"
    [string]$Message, # Message to display (e.g., "added" or "removed")
    [string]$ForegroundColor # Color for the action message
  )

  if ($EnvFiles) {
    # Initialize a string to store the full output
    $listOutput = "The following .env files were ${Message}:`n"

    # Collect formatted paths
    foreach ($envFile in $EnvFiles) {
      $formattedPath = Format-EnvFilePath -Path $envFile -BasePath $BasePath
      $listOutput += "$script:itemiser $formattedPath`n"
    }

    # Display the full output at once with colors
    Write-Host $listOutput -ForegroundColor DarkGray

    foreach ($envFile in $EnvFiles) {
      Format-EnvFile -EnvFile $envFile -BasePath $BasePath -Action $Action -ForegroundColor $ForegroundColor
    }
  }
}

function Import-DotEnv {
  param (
    [string]$Path = "."
  )

  # Resolve the full path of the directory
  try {
    $resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop
  } catch {
    $resolvedPath = (Get-Location).Path
  }

  # Get the current list of .env files
  $currentEnvFiles = Get-EnvFilesUpstream -Directory $resolvedPath

  $previousEnvFilesSet = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($file in $script:previousEnvFiles) {
    [void]$previousEnvFilesSet.Add($file)
  }

  $currentEnvFilesSet = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($file in $currentEnvFiles) {
    [void]$currentEnvFilesSet.Add($file)
  }


  # Compare with the previous list to detect removed .env files
  $removedEnvFiles = $script:previousEnvFiles | Where-Object { -not $currentEnvFilesSet.Contains($_) }

  # Compare with the previous list to detect added .env files
  $addedEnvFiles = $currentEnvFiles | Where-Object { -not $previousEnvFilesSet.Contains($_) }

  # Process removed .env files (relative to current path)
  Format-EnvFiles -EnvFiles $removedEnvFiles -BasePath $resolvedPath -Action "Unload" -Message "removed" -ForegroundColor Yellow

  # Process added .env files (relative to previous path)
  Format-EnvFiles -EnvFiles $addedEnvFiles -BasePath $script:previousWorkingDirectory -Action "Load" -Message "added" -ForegroundColor Cyan

  # Update the previous list with the current list
  $script:previousEnvFiles = $currentEnvFiles

  # Update the previous working directory
  $script:previousWorkingDirectory = $resolvedPath
}

function Set-Location {
  param (
    [string]$Path
  )

  Microsoft.PowerShell.Management\Set-Location $Path
  Import-DotEnv
}

Export-ModuleMember -Function Get-EnvFilesUpstream, Import-DotEnv, Set-Location