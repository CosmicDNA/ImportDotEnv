# ImportDotEnv

![CI/CD](https://github.com/CosmicDNA/ImportDotEnv/actions/workflows/pester.yml/badge.svg)
[![Coverage](https://img.shields.io/endpoint?url=https://cosmicdna.github.io/ImportDotEnv/coverage.json)](https://cosmicdna.github.io/ImportDotEnv/)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/ImportDotEnv?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/ImportDotEnv)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A PowerShell module for managing `.env` files, allowing you to load and unload environment variables dynamically. This module is designed to simplify working with environment variables in PowerShell scripts and automation workflows.

---

## Features

- **VS Code hyperlink to env var definition**: Automatically sets a hyperlink on the terminal to each environment variable defintion.
- **Load `.env` Files**: Automatically load environment variables from `.env` files in the current or parent directories.
- **Unload `.env` Files**: Unload previously loaded environment variables when switching directories.
- **Track Changes**: Track and manage changes to `.env` files as you navigate through directories.
- **Colorized Output**: Provides colorized and formatted output for better visibility of loaded/unloaded variables.
- **Cross-Platform**: Works on Windows, macOS, and Linux.

## Preview

<p align="center">
  <img src="https://github.com/user-attachments/assets/6dbc49e9-3561-4e3a-87b9-9d4df208fcac" alt="ImportDotEnv Usage" />
</p>

---

## Installation

### From the PowerShell Gallery

You can install the module directly from the [PowerShell Gallery](https://www.powershellgallery.com/packages/ImportDotEnv):

```powershell
Install-Module -Name ImportDotEnv -Scope CurrentUser -AllowClobber
```

Once installed open your $PROfILE with the command `code $PROFILE` and add:

```powershell
Import-Module ImportDotEnv

# Set the initial environment variables
Import-DotEnv
```

### Manual Installation

1. Clone this repository:
```powershell
  git clone https://github.com/CosmicDNA/ImportDotEnv.git
```

2. Navigate to the module directory:
```powershell
  cd ImportDotEnv
```

3. Import the module:
```powershell
  Import-Module .\ImportDotEnv.psm1
```

## Usage

### Import Environment Variables

To load environment variables from a `.env` file in the current directory or any parent directory, use the `Import-DotEnv` function:

```powershell
Import-DotEnv
```

This will:

1. Search for .env files in the current directory and its parent directories.
2. Load the environment variables from the found .env files.
3. Display a colorized output of the loaded variables.

### Change Directory and Auto-Load .env Files
The module overrides the Set-Location cmdlet to automatically load .env files when you change directories:

```powershell
cd MyProject
```

This will:

1. Change the directory.

2. Load any .env files in the new directory or its parent directories.

3. Unload environment variables from .env files in the previous directory.

# Example .env File
Create a .env file in your project directory with the following content:

```shell
# .env file
DATABASE_URL=postgres://user:password @localhost:5432/mydb
API_KEY=12345
DEBUG=true
```

When you run Import-DotEnv, the environment variables will be loaded into your session.

## Functions
### Import-DotEnv
Loads environment variables from .env files in the current or parent directories.

```powershell
Import-DotEnv [-Path <string>]
```

- -Path: (Optional) Specifies the path to the .env file. Defaults to .env in the current directory.

## Set-Location
Overrides the built-in Set-Location cmdlet to automatically load .env files when changing directories.

```powershell
Set-Location -Path <string>
```

- -Path: The directory path to navigate to.

## Get-EnvFilesUpstream
Searches for .env files in the current directory and its parent directories.

```powershell
Get-EnvFilesUpstream [-Directory <string>]
```

- -Directory: (Optional) The directory to start searching from. Defaults to the current directory.

# Examples
## Load .env Files
```powershell
# Navigate to a directory with a .env file
cd testme
```

And the output:

```terminal
The following .env files were added:
↳ .\testme\.env

Load .env file .\testme\.env:
↳ Setting environment variable: VAR1
```

> [!TIP]
> There is a hyperlink on the environment variables to Visual Studio Code with the reference to the line where it is set for the loaded variables.


## Unload .env Files
When you change directories, the module automatically unloads environment variables from the previous directory's .env files.

```powershell
# Navigate to another directory
cd ..
```

And the output:

```terminal
The following .env files were removed:
↳ .\testme\.env

Unload .env file .\testme\.env:
↳ Unsetting environment variable: VAR1
```

> [!TIP]
> There is a hyperlink on the environment variables to Visual Studio Code with the reference to the line where it is set for the unloaded variables as well.

Check for .env Files
```powershell
# Find .env files in the current directory and its parents
Get-EnvFilesUpstream
```

# Contributing
Contributions are welcome! If you'd like to contribute to this project, please follow these steps:

1. Fork the repository.
2. Create a new branch for your feature or bugfix.
3. Make your changes and commit them.
4. Submit a pull request.

# License
This project is licensed under the MIT License. See the LICENSE file for details.

# Links
- GitHub Repository: https://github.com/CosmicDNA/ImportDotEnv
- PowerShell Gallery: https://www.powershellgallery.com/packages/ImportDotEnv

# Author
- Cosmic DNA
- GitHub: https://github.com/CosmicDNA
