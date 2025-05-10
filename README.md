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

# Enable Cd Integration (Optional: Enable if you are willing to have the variables loaded and unloaded automatically)
Enable-ImportDotEnvCdIntegration
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


### Listing Active Environment Variables

You can easily see which environment variables are currently managed by `ImportDotEnv`, what their effective values are, and which `.env` files contributed to their settings using the `-List` parameter.

> [!TIP]
> This feature provides a clear, VS Code-friendly table of all variables managed by ImportDotEnv, including clickable hyperlinks for quick navigation and search.

**Usage:**

```powershell
Import-DotEnv -List
```

**Output:**

| Name             | Defined In         |
|------------------|--------------------|
| GALLERY_2        | env                |
| GALLERY_API_KEY  | .env               |
| VK_ADD_LAYER_PATH| ..\baseDir\.env    |


- **Name**: The environment variable name. In supported terminals (like VS Code or Windows Terminal), this will be a clickable hyperlink that opens a search for the variable in your workspace.
- **Defined In**: Lists the `.env` files that define this variable, shown relative to your current directory. If a variable is defined in multiple `.env` files, each file is listed on a new line.

> [!NOTE]
> The value shown for each variable is the one that took precedence according to the loading hierarchy. If no .env configuration is currently active (e.g., after `Import-DotEnv -Unload` or if no .env files were found on the last load), a message will be displayed instead of the table.

---

## Additional Features

* **Efficient Variable Management:** Only variables that are new, removed, or have changed values are set/unset when changing directories. Unchanged variables are not redundantly reloaded or printed.
* **Smart Output:** The module only prints a ".env file" header if there are actual variable actions for that file. Restoration/unload output is grouped by file, and headers are only shown if there are actions for that file.
* **Pre-existing Variable Restoration:** If a variable existed before any `.env` file was loaded (e.g., a global or user environment variable), it will be restored to its original value when unloading or changing directories, even if it was overwritten by a `.env` file.
* **No Redundant Actions:** The module prevents duplicate or unnecessary file headers and does not print a file header if there are no actions for that file.
* **Accurate Hierarchical Restoration:** When loading multiple `.env` files hierarchically, the original value for each variable is captured before any are set, ensuring correct restoration even in complex scenarios.

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
