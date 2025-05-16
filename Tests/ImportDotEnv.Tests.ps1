# c:\Users\dani_\Workspaces\ImportDotEnv\Tests\ImportDotEnv.Tests.ps1

#Requires -Modules Pester
param(
    [string]$ModulePath = (Resolve-Path (Join-Path $PSScriptRoot "..\ImportDotEnv.psm1")).Path # Assuming tests are in a subfolder
)

# Disable debug messages for this test run
# $DebugPreference = 'Continue'

$Global:InitialEnvironment = @{}

# Import the module before InModuleScope so Pester can find it
Write-Debug "Top-level: Attempting to import module from '$ModulePath'"
if (-not (Test-Path $ModulePath)) {
    throw "Top-level: ModulePath '$ModulePath' does not exist."
}
$null = Import-Module $ModulePath -Force -PassThru
Write-Debug "Top-level: Import-Module executed."

# Wrap the entire Describe block in InModuleScope
InModuleScope 'ImportDotEnv' {

    # Define the helper function logic as a scriptblock outside InModuleScope,
    # but store it in script scope to be passed into the module scope for invocation.
    $script:InvokeImportDotEnvListAndCaptureOutputScriptBlock = {
        param(
            [string]$PathToLoadForList,
            [switch]$MockPSVersion5ForList
        )
        # This scriptblock runs inside the module scope when invoked with &
        $originalPSVersionTable = $null # Store original
        if ($MockPSVersion5ForList) {
            # Access script:PSVersionTable which is available in the module scope
            $originalPSVersionTable = $script:PSVersionTable
            $script:PSVersionTable = @{ PSVersion = [version]'5.1.0.0' } # Mock PS5 version
        }

        try {
            Import-DotEnv -Path $PathToLoadForList # Load .env files for the target path
            $output = & { Import-DotEnv -List } *>&1 # Capture output from -List
            return $output | Out-String
        }
        finally {
            if ($MockPSVersion5ForList -and $originalPSVersionTable) {
                $script:PSVersionTable = $originalPSVersionTable # Restore original PSVersionTable
            }
        }
    } # End of scriptblock definition

    Describe "Import-DotEnv Core and Integration Tests" {
        BeforeAll { # Runs once before any test in this Describe block
            $script:ImportDotEnvModule = Get-Module ImportDotEnv # Store it in script scope
            Write-Debug "BeforeAll: Import-Module executed."
            if (-not $script:ImportDotEnvModule) {
                throw "BeforeAll: ImportDotEnv module object could not be retrieved after Import-Module."
            }
            Write-Debug "BeforeAll: ImportDotEnv module IS loaded."

            # Store initial state of any test-related environment variables
            $testVarNames = @("TEST_VAR_GLOBAL", "TEST_VAR_A", "TEST_VAR_BASE", "TEST_VAR_OVERRIDE", "TEST_VAR_SUB", "NEW_VAR", "TEST_EMPTY_VAR", "PROJECT_ID", "MANUAL_TEST_VAR", "HELP_SWITCH_TEST_VAR")
            foreach ($varName in $testVarNames) {
                $Global:InitialEnvironment[$varName] = [Environment]::GetEnvironmentVariable($varName)
            }

            # Create temporary directory structure for tests using $TestDrive
            $script:TestRoot = Join-Path $TestDrive "ImportDotEnvPesterTests"
            New-Item -Path $script:TestRoot -ItemType Directory | Out-Null

            $script:ParentDirOfTestRoot = $TestDrive
            $script:ParentEnvPath = Join-Path $script:ParentDirOfTestRoot ".env"

            $script:DirWithOwnEnv = New-Item -Path (Join-Path $script:TestRoot "DirWithOwnEnv") -ItemType Directory
            Set-Content -Path (Join-Path $script:DirWithOwnEnv.FullName ".env") -Value "GALLERY_API_KEY=abc123`nGALLERY_2=def456"
            Write-Debug "BeforeAll: Content of DirWithOwnEnv/.env is '$(Get-Content (Join-Path $script:DirWithOwnEnv.FullName ".env") -Raw)'"

            $script:DirA = New-Item -Path (Join-Path $script:TestRoot "dirA") -ItemType Directory
            Set-Content -Path (Join-Path $script:DirA.FullName ".env") -Value "TEST_VAR_A=valA`nTEST_VAR_GLOBAL=valA_override"
            Write-Debug "BeforeAll: Content of dirA/.env is '$(Get-Content (Join-Path $script:DirA.FullName ".env") -Raw)'"

            $script:BaseDir = New-Item -Path (Join-Path $script:TestRoot "baseDir") -ItemType Directory
            Set-Content -Path (Join-Path $script:BaseDir.FullName ".env") -Value "TEST_VAR_BASE=base_val`nTEST_VAR_OVERRIDE=base_override_val"
            Write-Debug "BeforeAll: Content of baseDir/.env is '$(Get-Content (Join-Path $script:BaseDir.FullName ".env") -Raw)'"

            $script:SubDir = New-Item -Path (Join-Path $script:BaseDir.FullName "subDir") -ItemType Directory
            Set-Content -Path (Join-Path $script:SubDir.FullName ".env") -Value "TEST_VAR_SUB=sub_val`nTEST_VAR_OVERRIDE=sub_override_val"
            Write-Debug "BeforeAll: Content of subDir/.env is '$(Get-Content (Join-Path $script:SubDir.FullName ".env") -Raw)'"

            $script:DirB = New-Item -Path (Join-Path $script:TestRoot "dirB") -ItemType Directory
            Set-Content -Path (Join-Path $script:DirB.FullName ".env") -Value "NEW_VAR=new_value"
            Write-Debug "BeforeAll: Content of dirB/.env is '$(Get-Content (Join-Path $script:DirB.FullName ".env") -Raw)'"

            $script:DirC = New-Item -Path (Join-Path $script:TestRoot "dirC") -ItemType Directory
            Set-Content -Path (Join-Path $script:DirC.FullName ".env") -Value "TEST_EMPTY_VAR="
            Write-Debug "BeforeAll: Content of dirC/.env is '$(Get-Content (Join-Path $script:DirC.FullName ".env") -Raw)'"

            $script:Project1Dir = New-Item -Path (Join-Path $script:TestRoot "project1") -ItemType Directory
            Set-Content -Path (Join-Path $script:Project1Dir.FullName ".env") -Value "PROJECT_ID=P1"
            Write-Debug "BeforeAll: Content of project1/.env is '$(Get-Content (Join-Path $script:Project1Dir.FullName ".env") -Raw)'"

            $script:Project2Dir = New-Item -Path (Join-Path $script:TestRoot "project2") -ItemType Directory
            Set-Content -Path (Join-Path $script:Project2Dir.FullName ".env") -Value "PROJECT_ID=P2"
            Write-Debug "BeforeAll: Content of project2/.env is '$(Get-Content (Join-Path $script:Project2Dir.FullName ".env") -Raw)'"

            $script:NonEnvDir = New-Item -Path (Join-Path $script:TestRoot "nonEnvDir") -ItemType Directory
        }

        BeforeEach {
            $globalTestVarNames = @("TEST_VAR_GLOBAL", "TEST_VAR_BASE", "TEST_VAR_OVERRIDE", "TEST_EMPTY_VAR", "PROJECT_ID", "MANUAL_TEST_VAR", "HELP_SWITCH_TEST_VAR")
            $scenarioSpecificVarNames = @("TEST_VAR_A", "TEST_VAR_SUB", "NEW_VAR")

            foreach ($varName in $globalTestVarNames) {
                $initialVal = $Global:InitialEnvironment[$varName]
                if ($null -eq $initialVal) {
                    if (Test-Path "Env:\$varName") { Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue }
                    [Environment]::SetEnvironmentVariable($varName, $null)
                } else {
                    [Environment]::SetEnvironmentVariable($varName, $initialVal)
                }
            }

            foreach ($varName in $scenarioSpecificVarNames) {
                Write-Debug "BeforeEach: Unconditionally clearing scenario-specific var '$varName'. Initial Test-Path: $(Test-Path \"Env:\\$varName\"), Initial Value: '$([Environment]::GetEnvironmentVariable($varName))'"
                [Environment]::SetEnvironmentVariable($varName, $null)
                if (Test-Path "Env:\$varName") { Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue }

                if ([Environment]::GetEnvironmentVariable($varName) -ne $null) {
                    Write-Warning "BeforeEach: FAILED to clear '$varName'. It is still '$([Environment]::GetEnvironmentVariable($varName))'."
                } else {
                    Write-Debug "BeforeEach: Successfully cleared '$varName'. Current Value: '$([Environment]::GetEnvironmentVariable($varName))', Test-Path: $(Test-Path \"Env:\\$varName\")"
                }
            }
            Write-Debug "BeforeEach (Start): Environment variables reset."
            $currentTestRoot = $script:TestRoot
            Write-Debug "BeforeEach: Value of currentTestRoot (from script:TestRoot) is '$currentTestRoot'"
            if (-not $currentTestRoot) { throw "BeforeEach: currentTestRoot (from script:TestRoot) is not set!" }

            if (-not $script:ImportDotEnvModule) {
                throw "BeforeEach: script:ImportDotEnvModule is not available for state reset!"
            }
            Write-Debug "BeforeEach: Directly resetting ImportDotEnv module's internal script variables."
            $script:trueOriginalEnvironmentVariables = @{}
            $script:previousEnvFiles = @()
            $script:previousWorkingDirectory = "RESET_BY_BEFORE_EACH_TEST_HOOK"

            $currentTrueOriginals = $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('trueOriginalEnvironmentVariables')
            Write-Debug "BeforeEach (Describe): After reset, trueOriginalEnvironmentVariables count: $($currentTrueOriginals.Count). Keys: $($currentTrueOriginals.Keys -join ', ')"
            if ($script:TestRoot -and (Test-Path $script:TestRoot)) {
                 Microsoft.PowerShell.Management\Set-Location $script:TestRoot
                 Write-Debug "Describe-level BeforeEach: PWD reset to $($PWD.Path)"
            }

            Write-Debug "BeforeEach: Module state reset. TrueOriginalEnvironmentVariables count: $($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('trueOriginalEnvironmentVariables').Count)"
            Write-Debug "BeforeEach: Module state reset. PreviousEnvFiles count: $($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousEnvFiles').Count)"
            Write-Debug "BeforeEach: Module state reset. PreviousWorkingDirectory: $($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousWorkingDirectory'))"
        }

        AfterAll {
            if ($script:TestRoot -and $PWD.Path.StartsWith($script:TestRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Debug "AfterAll: Current PWD '$($PWD.Path)' is inside TestRoot. Changing location to '$($script:ParentDirOfTestRoot)'."
                Microsoft.PowerShell.Management\Set-Location $script:ParentDirOfTestRoot
            }
            Write-Debug "AfterAll: Restoring initial environment variables."
            foreach ($varName in $Global:InitialEnvironment.Keys) {
                $initialVal = $Global:InitialEnvironment[$varName]
                if ($null -eq $initialVal) {
                    if (Test-Path "Env:\$varName") {
                        Write-Debug "AfterAll: Removing environment variable '$varName' as its initial state was null."
                        Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Write-Debug "AfterAll: Restoring environment variable '$varName' to '$initialVal'."
                    [Environment]::SetEnvironmentVariable($varName, $initialVal)
                }
            }
            if (Get-Command Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue) {
                Write-Debug "AfterAll: Calling Disable-ImportDotEnvCdIntegration."
                Disable-ImportDotEnvCdIntegration
                Write-Debug "AfterAll: Disable-ImportDotEnvCdIntegration finished."
                $cdCmdAfterDisable = Get-Command cd -ErrorAction SilentlyContinue
                Write-Debug "AfterAll: State of 'cd' after Disable-ImportDotEnvCdIntegration: Name: $($cdCmdAfterDisable.Name), Type: $($cdCmdAfterDisable.CommandType), Definition: $($cdCmdAfterDisable.Definition)"
                if ($cdCmdAfterDisable.CommandType -ne [System.Management.Automation.CommandTypes]::Alias) {
                    Write-Warning "AfterAll: 'cd' IS NOT an alias after Disable-ImportDotEnvCdIntegration. This is unexpected."
                } else {
                    Write-Debug "AfterAll: 'cd' IS an alias as expected."
                }
            } else {
                Write-Warning "AfterAll: Disable-ImportDotEnvCdIntegration command not found. Skipping disable."
            }
            Write-Debug "AfterAll: Calling Remove-Module ImportDotEnv -Force."
            Remove-Module ImportDotEnv -Force -ErrorAction SilentlyContinue
            Write-Debug "AfterAll: Remove-Module ImportDotEnv -Force finished."
            $cdCmdAfterRemoveModule = Get-Command cd -ErrorAction SilentlyContinue
            Write-Debug "AfterAll: State of 'cd' after Remove-Module: Name: $($cdCmdAfterRemoveModule.Name), Type: $($cdCmdAfterRemoveModule.CommandType), Definition: $($cdCmdAfterRemoveModule.Definition)"
        }

        $script:GetEnvFilesUpstreamMock = {
            param([string]$Directory)
            $resolvedDir = Convert-Path $Directory

            if ($resolvedDir -eq $script:DirA.FullName) { return @(Join-Path $script:DirA.FullName ".env") }
            if ($resolvedDir -eq $script:DirB.FullName) { return @(Join-Path $script:DirB.FullName ".env") }
            if ($resolvedDir -eq $script:DirC.FullName) { return @(Join-Path $script:DirC.FullName ".env") }
            if ($resolvedDir -eq $script:SubDir.FullName) { return @( (Join-Path $script:BaseDir.FullName ".env"), (Join-Path $script:SubDir.FullName ".env") ) }
            if ($resolvedDir -eq $script:BaseDir.FullName) { return @(Join-Path $script:BaseDir.FullName ".env") }
            if ($resolvedDir -eq $script:Project1Dir.FullName) { return @(Join-Path $script:Project1Dir.FullName ".env") }
            if ($resolvedDir -eq $script:Project2Dir.FullName) { return @(Join-Path $script:Project2Dir.FullName ".env") }
            if ($resolvedDir -eq $script:NonEnvDir.FullName) { return @() }

            if ($resolvedDir -eq $script:TestRoot) {
                $filesToReturn = @()
                if (Test-Path $script:ParentEnvPath) {
                    # $filesToReturn += $script:ParentEnvPath
                }
                $testRootOwnEnv = Join-Path $script:TestRoot ".env"
                if (Test-Path $testRootOwnEnv) { return @($testRootOwnEnv) } else { return @() }
            }
            if ($resolvedDir -eq $script:ParentDirOfTestRoot) {
                if (Test-Path $script:ParentEnvPath) {
                    return @($script:ParentEnvPath)
                }
                return @()
            }
            return @()
        }

        Context "Helper Function Tests" {
            It "Format-EnvFilePath should handle empty core path" {
                Mock Get-RelativePath { return ".env" } -ModuleName ImportDotEnv
                $result = Format-EnvFilePath -Path ".env" -BasePath "."
                $result | Should -Be ".env"
            }

            It "Get-EnvVarsFromFiles (via Read-EnvFile) handles non-existent file" {
                $nonExistentFile = Join-Path $script:TestRoot "nonexistent.env"
                $vars = Get-EnvVarsFromFiles -Files @($nonExistentFile) -BasePath $script:TestRoot
                $vars | Should -BeOfType ([System.Collections.Hashtable])
                $vars.Count | Should -Be 0
            }
        }

        Context "Import-DotEnv Direct Invocation Parameters" {
            It "Import-DotEnv load path handles no .env files found" {
                Mock Get-EnvFilesUpstream { return @() } -ModuleName ImportDotEnv
                Import-DotEnv -Path $script:TestRoot
                ($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousEnvFiles').Count) | Should -Be 0
            }

            It "Import-DotEnv -Help switch should display help and not alter state or environment" {
                # Arrange: Store initial module state and a test environment variable
                $initialPreviousEnvFiles = $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousEnvFiles')
                $initialPreviousWorkingDirectory = $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousWorkingDirectory')
                $initialTrueOriginals = $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('trueOriginalEnvironmentVariables').Clone()

                $testHelpVarName = "HELP_SWITCH_TEST_VAR"
                $initialTestHelpVarValue = "initial_help_value_for_test"
                [Environment]::SetEnvironmentVariable($testHelpVarName, $initialTestHelpVarValue)
                if (-not $Global:InitialEnvironment.ContainsKey($testHelpVarName)) {
                    $Global:InitialEnvironment[$testHelpVarName] = $initialTestHelpVarValue
                }

                # Act: Call Import-DotEnv -Help and capture output
                $output = & { Import-DotEnv -Help } *>&1
                $outputString = $output | Out-String

                # Assert: Help text is displayed
                $outputString | Should -Match "Import-DotEnv Module Help"
                $outputString | Should -Match "Usage:"
                $outputString | Should -Match "Loads .env files from the specified path"
                $outputString | Should -Match "Enable-ImportDotEnvCdIntegration \[-Silent\]" # Check for the new -Silent info

                # Assert: Environment variable is unchanged
                [Environment]::GetEnvironmentVariable($testHelpVarName) | Should -Be $initialTestHelpVarValue

                # Assert: Module internal state is unchanged
                $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousEnvFiles') | Should -Be $initialPreviousEnvFiles
                $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousWorkingDirectory') | Should -Be $initialPreviousWorkingDirectory
                ($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('trueOriginalEnvironmentVariables').Count) | Should -Be $initialTrueOriginals.Count
            }
        }

        Context "Core Import-DotEnv Functionality (Manual Invocation)" {
            It "loads variables when Import-DotEnv is called directly and restores on subsequent call for parent" {
                Write-Debug "DIAGNOSTIC (Test Start): Test 'loads variables...' starting. DebugPreference: $DebugPreference"
                Write-Debug "DIAGNOSTIC (Test Start): script:TestRoot is '$($script:TestRoot)'"
                $initialManualTestVar = [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR")
                $manualEnvFile = Join-Path $script:TestRoot ".env"
                Set-Content -Path $manualEnvFile -Value "MANUAL_TEST_VAR=loaded_manual"
                $ErrorActionPreferenceBackup = $ErrorActionPreference
                $ErrorActionPreference = 'Stop'
                $Error.Clear()
                try {
                    Push-Location $script:TestRoot
                    Write-Debug "DIAGNOSTIC (Inside Try): PWD after Push-Location: $($PWD.Path)"
                    Write-Debug "DIAGNOSTIC (Inside Try): MANUAL_TEST_VAR before mock setup: '$([Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR"))'"
                    Write-Debug "DIAGNOSTIC (Inside Try): Does manualEnvFile '$manualEnvFile' exist? $(Test-Path $manualEnvFile). Content: '$(try { Get-Content $manualEnvFile -Raw } catch { "ERROR READING FILE" })'"

                    $script:mockGetEnvFilesUpstreamOutput = $null
                    Mock Get-EnvFilesUpstream {
                        param([string]$DirectoryBeingProcessed)
                        $resolvedDirForMock = Convert-Path $DirectoryBeingProcessed
                        Write-Debug "DIAGNOSTIC (Mock): Get-EnvFilesUpstream called for directory '$DirectoryBeingProcessed' (resolved to '$resolvedDirForMock')."
                        $filesToReturnFromMock = $script:GetEnvFilesUpstreamMock.Invoke($DirectoryBeingProcessed)
                        $script:mockGetEnvFilesUpstreamOutput = $filesToReturnFromMock
                        Write-Debug "DIAGNOSTIC (Mock): Get-EnvFilesUpstream returning files: $($filesToReturnFromMock -join ', ')"
                        return $filesToReturnFromMock
                    } -ModuleName ImportDotEnv

                    Write-Debug "DIAGNOSTIC (Inside Try): Calling Import-DotEnv for first load. Initial MANUAL_TEST_VAR: '$initialManualTestVar'"
                    Import-DotEnv -Path "."
                    Write-Debug "DIAGNOSTIC (Inside Try): Import-DotEnv -Path '.' completed."
                    Write-Debug "DIAGNOSTIC (Inside Try): Mock Get-EnvFilesUpstream actually returned: $($script:mockGetEnvFilesUpstreamOutput -join ', ')"
                    $currentManualTestVarValue = [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR")
                    Write-Debug "DIAGNOSTIC (Inside Try): MANUAL_TEST_VAR value immediately before assertion: '$currentManualTestVarValue'"

                    $modulePreviousEnvFiles = $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousEnvFiles')
                    Write-Debug "DIAGNOSTIC (Inside Try): Module's internal previousEnvFiles: $($modulePreviousEnvFiles -join ', ')"
                    $moduleTrueOriginals = $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('trueOriginalEnvironmentVariables')
                    Write-Debug "DIAGNOSTIC (Inside Try): Module's internal trueOriginals for MANUAL_TEST_VAR: '$($moduleTrueOriginals['MANUAL_TEST_VAR'])'"
                    [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR") | Should -Be "loaded_manual"
                    Write-Debug "DIAGNOSTIC (Inside Try): Assertion 1 passed."
                    Write-Debug "DIAGNOSTIC (Inside Try): Module's trueOriginals for MANUAL_TEST_VAR: '$($script:trueOriginalEnvironmentVariables['MANUAL_TEST_VAR'])'"

                    Write-Debug "DIAGNOSTIC (Inside Try): Calling Import-DotEnv for parent restore. PWD: $($PWD.Path)"
                    Import-DotEnv -Path $script:ParentDirOfTestRoot
                    $restoredManualTestVarValue = [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR")
                    Write-Debug "DIAGNOSTIC (Inside Try): MANUAL_TEST_VAR after parent restore call: '$restoredManualTestVarValue'"

                    if ($null -eq $initialManualTestVar) {
                        (Test-Path Env:\MANUAL_TEST_VAR) | Should -Be $false
                        ([Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR")) | Should -BeNullOrEmpty "because initial was null"
                    } else {
                        [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR") | Should -Be $initialManualTestVar
                    }
                    Write-Debug "DIAGNOSTIC (Inside Try): Assertion 2 passed."
                    Pop-Location
                    Write-Debug "DIAGNOSTIC (Inside Try): Pop-Location successful."
                }
                catch {
                    Write-Error "Test 'loads variables...' FAILED with exception: $($_.ToString())"
                    Write-Error "Exception StackTrace: $($_.ScriptStackTrace)"
                    throw "Test 'loads variables...' failed explicitly due to caught error."
                }
                finally {
                    $ErrorActionPreference = $ErrorActionPreferenceBackup
                    if (Test-Path $manualEnvFile) { Remove-Item $manualEnvFile -Force -ErrorAction SilentlyContinue }
                    if ($null -eq $initialManualTestVar) { [Environment]::SetEnvironmentVariable("MANUAL_TEST_VAR", $null) } else { [Environment]::SetEnvironmentVariable("MANUAL_TEST_VAR", $initialManualTestVar) }
                }
            }
        }

        Context "Set-Location Integration (Enable/Disable Functionality)" {
            AfterEach {
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue
            }

            It "should have Set-Location, cd, and sl in their default states after module import (or after disable)" {
                # The AfterEach for this context ensures Disable-ImportDotEnvCdIntegration has been called.
                # This test verifies the state *after* disable, or the initial state.
                $cmd = Get-Command Set-Location -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.ModuleName | Should -Be "Microsoft.PowerShell.Management"

                $cmd = Get-Command cd -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Set-Location"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.ResolvedCommand.ModuleName | Should -Be "Microsoft.PowerShell.Management"

                $cmd = Get-Command sl -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Set-Location"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.ResolvedCommand.ModuleName | Should -Be "Microsoft.PowerShell.Management"
            }

            It "Enable-ImportDotEnvCdIntegration should correctly modify Set-Location, and cd/sl should follow" {
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
                Enable-ImportDotEnvCdIntegration

                $cmd = Get-Command Set-Location -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNull
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "ImportDotEnv\Invoke-ImportDotEnvSetLocationWrapper"
                $cmd.ResolvedCommand.Name | Should -Be "Invoke-ImportDotEnvSetLocationWrapper"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Function)
                $cmd.ResolvedCommand.ModuleName | Should -Be "ImportDotEnv"

                $cmd = Get-Command cd -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNull
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Invoke-ImportDotEnvSetLocationWrapper"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Function)
                $cmd.ResolvedCommand.ModuleName | Should -Be "ImportDotEnv"
                $cmd.Name | Should -Be "cd"

                $cmd = Get-Command sl -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNull
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Invoke-ImportDotEnvSetLocationWrapper"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Function)
                $cmd.ResolvedCommand.ModuleName | Should -Be "ImportDotEnv"
                $cmd.Name | Should -Be "sl"
            }

            It "Disable-ImportDotEnvCdIntegration should correctly restore Set-Location, and cd/sl should follow" {
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
                Enable-ImportDotEnvCdIntegration
                Disable-ImportDotEnvCdIntegration

                $cmd = Get-Command Set-Location -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.Name | Should -Be "Set-Location"
                $cmd.ModuleName | Should -Be "Microsoft.PowerShell.Management"

                $cmd = Get-Command cd -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Set-Location"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.ResolvedCommand.ModuleName | Should -Be "Microsoft.PowerShell.Management"

                $cmd = Get-Command sl -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Set-Location"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.ResolvedCommand.ModuleName | Should -Be "Microsoft.PowerShell.Management"
            }

            It "Disable-ImportDotEnvCdIntegration keeps vars loaded (no longer unloads)" {
                $newVarName = "NEW_VAR_FOR_DISABLE_TEST"
                $existingVarName = "EXISTING_VAR_FOR_DISABLE_TEST"
                $initialExistingValue = "initial_value_for_existing"

                if (Test-Path "Env:\$newVarName") { Remove-Item "Env:\$newVarName" -Force }
                (Test-Path "Env:\$newVarName") | Should -Be $false
                [Environment]::SetEnvironmentVariable($existingVarName, $initialExistingValue)
                [Environment]::GetEnvironmentVariable($existingVarName) | Should -Be $initialExistingValue

                $dirBEnvPath = Join-Path $script:DirB.FullName ".env"
                $originalDirBEnvContent = Get-Content $dirBEnvPath -Raw -ErrorAction SilentlyContinue
                Set-Content -Path $dirBEnvPath -Value "$newVarName=new_value_from_env`n$existingVarName=overwritten_by_env"

                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv

                Microsoft.PowerShell.Management\Set-Location $script:DirB.FullName
                Enable-ImportDotEnvCdIntegration

                [Environment]::GetEnvironmentVariable($newVarName) | Should -Be "new_value_from_env"
                [Environment]::GetEnvironmentVariable($existingVarName) | Should -Be "overwritten_by_env"

                Disable-ImportDotEnvCdIntegration

                (Test-Path "Env:\$newVarName") | Should -Be $true
                [Environment]::GetEnvironmentVariable($newVarName) | Should -Be "new_value_from_env"
                [Environment]::GetEnvironmentVariable($existingVarName) | Should -Be "overwritten_by_env"

                if ($null -ne $originalDirBEnvContent) { Set-Content -Path $dirBEnvPath -Value $originalDirBEnvContent -Force } else { Remove-Item $dirBEnvPath -Force -ErrorAction SilentlyContinue }
                [Environment]::SetEnvironmentVariable($newVarName, $null)
                [Environment]::SetEnvironmentVariable($existingVarName, $initialExistingValue)
            }

            It "loads .env variables for the current directory upon enabling integration and restores on subsequent cd" {
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue
                (Get-Command Set-Location).CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)

                $initialTestVarA = "initial_A_for_enable_test"
                $initialTestVarGlobal = "initial_GLOBAL_for_enable_test"
                [Environment]::SetEnvironmentVariable("TEST_VAR_A", $initialTestVarA)
                [Environment]::SetEnvironmentVariable("TEST_VAR_GLOBAL", $initialTestVarGlobal)

                Microsoft.PowerShell.Management\Set-Location $script:DirA.FullName

                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be $initialTestVarA
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $initialTestVarGlobal

                Enable-ImportDotEnvCdIntegration

                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be "valA"
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be "valA_override"

                Set-Location $script:TestRoot

                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be $initialTestVarA
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $initialTestVarGlobal
            }

            It "keeps .env variables loaded upon disabling integration (no longer unloads)" {
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue
                (Get-Command Set-Location).CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)

                $initialTestVarA = "initial_A_for_disable_test"
                $initialTestVarGlobal = "initial_GLOBAL_for_disable_test"
                [Environment]::SetEnvironmentVariable("TEST_VAR_A", $initialTestVarA)
                [Environment]::SetEnvironmentVariable("TEST_VAR_GLOBAL", $initialTestVarGlobal)

                Microsoft.PowerShell.Management\Set-Location $script:DirA.FullName
                Enable-ImportDotEnvCdIntegration

                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be "valA"
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be "valA_override"

                Disable-ImportDotEnvCdIntegration

                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be "valA"
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be "valA_override"

                (Get-Command Set-Location).CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                (Get-Command cd).Definition | Should -Be "Set-Location"
            }

            It "Enable-ImportDotEnvCdIntegration -Silent should enable integration without verbose output" {
                # Arrange
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv

                # Act
                $output = & { Enable-ImportDotEnvCdIntegration -Silent } *>&1
                $outputString = $output | Out-String

                # Assert: No verbose output from Enable-ImportDotEnvCdIntegration itself
                $outputString | Should -Not -Match "Enabling ImportDotEnv integration"
                $outputString | Should -Not -Match "ImportDotEnv 'Set-Location', 'cd', 'sl' integration enabled!"

                # Assert: Integration is enabled
                $cmd = Get-Command Set-Location -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNull
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "ImportDotEnv\Invoke-ImportDotEnvSetLocationWrapper"
            }
        }

        Context "Set-Location Integration - Variable Loading Scenarios" {
            BeforeEach {
                $script:trueOriginalEnvironmentVariables = @{}
                Write-Debug "BeforeEach (Context): Manually reset trueOriginalEnvironmentVariables before Enable."
                Enable-ImportDotEnvCdIntegration
                $trueOriginalsAfterEnable = $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('trueOriginalEnvironmentVariables')
                Write-Debug "BeforeEach (Context): After Enable-ImportDotEnvCdIntegration, trueOriginalEnvironmentVariables count: $($trueOriginalsAfterEnable.Count). Keys: $($trueOriginalsAfterEnable.Keys -join ', ')"
                Write-Debug "BeforeEach (Context): Value of TEST_VAR_A in trueOriginals: '$($trueOriginalsAfterEnable['TEST_VAR_A'])'"
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
            }
            AfterEach {
                Disable-ImportDotEnvCdIntegration
            }

            It "loads variables from .env and restores global on exit" {
                $initialTestVarA = $Global:InitialEnvironment["TEST_VAR_A"]

                if ($null -eq $initialTestVarA) {
                    [Environment]::SetEnvironmentVariable("TEST_VAR_A", $null)
                    if(Test-Path Env:\TEST_VAR_A) { Remove-Item Env:\TEST_VAR_A -Force }
                } else {
                    [Environment]::SetEnvironmentVariable("TEST_VAR_A", $initialTestVarA)
                }

                Set-Location $script:DirA.FullName
                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be "valA"

                Set-Location $script:TestRoot

                $actualValue = [Environment]::GetEnvironmentVariable("TEST_VAR_A")
                $existsInPSDrive = Test-Path "Env:\TEST_VAR_A"
                $trueOriginalsAtAssert = $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('trueOriginalEnvironmentVariables')

                Write-Debug "At assertion, value of TEST_VAR_A in trueOriginals: '$($trueOriginalsAtAssert['TEST_VAR_A'])'"

                if ($null -eq $initialTestVarA) {
                    $actualValue | Should -BeNullOrEmpty
                    $existsInPSDrive | Should -Be $false
                } else {
                    $actualValue | Should -Be $initialTestVarA
                }
            }

            It "loads hierarchically and restores correctly level by level" {
                $initialTestVarBase = $Global:InitialEnvironment["TEST_VAR_BASE"]
                $initialTestVarOverride = $Global:InitialEnvironment["TEST_VAR_OVERRIDE"]
                $initialTestVarSub = $Global:InitialEnvironment["TEST_VAR_SUB"]

                if ($null -ne $initialTestVarBase) { [Environment]::SetEnvironmentVariable("TEST_VAR_BASE", $initialTestVarBase) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_BASE", $null); if(Test-Path Env:\TEST_VAR_BASE){Remove-Item Env:\TEST_VAR_BASE -Force} }
                if ($null -ne $initialTestVarOverride) { [Environment]::SetEnvironmentVariable("TEST_VAR_OVERRIDE", $initialTestVarOverride) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_OVERRIDE", $null); if(Test-Path Env:\TEST_VAR_OVERRIDE){Remove-Item Env:\TEST_VAR_OVERRIDE -Force} }
                if ($null -ne $initialTestVarSub) { [Environment]::SetEnvironmentVariable("TEST_VAR_SUB", $initialTestVarSub) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_SUB", $null); if(Test-Path Env:\TEST_VAR_SUB){Remove-Item Env:\TEST_VAR_SUB -Force} }


                Set-Location $script:SubDir.FullName
                [Environment]::GetEnvironmentVariable("TEST_VAR_BASE") | Should -Be "base_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_SUB") | Should -Be "sub_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "sub_override_val"

                Set-Location $script:BaseDir.FullName
                if ($null -eq $initialTestVarSub) { (Test-Path "Env:\TEST_VAR_SUB") | Should -Be $false } else { [Environment]::GetEnvironmentVariable("TEST_VAR_SUB") | Should -Be $initialTestVarSub }
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "base_override_val"

                Set-Location $script:TestRoot
                if ($null -eq $initialTestVarBase) { (Test-Path "Env:\TEST_VAR_BASE") | Should -Be $false } else { [Environment]::GetEnvironmentVariable("TEST_VAR_BASE") | Should -Be $initialTestVarBase }
                if ($null -eq $initialTestVarSub) { (Test-Path "Env:\TEST_VAR_SUB") | Should -Be $false } else { [Environment]::GetEnvironmentVariable("TEST_VAR_SUB") | Should -Be $initialTestVarSub }
                if ($null -eq $initialTestVarOverride) { (Test-Path "Env:\TEST_VAR_OVERRIDE") | Should -Be $false } else { [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be $initialTestVarOverride }
            }

            It "creates a new variable and removes it on exit (restores to non-existent)" {
                $initialNewVar = $Global:InitialEnvironment["NEW_VAR"]
                if ($null -eq $initialNewVar) { [Environment]::SetEnvironmentVariable("NEW_VAR", $null); if(Test-Path Env:\NEW_VAR){Remove-Item Env:\NEW_VAR -Force} } else { [Environment]::SetEnvironmentVariable("NEW_VAR", $initialNewVar) }

                Set-Location $script:DirB.FullName
                [Environment]::GetEnvironmentVariable("NEW_VAR") | Should -Be "new_value"

                Set-Location $script:TestRoot
                if ($null -eq $initialNewVar) { (Test-Path "Env:\NEW_VAR") | Should -Be $false } else { [Environment]::GetEnvironmentVariable("NEW_VAR") | Should -Be $initialNewVar }
            }

            It "sets variable to empty string from .env and restores previous value on exit" {
                $initialEmptyVar = "initial_empty_test_val_specific"
                [Environment]::SetEnvironmentVariable("TEST_EMPTY_VAR", $initialEmptyVar)

                Set-Location $script:DirC.FullName
                [Environment]::GetEnvironmentVariable("TEST_EMPTY_VAR") | Should -BeNullOrEmpty

                Set-Location $script:TestRoot
                [Environment]::GetEnvironmentVariable("TEST_EMPTY_VAR") | Should -Be $initialEmptyVar
            }

            It "correctly unloads project1 vars and loads project2 vars, then restores global" {
                $initialProjectId = "global_project_id_specific"
                [Environment]::SetEnvironmentVariable("PROJECT_ID", $initialProjectId)

                Set-Location $script:Project1Dir.FullName
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be "P1"

                Set-Location $script:Project2Dir.FullName
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be "P2"

                Set-Location $script:TestRoot
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be $initialProjectId
            }

            It "should not alter existing environment variables when moving to a dir with no .env" {
                $initialGlobalVar = "no_env_test_initial_specific"
                [Environment]::SetEnvironmentVariable("TEST_VAR_GLOBAL", $initialGlobalVar)

                Set-Location $script:NonEnvDir.FullName
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $initialGlobalVar

                Set-Location $script:TestRoot
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $initialGlobalVar
            }

            It "loads variables from .env files in the correct order when using Set-Location" {
                $initialTestVarBase = $Global:InitialEnvironment["TEST_VAR_BASE"]
                $initialTestVarSub = $Global:InitialEnvironment["TEST_VAR_SUB"]
                $initialTestVarOverride = $Global:InitialEnvironment["TEST_VAR_OVERRIDE"]

                if ($null -ne $initialTestVarBase) { [Environment]::SetEnvironmentVariable("TEST_VAR_BASE", $initialTestVarBase) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_BASE", $null); if(Test-Path Env:\TEST_VAR_BASE){Remove-Item Env:\TEST_VAR_BASE -Force} }
                if ($null -ne $initialTestVarSub) { [Environment]::SetEnvironmentVariable("TEST_VAR_SUB", $initialTestVarSub) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_SUB", $null); if(Test-Path Env:\TEST_VAR_SUB){Remove-Item Env:\TEST_VAR_SUB -Force} }
                if ($null -ne $initialTestVarOverride) { [Environment]::SetEnvironmentVariable("TEST_VAR_OVERRIDE", $initialTestVarOverride) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_OVERRIDE", $null); if(Test-Path Env:\TEST_VAR_OVERRIDE){Remove-Item Env:\TEST_VAR_OVERRIDE -Force} }

                Set-Location $script:SubDir.FullName
                [Environment]::GetEnvironmentVariable("TEST_VAR_BASE") | Should -Be "base_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_SUB") | Should -Be "sub_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "sub_override_val"
            }
        }

        Context "Import-DotEnv -List switch" {
            $baseDirForListTestCtx = $null
            $subDirForListTestCtx = $null
            $envFile1ListCtx = $null
            $envFile2ListCtx = $null

            BeforeEach {
                $baseDirForListTestCtx = Join-Path $TestDrive "ListSwitchTestDirCtx"
                if (Test-Path $baseDirForListTestCtx) { Remove-Item $baseDirForListTestCtx -Recurse -Force }
                New-Item -ItemType Directory -Path $baseDirForListTestCtx | Out-Null

                $subDirForListTestCtx = Join-Path $baseDirForListTestCtx "ListSwitchSubDirCtx"
                New-Item -ItemType Directory -Path $subDirForListTestCtx | Out-Null

                $envFile1ListCtx = Join-Path $baseDirForListTestCtx '.env'
                Set-Content -Path $envFile1ListCtx -Value @(
                    'FOO_LIST=bar_list',
                    'BAZ_LIST=qux_list'
                )

                $envFile2ListCtx = Join-Path $subDirForListTestCtx '.env'
                Set-Content -Path $envFile2ListCtx -Value @(
                    'FOO_LIST=override_list',
                    'GEZ_LIST=whatever_list'
                )

                Mock Get-EnvFilesUpstream {
                    param(
                        [string]$DirectoryToScan
                    )
                    $resolvedDirToScan = Convert-Path $DirectoryToScan
                    if ($resolvedDirToScan -eq $subDirForListTestCtx) {
                        return @($envFile1ListCtx, $envFile2ListCtx)
                    }
                    if ($resolvedDirToScan -eq $baseDirForListTestCtx) {
                        return @($envFile1ListCtx)
                    }
                    return @()
                } -ModuleName ImportDotEnv # Removed -Scope It, will default to Context scope
            }

            AfterEach {
                # Ensure PWD is not inside the directory to be deleted
                Push-Location $script:TestRoot # Go to a safe location
                try {
                    if (Test-Path $baseDirForListTestCtx) {
                        Remove-Item -Path $baseDirForListTestCtx -Recurse -Force
                    }
                }
                finally {
                    Pop-Location # Return to original PWD
                }
            }

            It 'lists active variables and their defining files when state is active (PowerShell 7+)' {
                Push-Location $subDirForListTestCtx
                try {
                    $outputString = & $script:InvokeImportDotEnvListAndCaptureOutputScriptBlock -PathToLoadForList $subDirForListTestCtx
                }
                finally {
                    try { Pop-Location -ErrorAction Stop }
                    catch {
                        Write-Warning "Pop-Location failed in test 'lists active variables (PS7+)', directory likely removed by AfterEach. Setting PWD to TestRoot."
                        Set-Location $script:TestRoot
                    }
                }
                $outputString | Should -Match 'FOO_LIST'
                $outputString | Should -Match 'BAZ_LIST'
                $outputString | Should -Match 'GEZ_LIST'
                $outputString | Should -Match '\.env'
            }

            It 'lists active variables in table format when PSVersion is 5 (Windows PowerShell)' {
                Push-Location $subDirForListTestCtx
                try {
                    $outputString = & $script:InvokeImportDotEnvListAndCaptureOutputScriptBlock -PathToLoadForList $subDirForListTestCtx -MockPSVersion5ForList $true
                }
                finally {
                    try { Pop-Location -ErrorAction Stop }
                    catch {
                        Write-Warning "Pop-Location failed in test 'lists active variables (PS5)', directory likely removed by AfterEach. Setting PWD to TestRoot."
                        Set-Location $script:TestRoot
                    }
                }
                $outputString | Should -Match 'FOO_LIST'
                $outputString | Should -Match 'BAZ_LIST'
                $outputString | Should -Match 'GEZ_LIST'
                $outputString | Should -Match '\.env'
                $outputString | Should -Match 'Name\s+Defined In'
                $outputString | Should -Match '----\s+----------'
            }

            It 'reports correctly when no .env files are active' {
                $script:previousEnvFiles = @()
                $script:previousWorkingDirectory = "STATE_FOR_NO_ACTIVE_LIST_TEST"

                $output = & { Import-DotEnv -List } *>&1
                $outputString = $output | Out-String
                $outputString | Should -Match 'No .env configuration is currently active or managed by ImportDotEnv.'
            }
        }

        Context "Import-DotEnv -Unload switch" {
            It 'unloads variables and resets state after a load' {
                $tempDirForUnloadCtx = Join-Path $TestDrive "UnloadSwitchTestDirCtx"
                if (Test-Path $tempDirForUnloadCtx) { Remove-Item $tempDirForUnloadCtx -Recurse -Force }
                New-Item -ItemType Directory -Path $tempDirForUnloadCtx | Out-Null
                $envFileForUnloadCtx = Join-Path $tempDirForUnloadCtx '.env'
                $varNameForUnloadCtx = 'UNLOAD_TEST_VAR_CTX'
                Set-Content -Path $envFileForUnloadCtx -Value "$varNameForUnloadCtx=unload_me_ctx"

                $initialVarValueForUnloadCtx = [Environment]::GetEnvironmentVariable($varNameForUnloadCtx)
                if (-not $Global:InitialEnvironment.ContainsKey($varNameForUnloadCtx)) {
                    $Global:InitialEnvironment[$varNameForUnloadCtx] = $initialVarValueForUnloadCtx
                }

                Mock Get-EnvFilesUpstream { param($Directory) return @($envFileForUnloadCtx) } -ModuleName ImportDotEnv

                Import-DotEnv -Path $tempDirForUnloadCtx
                [Environment]::GetEnvironmentVariable($varNameForUnloadCtx) | Should -Be 'unload_me_ctx'
                $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousEnvFiles') | Should -BeExactly @($envFileForUnloadCtx)
                $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousWorkingDirectory') | Should -Be $tempDirForUnloadCtx

                & { Import-DotEnv -Unload }

                if ($null -eq $initialVarValueForUnloadCtx) {
                    (Test-Path "Env:\$varNameForUnloadCtx") | Should -Be $false
                } else {
                    [Environment]::GetEnvironmentVariable($varNameForUnloadCtx) | Should -Be $initialVarValueForUnloadCtx
                }
                ($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousEnvFiles').Count) | Should -Be 0
                $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousWorkingDirectory') | Should -Be 'STATE_AFTER_EXPLICIT_UNLOAD'

                if (Test-Path $tempDirForUnloadCtx) { Remove-Item $tempDirForUnloadCtx -Recurse -Force }
            }
        }
    }
}
