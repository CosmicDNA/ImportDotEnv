# Track previously loaded .env files
$script:previousEnvFiles = @()

# Track the previous working directory
$script:previousWorkingDirectory = (Get-Location).Path

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
  $relativePath = Resolve-Path $Path -Relative -RelativeBasePath $BasePath
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

    # Add the action message to the output with color
    $colorCode = if ($ForegroundColor -eq "Cyan") { "36" } elseif ($ForegroundColor -eq "Yellow") { "33" } else { "37" } # Default to white
    $output += "`e[${colorCode}m$Action .env file ${formattedPath}:`e[0m`n"

    # Read the file content once
    $content = Get-Content $EnvFile

    # Process the .env file
    foreach ($line in $content) {
      # Remove comments and trailing whitespace
      $line = $line -replace '\s*#.*', ''
      # Match lines that have key=value
      if ($line -match '^(.*)=(.*)$') {
        $variableName = $matches[1].Trim()

        if ($Action -eq "Load") {
          $variableValue = $matches[2].Trim()
          [System.Environment]::SetEnvironmentVariable($variableName, $variableValue)
          $color = "32" # Green
          $actionText = "Setting"
        } else {
          [System.Environment]::SetEnvironmentVariable($variableName, $null)
          $color = "31" # Red
          $actionText = "Unsetting"
        }

        # Add the environment variable action to the output with color and hyperlink
        $hyperlinkStart = "`e]8;;$EnvFile`e\"
        $hyperlinkEnd = "`e]8;;`e\"
        $output += "↳ $actionText environment variable: `e[${color}m$hyperlinkStart$variableName$hyperlinkEnd`e[0m`n"
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

    $processingOutput = ""
    # Collect formatted paths
    foreach ($envFile in $EnvFiles) {
      $formattedPath = Format-EnvFilePath -Path $envFile -BasePath $BasePath
      $listOutput += "↳ $formattedPath`n"
      $envFileOutput = Format-EnvFile -EnvFile $envFile -BasePath $BasePath -Action $Action -ForegroundColor $ForegroundColor
      $processingOutput += "$envFileOutput`n"
    }

    # Display the full output at once with colors
    Write-Host $listOutput -ForegroundColor DarkGray

    # Display the full output at once with colors
    Write-Host $processingOutput
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