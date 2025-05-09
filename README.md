# ImportDotEnv PowerShell Module

![CI/CD](https://github.com/CosmicDNA/ImportDotEnv/actions/workflows/pester.yml/badge.svg)
[![Coverage](https://img.shields.io/endpoint?url=https://cosmicdna.github.io/ImportDotEnv/coverage.json)](https://cosmicdna.github.io/ImportDotEnv/)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/ImportDotEnv?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/ImportDotEnv)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

`ImportDotEnv` is a PowerShell module designed to simplify environment variable management using `.env` files. It supports hierarchical loading of `.env` files, automatic unloading/restoration of variables when changing directories (with `cd` integration), and provides helpful console output with VS Code integration.


---

## Features

*   **Hierarchical `.env` Loading**: Loads `.env` files from the current directory up to the root. Variables in child `.env` files override those from parent directories.
*   **Automatic Restoration**: When you navigate away from a directory (or load a new `.env` configuration), variables set by the previous `.env` files are automatically restored to their original values or unset if they were newly created.
*   **`cd` Integration**: Optionally integrates with `Set-Location` (and its aliases `cd`, `sl`) to automatically process `.env` files upon directory changes.
*   **VS Code Hyperlinks**: Console output for loaded variables includes hyperlinks that can take you directly to the variable definition in your `.env` file within VS Code. Restored variables link to a VS Code search for the variable name.
*   **Manual Invocation**: You can manually trigger `.env` processing for any directory.
*   **`.env` File Format**:
    *   Supports `VAR=value` assignments.
    *   Lines starting with `#` are treated as comments.
    *   Empty lines are ignored.
    *   Whitespace around variable names and values is trimmed.

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

### Manually Importing Environment Variables

To load environment variables from a `.env` file in the current directory or any parent directory, use the `Import-DotEnv` function:

```powershell
Import-DotEnv
```

This will:

1. Search for .env files in the current directory and its parent directories.
2. Load the environment variables from the found .env files.
3. Display a colorized output of the loaded variables.

### Enabling/Disabling `cd` Integration

For automatic `.env` processing when you change directories, you can enable or disable the `cd` integration.

**Enable Integration:**
```powershell
Enable-ImportDotEnvCdIntegration
```
This makes `Set-Location` (and its aliases `cd`, `sl`) automatically manage `.env` files. This is the recommended way to use the module for an interactive shell experience.

**Disable Integration:**
```powershell
Disable-ImportDotEnvCdIntegration
```
This restores `Set-Location`, `cd`, and `sl` to their default PowerShell behavior.

### Automatic `.env` Processing on Directory Change (with `cd` Integration)
When `cd` integration is enabled (using `Enable-ImportDotEnvCdIntegration`), the module overrides the `Set-Location` cmdlet to automatically load/unload .env files when you change directories:

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
- Code Coverage: https://cosmicdna.github.io/ImportDotEnv

# Author
- Cosmic DNA
- GitHub: https://github.com/CosmicDNA
