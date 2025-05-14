# c:\Users\dani_\Workspaces\ImportDotEnv\Tests\ImportDotEnv.Tests.ps1

#Requires -Modules Pester
param(
    [string]$ModulePath = (Resolve-Path (Join-Path $PSScriptRoot "..\ImportDotEnv.psm1")).Path # Assuming tests are in a subfolder
)

# Enable debug messages for this test run
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

    Describe "Import-DotEnv Core and Integration Tests" {
        BeforeAll { # Runs once before any test in this Describe block
            $script:ImportDotEnvModule = Get-Module ImportDotEnv # Store it in script scope
            Write-Debug "BeforeAll: Import-Module executed."
            if (-not $script:ImportDotEnvModule) {
                throw "BeforeAll: ImportDotEnv module object could not be retrieved after Import-Module."
            }
            Write-Debug "BeforeAll: ImportDotEnv module IS loaded."

            # Store initial state of any test-related environment variables
            $testVarNames = @("TEST_VAR_GLOBAL", "TEST_VAR_A", "TEST_VAR_BASE", "TEST_VAR_OVERRIDE", "TEST_VAR_SUB", "NEW_VAR", "TEST_EMPTY_VAR", "PROJECT_ID", "MANUAL_TEST_VAR")
            foreach ($varName in $testVarNames) {
                $Global:InitialEnvironment[$varName] = [Environment]::GetEnvironmentVariable($varName)
            }

            # Create temporary directory structure for tests
            $script:TestRoot = Join-Path $env:TEMP "ImportDotEnvPesterTests"
            if (Test-Path $script:TestRoot) {
                Write-Debug "BeforeAll: Removing existing TestRoot '$script:TestRoot'"
                Remove-Item $script:TestRoot -Recurse -Force
            }
            New-Item -Path $script:TestRoot -ItemType Directory | Out-Null

            # --- New: Create a parent directory with a .env file for cross-directory restoration test ---
            $script:ParentDirOfTestRoot = Split-Path $script:TestRoot -Parent # e.g., C:\Users\dani_\AppData\Local\Temp
            $script:ParentEnvPath = Join-Path $script:ParentDirOfTestRoot ".env" # e.g., C:\Users\dani_\AppData\Local\Temp\.env

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

        BeforeEach { # Runs before each It in this Describe block
            # Variables that are truly global/external and whose pre-Pester state should be restored by BeforeEach
            $globalTestVarNames = @("TEST_VAR_GLOBAL", "TEST_VAR_BASE", "TEST_VAR_OVERRIDE", "TEST_EMPTY_VAR", "PROJECT_ID", "MANUAL_TEST_VAR")
            # Variables that are primarily created/manipulated by test scenarios and should always be cleared
            $scenarioSpecificVarNames = @("TEST_VAR_A", "TEST_VAR_SUB", "NEW_VAR")

            foreach ($varName in $globalTestVarNames) {
                $initialVal = $Global:InitialEnvironment[$varName] # This relies on $Global:InitialEnvironment being pristine
                if ($null -eq $initialVal) {
                    if (Test-Path "Env:\$varName") { Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue }
                    [Environment]::SetEnvironmentVariable($varName, $null)
                } else {
                    [Environment]::SetEnvironmentVariable($varName, $initialVal)
                }
            }

            foreach ($varName in $scenarioSpecificVarNames) {
                Write-Debug "BeforeEach: Unconditionally clearing scenario-specific var '$varName'. Initial Test-Path: $(Test-Path \"Env:\\$varName\"), Initial Value: '$([Environment]::GetEnvironmentVariable($varName))'"
                # Attempt to clear the variable from the process environment first.
                [Environment]::SetEnvironmentVariable($varName, $null)
                # Then, ensure it's also cleared from PowerShell's Env: drive if it lingers.
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
            # Since we are InModuleScope, we can directly set the script-scoped variables
            $script:trueOriginalEnvironmentVariables = @{}
            $script:previousEnvFiles = @()
            $script:previousWorkingDirectory = "RESET_BY_BEFORE_EACH_TEST_HOOK" # Match initial state or a known reset state

            $currentTrueOriginals = $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('trueOriginalEnvironmentVariables')
            Write-Debug "BeforeEach (Describe): After reset, trueOriginalEnvironmentVariables count: $($currentTrueOriginals.Count). Keys: $($currentTrueOriginals.Keys -join ', ')"
            if ($script:TestRoot -and (Test-Path $script:TestRoot)) {
                 Microsoft.PowerShell.Management\Set-Location $script:TestRoot
                 Write-Debug "Describe-level BeforeEach: PWD reset to $($PWD.Path)"
            }
            # $script:ImportDotEnvModule.SessionState.PSVariable.Set('previousWorkingDirectory', "RESET_BY_BEFORE_EACH_TEST_HOOK") # Done above

            Write-Debug "BeforeEach: Module state reset. TrueOriginalEnvironmentVariables count: $($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('trueOriginalEnvironmentVariables').Count)"
            Write-Debug "BeforeEach: Module state reset. PreviousEnvFiles count: $($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousEnvFiles').Count)"
            Write-Debug "BeforeEach: Module state reset. PreviousWorkingDirectory: $($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousWorkingDirectory'))"
        }

        AfterAll { # Runs once after all tests in this Describe block
            if ($script:TestRoot -and $PWD.Path.StartsWith($script:TestRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $parentOfTestRoot = Split-Path $script:TestRoot -Parent
                Write-Debug "AfterAll: Current PWD '$($PWD.Path)' is inside TestRoot. Changing location to '$parentOfTestRoot'."
                Microsoft.PowerShell.Management\Set-Location $parentOfTestRoot # Use original SL
            }
            # Only restore environment variables; do not manually remove any test files or directories. Pester will handle cleanup.
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

        # Helper function for mocking Get-EnvFilesUpstream
        $script:GetEnvFilesUpstreamMock = {
            param([string]$Directory)
            $resolvedDir = Convert-Path $Directory
            #Write-Host "MOCK Get-EnvFilesUpstream called for dir: $resolvedDir (TestRoot: $($script:TestRoot), ParentEnvPath: $($script:ParentEnvPath))" -ForegroundColor Magenta

            if ($resolvedDir -eq $script:DirA.FullName) { return @(Join-Path $script:DirA.FullName ".env") }
            if ($resolvedDir -eq $script:DirB.FullName) { return @(Join-Path $script:DirB.FullName ".env") }
            if ($resolvedDir -eq $script:DirC.FullName) { return @(Join-Path $script:DirC.FullName ".env") }
            if ($resolvedDir -eq $script:SubDir.FullName) { return @( (Join-Path $script:BaseDir.FullName ".env"), (Join-Path $script:SubDir.FullName ".env") ) } # Hierarchical
            if ($resolvedDir -eq $script:BaseDir.FullName) { return @(Join-Path $script:BaseDir.FullName ".env") }
            if ($resolvedDir -eq $script:Project1Dir.FullName) { return @(Join-Path $script:Project1Dir.FullName ".env") }
            if ($resolvedDir -eq $script:Project2Dir.FullName) { return @(Join-Path $script:Project2Dir.FullName ".env") }
            if ($resolvedDir -eq $script:NonEnvDir.FullName) { return @() }

            if ($resolvedDir -eq $script:TestRoot) {
                $filesToReturn = @()
                # The real Get-EnvFilesUpstream collects current-to-root, then reverses.
                # So, parent .env (if exists) comes before current's .env (if exists) in the final list.
                if (Test-Path $script:ParentEnvPath) { # This is C:\Users\dani_\AppData\Local\Temp\.env
                    $filesToReturn += $script:ParentEnvPath
                }
                $testRootOwnEnv = Join-Path $script:TestRoot ".env" # e.g., for the manual test
                if (Test-Path $testRootOwnEnv) {
                    $filesToReturn += $testRootOwnEnv
                }
                #Write-Host "MOCK Get-EnvFilesUpstream for TestRoot returning: $($filesToReturn -join ', ')" -ForegroundColor Magenta
                return $filesToReturn
            }
            if ($resolvedDir -eq $script:ParentDirOfTestRoot) { # e.g. C:\Users\dani_\AppData\Local\Temp
                # This directory, in the context of our tests, primarily has $script:ParentEnvPath
                if (Test-Path $script:ParentEnvPath) {
                    #Write-Host "MOCK Get-EnvFilesUpstream for ParentDirOfTestRoot returning: $($script:ParentEnvPath)" -ForegroundColor Magenta
                    return @($script:ParentEnvPath)
                }
                #Write-Host "MOCK Get-EnvFilesUpstream for ParentDirOfTestRoot returning empty (no ParentEnvPath)" -ForegroundColor Magenta
                return @()
            }
            # For other non-test specific dirs, return empty
            #Write-Host "MOCK Get-EnvFilesUpstream for '$resolvedDir' returning empty (default case)" -ForegroundColor Magenta
            return @()
        }

        Context "Helper Function Tests" {


            It "Format-EnvFilePath should handle empty core path" {
                Mock Get-RelativePath { return ".env" } -ModuleName ImportDotEnv
                $result = Format-EnvFilePath -Path ".env" -BasePath "."
                $result | Should -Be ".env" # No bolding expected
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
                $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousEnvFiles').Count | Should -Be 0
            }
        }

        Context "Core Import-DotEnv Functionality (Manual Invocation)" {
            It "loads variables when Import-DotEnv is called directly and restores on subsequent call for parent" {
                $initialManualTestVar = [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR") # Capture initial state
                $manualEnvFile = Join-Path $script:TestRoot ".env"
                Set-Content -Path $manualEnvFile -Value "MANUAL_TEST_VAR=loaded_manual"
                $ErrorActionPreferenceBackup = $ErrorActionPreference
                $ErrorActionPreference = 'Stop' # Make sure errors in the try block are caught
                $Error.Clear()
                try {
                    Push-Location $script:TestRoot
                    Write-Debug "Test 'loads variables...': PWD after Push-Location: $($PWD.Path)"
                    Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv

                    Write-Debug "Test 'loads variables...': Calling Import-DotEnv for first load. Initial MANUAL_TEST_VAR: '$initialManualTestVar'"
                    Import-DotEnv -Path "." # Load .env from $script:TestRoot
                    $currentManualTestVarValue = [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR")
                    Write-Debug "Test 'loads variables...': MANUAL_TEST_VAR after first load: '$currentManualTestVarValue'"
                    [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR") | Should -Be "loaded_manual"
                    Write-Debug "Test 'loads variables...': Assertion 1 passed."
                    Write-Debug "Test 'loads variables...': Module's trueOriginals for MANUAL_TEST_VAR: '$($script:trueOriginalEnvironmentVariables['MANUAL_TEST_VAR'])'"

                    # Simulate moving out by calling Import-DotEnv for the parent
                    Write-Debug "Test 'loads variables...': Calling Import-DotEnv for parent restore. PWD: $($PWD.Path)"
                    Import-DotEnv -Path $script:ParentDirOfTestRoot
                    $restoredManualTestVarValue = [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR")
                    Write-Debug "Test 'loads variables...': MANUAL_TEST_VAR after parent restore call: '$restoredManualTestVarValue'"

                    # Check if MANUAL_TEST_VAR was restored to its original value or unset if it didn't exist
                    if ($null -eq $initialManualTestVar) {
                        (Test-Path Env:\MANUAL_TEST_VAR) | Should -Be $false
                        ([Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR")) | Should -BeNullOrEmpty "because initial was null"
                    } else {
                        [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR") | Should -Be $initialManualTestVar
                    }
                    Write-Debug "Test 'loads variables...': Assertion 2 passed."
                    Pop-Location
                    Write-Debug "Test 'loads variables...': Pop-Location successful."
                }
                catch {
                    Write-Error "Test 'loads variables...' FAILED with exception: $($_.ToString())"
                    Write-Error "Exception StackTrace: $($_.ScriptStackTrace)"
                    # Ensure Pester sees a failure
                    throw "Test 'loads variables...' failed explicitly due to caught error."
                }
                finally {
                    $ErrorActionPreference = $ErrorActionPreferenceBackup
                    if (Test-Path $manualEnvFile) { Remove-Item $manualEnvFile -Force -ErrorAction SilentlyContinue }
                    # Restore MANUAL_TEST_VAR to its absolute initial state
                    if ($null -eq $initialManualTestVar) { [Environment]::SetEnvironmentVariable("MANUAL_TEST_VAR", $null) } else { [Environment]::SetEnvironmentVariable("MANUAL_TEST_VAR", $initialManualTestVar) }
                }
            }
        }

        Context "Set-Location Integration (Enable/Disable Functionality)" {
            AfterEach {
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue
            }

            It "should have Set-Location, cd, and sl in their default states after module import (or after disable)" {
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue

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
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv # Mock for the auto-load on enable
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
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv # Mock for the auto-load on enable
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

                Microsoft.PowerShell.Management\Set-Location $script:DirB.FullName # Go to DirB before enabling
                Enable-ImportDotEnvCdIntegration # This will load DirB's .env

                [Environment]::GetEnvironmentVariable($newVarName) | Should -Be "new_value_from_env"
                [Environment]::GetEnvironmentVariable($existingVarName) | Should -Be "overwritten_by_env"

                Disable-ImportDotEnvCdIntegration

                (Test-Path "Env:\$newVarName") | Should -Be $true
                [Environment]::GetEnvironmentVariable($newVarName) | Should -Be "new_value_from_env"
                [Environment]::GetEnvironmentVariable($existingVarName) | Should -Be "overwritten_by_env"

                if ($null -ne $originalDirBEnvContent) { Set-Content -Path $dirBEnvPath -Value $originalDirBEnvContent -Force } else { Remove-Item $dirBEnvPath -Force -ErrorAction SilentlyContinue }
                # Clean up test vars
                [Environment]::SetEnvironmentVariable($newVarName, $null)
                [Environment]::SetEnvironmentVariable($existingVarName, $initialExistingValue) # Restore to its specific initial for this test
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

                Set-Location $script:TestRoot # Changed from Split-Path to $script:TestRoot for consistency with mock

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
        }

        Context "Set-Location Integration - Variable Loading Scenarios" {
            BeforeEach {
                # CRITICAL FIX: Ensure trueOriginalEnvironmentVariables is reset before this context's Enable-ImportDotEnvCdIntegration
                # This prevents state leakage from previous tests that also called Enable-ImportDotEnvCdIntegration.
                # Since we are InModuleScope, we can directly set the script-scoped variables
                $script:trueOriginalEnvironmentVariables = @{}
                # $script:ImportDotEnvModule.SessionState.PSVariable.Set('trueOriginalEnvironmentVariables', @{}) # Old way
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
                $initialTestVarA = $Global:InitialEnvironment["TEST_VAR_A"] # Get the true initial value

                # Ensure TEST_VAR_A is in its initial state (null or original value)
                if ($null -eq $initialTestVarA) {
                    [Environment]::SetEnvironmentVariable("TEST_VAR_A", $null)
                    if(Test-Path Env:\TEST_VAR_A) { Remove-Item Env:\TEST_VAR_A -Force }
                } else {
                    [Environment]::SetEnvironmentVariable("TEST_VAR_A", $initialTestVarA)
                }

                Set-Location $script:DirA.FullName
                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be "valA"

                Set-Location $script:TestRoot # Go to TestRoot, which might have its own or parent .env via mock

                $actualValue = [Environment]::GetEnvironmentVariable("TEST_VAR_A")
                $existsInPSDrive = Test-Path "Env:\TEST_VAR_A"
                $trueOriginalsAtAssert = $script:ImportDotEnvModule.SessionState.PSVariable.GetValue('trueOriginalEnvironmentVariables')

                # Only emit essential debug info now that all tests are passing
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

                # Set to known initial states for this test
                if ($null -ne $initialTestVarBase) { [Environment]::SetEnvironmentVariable("TEST_VAR_BASE", $initialTestVarBase) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_BASE", $null); if(Test-Path Env:\TEST_VAR_BASE){Remove-Item Env:\TEST_VAR_BASE -Force} }
                if ($null -ne $initialTestVarOverride) { [Environment]::SetEnvironmentVariable("TEST_VAR_OVERRIDE", $initialTestVarOverride) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_OVERRIDE", $null); if(Test-Path Env:\TEST_VAR_OVERRIDE){Remove-Item Env:\TEST_VAR_OVERRIDE -Force} }
                if ($null -ne $initialTestVarSub) { [Environment]::SetEnvironmentVariable("TEST_VAR_SUB", $initialTestVarSub) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_SUB", $null); if(Test-Path Env:\TEST_VAR_SUB){Remove-Item Env:\TEST_VAR_SUB -Force} }


                Set-Location $script:SubDir.FullName
                [Environment]::GetEnvironmentVariable("TEST_VAR_BASE") | Should -Be "base_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_SUB") | Should -Be "sub_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "sub_override_val"

                Set-Location $script:BaseDir.FullName
                if ($null -eq $initialTestVarSub) { (Test-Path "Env:\TEST_VAR_SUB") | Should -Be $false } else { [Environment]::GetEnvironmentVariable("TEST_VAR_SUB") | Should -Be $initialTestVarSub }
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "base_override_val" # Restored from sub, set by base

                Set-Location $script:TestRoot # Go to TestRoot
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
                $initialEmptyVar = "initial_empty_test_val_specific" # Use a specific initial value for this test
                [Environment]::SetEnvironmentVariable("TEST_EMPTY_VAR", $initialEmptyVar)

                Set-Location $script:DirC.FullName

                # When .env has VAR=, the value is an empty string. GetEnvironmentVariable should return "".
                [Environment]::GetEnvironmentVariable("TEST_EMPTY_VAR") | Should -Be ""

                Set-Location $script:TestRoot
                [Environment]::GetEnvironmentVariable("TEST_EMPTY_VAR") | Should -Be $initialEmptyVar
            }

            It "correctly unloads project1 vars and loads project2 vars, then restores global" {
                $initialProjectId = "global_project_id_specific" # Specific initial
                [Environment]::SetEnvironmentVariable("PROJECT_ID", $initialProjectId)

                Set-Location $script:Project1Dir.FullName
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be "P1"

                Set-Location $script:Project2Dir.FullName
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be "P2"

                Set-Location $script:TestRoot
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be $initialProjectId
            }

            It "should not alter existing environment variables when moving to a dir with no .env" {
                $initialGlobalVar = "no_env_test_initial_specific" # Specific initial
                [Environment]::SetEnvironmentVariable("TEST_VAR_GLOBAL", $initialGlobalVar)

                Set-Location $script:NonEnvDir.FullName
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $initialGlobalVar

                Set-Location $script:TestRoot
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $initialGlobalVar
            }

            # Moved test
            It "loads variables from .env files in the correct order when using Set-Location" {
                 # This test relies on the BeforeEach to set up integration and mock.
                 # Initial state of these vars will be from $Global:InitialEnvironment or null if not present there.
                $initialTestVarBase = $Global:InitialEnvironment["TEST_VAR_BASE"]
                $initialTestVarSub = $Global:InitialEnvironment["TEST_VAR_SUB"]
                $initialTestVarOverride = $Global:InitialEnvironment["TEST_VAR_OVERRIDE"]

                # Ensure a clean start for these specific vars based on their true initial state
                if ($null -ne $initialTestVarBase) { [Environment]::SetEnvironmentVariable("TEST_VAR_BASE", $initialTestVarBase) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_BASE", $null); if(Test-Path Env:\TEST_VAR_BASE){Remove-Item Env:\TEST_VAR_BASE -Force} }
                if ($null -ne $initialTestVarSub) { [Environment]::SetEnvironmentVariable("TEST_VAR_SUB", $initialTestVarSub) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_SUB", $null); if(Test-Path Env:\TEST_VAR_SUB){Remove-Item Env:\TEST_VAR_SUB -Force} }
                if ($null -ne $initialTestVarOverride) { [Environment]::SetEnvironmentVariable("TEST_VAR_OVERRIDE", $initialTestVarOverride) } else { [Environment]::SetEnvironmentVariable("TEST_VAR_OVERRIDE", $null); if(Test-Path Env:\TEST_VAR_OVERRIDE){Remove-Item Env:\TEST_VAR_OVERRIDE -Force} }

                Set-Location $script:SubDir.FullName
                [Environment]::GetEnvironmentVariable("TEST_VAR_BASE") | Should -Be "base_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_SUB") | Should -Be "sub_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "sub_override_val" # From subDir, overrides baseDir
            }
        }

        Describe 'Import-DotEnv -List switch' {
            BeforeAll {
                function Invoke-ImportDotEnvListAndCaptureOutput {
                    param(
                        [switch]$MockPSVersion5
                    )
                    # Create temp dir and .env file in $TestDrive
                    $tempDir = Join-Path $TestDrive (New-Guid)
                    New-Item -ItemType Directory -Path $tempDir | Out-Null
                    $tempDir2 = Join-Path $tempDir "tempDir2"
                    New-Item -ItemType Directory -Path $tempDir2 | Out-Null

                    $envFile = Join-Path $tempDir '.env'
                    Set-Content -Path $envFile -Value @(
                        'FOO=bar',
                        'BAZ=qux'
                    )

                    $envFile2 = Join-Path $tempDir2 '.env'
                    Set-Content -Path $envFile2 -Value @(
                        'FOO=override',
                        'GEZ=whatever'
                    )
                    if ($MockPSVersion5) {
                        $script:PSVersionTable = @{ PSVersion = [version]'5.1.0.0' }
                    }
                    Import-DotEnv -Path $tempDir2
                    $output = & { Import-DotEnv -List } *>&1
                    $outputString = $output | Out-String
                    $outputString | Should -Match 'FOO'
                    $outputString | Should -Match 'BAZ'
                    $outputString | Should -Match 'GEZ'
                    $outputString | Should -Match '\.env'
                }
            }
            It 'lists active variables and their defining files when state is active (PowerShell 7+)' -Tag "ListSwitch" {
                Invoke-ImportDotEnvListAndCaptureOutput

            }

            It 'lists active variables in table format when PSVersion is 5 (Windows PowerShell)' -Tag "ListSwitch" {
                Invoke-ImportDotEnvListAndCaptureOutput -MockPSVersion5
            }
        }
        It 'Import-DotEnv -List switch should report back correctly when no .env files are active' -Tag "focus" {
            $output = & { Import-DotEnv -List } *>&1
            $outputString = $output | Out-String
            Write-Debug "Output: $outputString"
            $outputString | Should -Match 'No .env configuration is currently active or managed by ImportDotEnv.'
        }

        Describe 'Import-DotEnv -Unload switch' -Tag 'UnloadSwitch' {
            It 'unloads variables and resets state after a load (in-process)' {
                # Arrange: create a temp .env file and load it
                $tempDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
                New-Item -ItemType Directory -Path $tempDir | Out-Null
                $envFile = Join-Path $tempDir '.env'
                $varName = 'UNLOAD_TEST_VAR'
                Set-Content -Path $envFile -Value "$varName=unload_me"

                InModuleScope ImportDotEnv {
                    # Mock Get-EnvFilesUpstream to return our temp .env file
                    Mock Get-EnvFilesUpstream { param($Directory) return @($envFile) } -ModuleName ImportDotEnv

                    # Load the .env file
                    Import-DotEnv -Path $tempDir
                    [Environment]::GetEnvironmentVariable($varName) | Should -Be 'unload_me'
                    $script:previousEnvFiles | Should -BeExactly @($envFile)
                    $script:previousWorkingDirectory | Should -Be $tempDir
                }

                # Act: Unload in-process (outside InModuleScope to avoid parameter set confusion)
                & { Import-DotEnv -Unload }

                # Assert: variable is unset and state is reset
                (Test-Path Env:\$varName) | Should -Be $false
                (-not $script:previousEnvFiles) | Should -Be $true
                $script:previousWorkingDirectory | Should -Be 'STATE_AFTER_EXPLICIT_UNLOAD'
            }
        } # End of Describe 'Import-DotEnv -Unload switch'
    } # End of Describe "Import-DotEnv Core and Integration Tests"
} # End of InModuleScope
