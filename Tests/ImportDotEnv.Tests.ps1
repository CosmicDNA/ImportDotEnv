# c:\Users\dani_\Workspaces\ImportDotEnv\Tests\ImportDotEnv.Tests.ps1

#Requires -Modules Pester
param(
    [string]$ModulePath = (Resolve-Path (Join-Path $PSScriptRoot "..\ImportDotEnv.psm1")).Path # Assuming tests are in a subfolder
)

# Enable debug messages for this test run
$DebugPreference = 'Continue'

$Global:InitialEnvironment = @{}

# Import the module before InModuleScope so Pester can find it
Write-Host "Top-level: Attempting to import module from '$ModulePath'"
if (-not (Test-Path $ModulePath)) {
    throw "Top-level: ModulePath '$ModulePath' does not exist."
}
$null = Import-Module $ModulePath -Force -PassThru
Write-Host "Top-level: Import-Module executed."

# Wrap the entire Describe block in InModuleScope
InModuleScope 'ImportDotEnv' {

    Describe "Import-DotEnv Core and Integration Tests" {
        BeforeAll { # Runs once before any test in this Describe block
            $script:ImportDotEnvModule = Get-Module ImportDotEnv # Store it in script scope
            Write-Host "BeforeAll: Import-Module executed."
            if (-not $script:ImportDotEnvModule) {
                throw "BeforeAll: ImportDotEnv module object could not be retrieved after Import-Module."
            }
            Write-Host "BeforeAll: ImportDotEnv module IS loaded."

            # Store initial state of any test-related environment variables
            $testVarNames = @("TEST_VAR_GLOBAL", "TEST_VAR_A", "TEST_VAR_BASE", "TEST_VAR_OVERRIDE", "TEST_VAR_SUB", "NEW_VAR", "TEST_EMPTY_VAR", "PROJECT_ID")
            foreach ($varName in $testVarNames) {
                $Global:InitialEnvironment[$varName] = [Environment]::GetEnvironmentVariable($varName)
            }

            # Create temporary directory structure for tests
            $script:TestRoot = Join-Path $env:TEMP "ImportDotEnvPesterTests" # Changed name to avoid conflict with previous example
            if (Test-Path $script:TestRoot) {
                Write-Host "BeforeAll: Removing existing TestRoot '$script:TestRoot'"
                Remove-Item $script:TestRoot -Recurse -Force
            }
            New-Item -Path $script:TestRoot -ItemType Directory | Out-Null

            $script:DirA = New-Item -Path (Join-Path $script:TestRoot "dirA") -ItemType Directory
            Set-Content -Path (Join-Path $script:DirA.FullName ".env") -Value "TEST_VAR_A=valA`nTEST_VAR_GLOBAL=valA_override"
            Write-Host "BeforeAll: Content of dirA/.env is '$(Get-Content (Join-Path $script:DirA.FullName ".env") -Raw)'"

            $script:BaseDir = New-Item -Path (Join-Path $script:TestRoot "baseDir") -ItemType Directory
            Set-Content -Path (Join-Path $script:BaseDir.FullName ".env") -Value "TEST_VAR_BASE=base_val`nTEST_VAR_OVERRIDE=base_override_val"
            Write-Host "BeforeAll: Content of baseDir/.env is '$(Get-Content (Join-Path $script:BaseDir.FullName ".env") -Raw)'"

            $script:SubDir = New-Item -Path (Join-Path $script:BaseDir.FullName "subDir") -ItemType Directory
            Set-Content -Path (Join-Path $script:SubDir.FullName ".env") -Value "TEST_VAR_SUB=sub_val`nTEST_VAR_OVERRIDE=sub_override_val"
            Write-Host "BeforeAll: Content of subDir/.env is '$(Get-Content (Join-Path $script:SubDir.FullName ".env") -Raw)'"

            $script:DirB = New-Item -Path (Join-Path $script:TestRoot "dirB") -ItemType Directory
            Set-Content -Path (Join-Path $script:DirB.FullName ".env") -Value "NEW_VAR=new_value"
            Write-Host "BeforeAll: Content of dirB/.env is '$(Get-Content (Join-Path $script:DirB.FullName ".env") -Raw)'"

            $script:DirC = New-Item -Path (Join-Path $script:TestRoot "dirC") -ItemType Directory
            Set-Content -Path (Join-Path $script:DirC.FullName ".env") -Value "TEST_EMPTY_VAR="
            Write-Host "BeforeAll: Content of dirC/.env is '$(Get-Content (Join-Path $script:DirC.FullName ".env") -Raw)'"

            $script:Project1Dir = New-Item -Path (Join-Path $script:TestRoot "project1") -ItemType Directory
            Set-Content -Path (Join-Path $script:Project1Dir.FullName ".env") -Value "PROJECT_ID=P1"
            Write-Host "BeforeAll: Content of project1/.env is '$(Get-Content (Join-Path $script:Project1Dir.FullName ".env") -Raw)'"

            $script:Project2Dir = New-Item -Path (Join-Path $script:TestRoot "project2") -ItemType Directory
            Set-Content -Path (Join-Path $script:Project2Dir.FullName ".env") -Value "PROJECT_ID=P2"
            Write-Host "BeforeAll: Content of project2/.env is '$(Get-Content (Join-Path $script:Project2Dir.FullName ".env") -Raw)'"

            $script:NonEnvDir = New-Item -Path (Join-Path $script:TestRoot "nonEnvDir") -ItemType Directory
        }

        BeforeEach { # Runs before each It in this Describe block
            # Variables that are truly global/external and whose pre-Pester state should be restored by BeforeEach
            $globalTestVarNames = @("TEST_VAR_GLOBAL", "TEST_VAR_BASE", "TEST_VAR_OVERRIDE", "TEST_EMPTY_VAR", "PROJECT_ID")
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
                Write-Host "BeforeEach: Unconditionally clearing scenario-specific var '$varName'. Initial Test-Path: $(Test-Path "Env:\$varName"), Initial Value: '$([Environment]::GetEnvironmentVariable($varName))'"
                # Attempt to clear the variable from the process environment first.
                [Environment]::SetEnvironmentVariable($varName, $null)
                # Then, ensure it's also cleared from PowerShell's Env: drive if it lingers.
                if (Test-Path "Env:\$varName") { Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue }

                if ([Environment]::GetEnvironmentVariable($varName) -ne $null) {
                    Write-Warning "BeforeEach: FAILED to clear '$varName'. It is still '$([Environment]::GetEnvironmentVariable($varName))'."
                } else {
                    Write-Host "BeforeEach: Successfully cleared '$varName'. Current Value: '$([Environment]::GetEnvironmentVariable($varName))', Test-Path: $(Test-Path "Env:\$varName")"
                }
            }

            # Consolidate all var names for the initial message if needed, or remove this loop if covered above.
            $testVarNames = $globalTestVarNames + $scenarioSpecificVarNames
            foreach ($varName in $testVarNames) {
                $initialVal = $Global:InitialEnvironment[$varName]
                if ($null -eq $initialVal) {
                    # This part is now handled by the loops above.
                    # We could add a final check here if desired.
                    # Write-Host "BeforeEach: Post-cleanup check for '$varName': Value: '$([Environment]::GetEnvironmentVariable($varName))', Test-Path: $(Test-Path "Env:\$varName")"
                }
            }
            Write-Host "BeforeEach (Start): Environment variables reset."
            # Ensure TestRoot is accessible. It should be inherited from BeforeAll's $script: scope.
            $currentTestRoot = $script:TestRoot
            Write-Host "BeforeEach: Value of currentTestRoot (from script:TestRoot) is '$currentTestRoot'"
            if (-not $currentTestRoot) { throw "BeforeEach: currentTestRoot (from script:TestRoot) is not set!" }

            # Reset module's internal state by cd'ing to a neutral location and triggering ImportDotEnv
            # This ensures the module's $script:previousEnvFiles, $script:originalEnvironmentVariables,
            # and $script:previousWorkingDirectory are reset to a known clean state.
            if (-not $script:ImportDotEnvModule) {
                throw "BeforeEach: script:ImportDotEnvModule is not available for state reset!"
            }
            Write-Host "BeforeEach: Directly resetting ImportDotEnv module's internal script variables."
            $script:ImportDotEnvModule.SessionState.PSVariable.Set('originalEnvironmentVariables', @{})
            $script:ImportDotEnvModule.SessionState.PSVariable.Set('previousEnvFiles', @())
            # Set previousWorkingDirectory to a value that won't match any realistic path,
            # ensuring Import-DotEnv will re-evaluate on its next actual invocation within a test.
            # This distinct marker string helps confirm it's being reset.
            # Ensure PWD is a known neutral state before each test (especially before Context's BeforeEach might run Enable-ImportDotEnvCdIntegration)
            if ($script:TestRoot -and (Test-Path $script:TestRoot)) { # Check if TestRoot is initialized and exists
                 Microsoft.PowerShell.Management\Set-Location $script:TestRoot # Use original SL to avoid module logic here
                 Write-Host "Describe-level BeforeEach: PWD reset to $($PWD.Path)"
            }
            # This distinct marker string helps confirm it's being reset.
            $script:ImportDotEnvModule.SessionState.PSVariable.Set('previousWorkingDirectory', "RESET_BY_BEFORE_EACH_TEST_HOOK")

            Write-Host "BeforeEach: Module state reset. OriginalEnvironmentVariables count: $($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('originalEnvironmentVariables').Count)"
            Write-Host "BeforeEach: Module state reset. PreviousEnvFiles count: $($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousEnvFiles').Count)"
            Write-Host "BeforeEach: Module state reset. PreviousWorkingDirectory: $($script:ImportDotEnvModule.SessionState.PSVariable.GetValue('previousWorkingDirectory'))"
        }

        AfterAll { # Runs once after all tests in this Describe block
            # Ensure we are not inside the TestRoot directory before trying to remove it
            if ($script:TestRoot -and $PWD.Path.StartsWith($script:TestRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $parentOfTestRoot = Split-Path $script:TestRoot -Parent
                Write-Host "AfterAll: Current PWD '$($PWD.Path)' is inside TestRoot. Changing location to '$parentOfTestRoot'."
                Set-Location $parentOfTestRoot
            }
            if (Test-Path $script:TestRoot) {
                Remove-Item $script:TestRoot -Recurse -Force
            }
            # Restore initial environment
            Write-Host "AfterAll: Restoring initial environment variables."
            foreach ($varName in $Global:InitialEnvironment.Keys) {
                $initialVal = $Global:InitialEnvironment[$varName]
                if ($null -eq $initialVal) {
                    # If the original value was null (non-existent), remove the environment variable
                    if (Test-Path "Env:\$varName") {
                        Write-Host "AfterAll: Removing environment variable '$varName' as its initial state was null."
                        Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Write-Host "AfterAll: Restoring environment variable '$varName' to '$initialVal'."
                    [Environment]::SetEnvironmentVariable($varName, $initialVal)
                }
            }
            # Ensure cd integration is disabled after all tests in this describe block
            if (Get-Command Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue) {
                Write-Host "AfterAll: Calling Disable-ImportDotEnvCdIntegration." -ForegroundColor Cyan
                Disable-ImportDotEnvCdIntegration
                Write-Host "AfterAll: Disable-ImportDotEnvCdIntegration finished." -ForegroundColor Cyan
                $cdCmdAfterDisable = Get-Command cd -ErrorAction SilentlyContinue
                Write-Host "AfterAll: State of 'cd' after Disable-ImportDotEnvCdIntegration: Name: $($cdCmdAfterDisable.Name), Type: $($cdCmdAfterDisable.CommandType), Definition: $($cdCmdAfterDisable.Definition)" -ForegroundColor Cyan
                if ($cdCmdAfterDisable.CommandType -ne [System.Management.Automation.CommandTypes]::Alias) {
                    Write-Warning "AfterAll: 'cd' IS NOT an alias after Disable-ImportDotEnvCdIntegration. This is unexpected."
                } else {
                    Write-Host "AfterAll: 'cd' IS an alias as expected." -ForegroundColor Green
                }
            } else {
                Write-Warning "AfterAll: Disable-ImportDotEnvCdIntegration command not found. Skipping disable."
            }
            Write-Host "AfterAll: Calling Remove-Module ImportDotEnv -Force." -ForegroundColor Cyan
            Remove-Module ImportDotEnv -Force -ErrorAction SilentlyContinue # Add SilentlyContinue for robustness in cleanup
            Write-Host "AfterAll: Remove-Module ImportDotEnv -Force finished." -ForegroundColor Cyan
            $cdCmdAfterRemoveModule = Get-Command cd -ErrorAction SilentlyContinue
            Write-Host "AfterAll: State of 'cd' after Remove-Module: Name: $($cdCmdAfterRemoveModule.Name), Type: $($cdCmdAfterRemoveModule.CommandType), Definition: $($cdCmdAfterRemoveModule.Definition)" -ForegroundColor Cyan
        }

        # Helper function for mocking Get-EnvFilesUpstream
        $script:MockedEnvFiles = @{}
        $script:GetEnvFilesUpstreamMock = {
            param([string]$Directory)
            $resolvedDir = Convert-Path $Directory
            #Write-Host "MOCK Get-EnvFilesUpstream called for dir: $resolvedDir"
            # Return files based on the specific directory structure of the tests
            if ($resolvedDir -eq $script:DirA.FullName) { return @(Join-Path $script:DirA.FullName ".env") }
            if ($resolvedDir -eq $script:DirB.FullName) { return @(Join-Path $script:DirB.FullName ".env") }
            if ($resolvedDir -eq $script:DirC.FullName) { return @(Join-Path $script:DirC.FullName ".env") }
            if ($resolvedDir -eq $script:SubDir.FullName) { return @( (Join-Path $script:BaseDir.FullName ".env"), (Join-Path $script:SubDir.FullName ".env") ) } # Hierarchical
            if ($resolvedDir -eq $script:BaseDir.FullName) { return @(Join-Path $script:BaseDir.FullName ".env") }
            if ($resolvedDir -eq $script:Project1Dir.FullName) { return @(Join-Path $script:Project1Dir.FullName ".env") }
            if ($resolvedDir -eq $script:Project2Dir.FullName) { return @(Join-Path $script:Project2Dir.FullName ".env") }
            if ($resolvedDir -eq $script:NonEnvDir.FullName) { return @() }
            if ($resolvedDir -eq $script:TestRoot) {
                # For the manual invocation test
                if (Test-Path (Join-Path $script:TestRoot ".env")) { return @(Join-Path $script:TestRoot ".env") }
                return @()
            }
            # For parent directories or other non-test specific dirs, return empty
            return @()
        }

        Context "Core Import-DotEnv Functionality (Manual Invocation)" {
            It "loads variables when Import-DotEnv is called directly and restores on subsequent call for parent" {
                [Environment]::SetEnvironmentVariable("MANUAL_TEST_VAR", "initial_manual")
                $manualEnvFile = Join-Path $script:TestRoot ".env" # Changed from "manual.env"
                Set-Content -Path $manualEnvFile -Value "MANUAL_TEST_VAR=loaded_manual"
                try {
                    Push-Location $script:TestRoot
                    # Mock Get-EnvFilesUpstream for this specific call if it's not covered by a broader mock context
                    Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
                    Import-DotEnv -Path "."
                    # Pester automatically cleans mocks from 'It' scope at the end of 'It'

                    [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR") | Should -Be "loaded_manual"

                    # Simulate moving out by calling Import-DotEnv for the parent (or a neutral dir)
                    # This requires Import-DotEnv to correctly identify the change in context.
                    # The module's state ($script:previousEnvFiles, $script:previousWorkingDirectory) is key.
                    # To properly test restoration, we need to ensure the module's state is as if we "left" $script:TestRoot
                    # A direct call to Import-DotEnv with a different path should trigger this.
                    $parentOfTestRoot = Split-Path $script:TestRoot -Parent
                    Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv # Ensure mock is active for this call too
                    Import-DotEnv -Path $parentOfTestRoot
                    # Pester automatically cleans mocks from 'It' scope at the end of 'It'

                    [Environment]::GetEnvironmentVariable("MANUAL_TEST_VAR") | Should -Be "initial_manual"
                    Pop-Location
                }
                finally {
                    if (Test-Path $manualEnvFile) { Remove-Item $manualEnvFile -Force -ErrorAction SilentlyContinue }
                }
            }
        }

        Context "Set-Location Integration (Enable/Disable Functionality)" {
            AfterEach {
                # Ensure integration is disabled after each test in this context
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue
                # Mocks defined within 'It' blocks are automatically cleaned up by Pester.
            }

            It "should have Set-Location, cd, and sl in their default states after module import (or after disable)" {
                # Ensure a clean state for this specific test, in case of prior partial runs
                # The AfterEach of this context also calls Disable-ImportDotEnvCdIntegration,
                # so this test effectively checks the state *after* a disable, which should be the default.
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue

                # Check Set-Location
                $cmd = Get-Command Set-Location -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.ModuleName | Should -Be "Microsoft.PowerShell.Management"

                # Check cd
                $cmd = Get-Command cd -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Set-Location"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.ResolvedCommand.ModuleName | Should -Be "Microsoft.PowerShell.Management"

                # Check sl
                $cmd = Get-Command sl -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Set-Location"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.ResolvedCommand.ModuleName | Should -Be "Microsoft.PowerShell.Management"
            }

            It "Enable-ImportDotEnvCdIntegration should correctly modify Set-Location, and cd/sl should follow" {
                # The AfterEach from the previous test ensures Disable-ImportDotEnvCdIntegration has run.
                # So, we are starting from a "disabled" (default-like) state.

                Enable-ImportDotEnvCdIntegration # This function is called from within InModuleScope 'ImportDotEnv'

                # Check Set-Location
                $cmd = Get-Command Set-Location -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNull
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "ImportDotEnv\Invoke-ImportDotEnvSetLocationWrapper"
                $cmd.ResolvedCommand.Name | Should -Be "Invoke-ImportDotEnvSetLocationWrapper"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Function)
                $cmd.ResolvedCommand.ModuleName | Should -Be "ImportDotEnv"

                # Check cd
                # 'cd' should now be an alias to our wrapper function.
                $cmd = Get-Command cd -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNull
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location" # cd's definition string remains "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Invoke-ImportDotEnvSetLocationWrapper"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Function)
                $cmd.ResolvedCommand.ModuleName | Should -Be "ImportDotEnv" # Verify it resolves to our module's function
                $cmd.Name | Should -Be "cd" # Ensure we got 'cd'

                # Check sl
                $cmd = Get-Command sl -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNull
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location" # sl's definition string remains "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Invoke-ImportDotEnvSetLocationWrapper"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Function)
                $cmd.ResolvedCommand.ModuleName | Should -Be "ImportDotEnv" # Verify it resolves to our module's function
                $cmd.Name | Should -Be "sl"
            }

            It "Disable-ImportDotEnvCdIntegration should correctly restore Set-Location, and cd/sl should follow" {
                Enable-ImportDotEnvCdIntegration # Enable it first
                Disable-ImportDotEnvCdIntegration # Then disable

                # Check Set-Location
                $cmd = Get-Command Set-Location -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.Name | Should -Be "Set-Location"
                $cmd.ModuleName | Should -Be "Microsoft.PowerShell.Management"

                # Check cd
                $cmd = Get-Command cd -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Set-Location"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.ResolvedCommand.ModuleName | Should -Be "Microsoft.PowerShell.Management"

                # Check sl
                $cmd = Get-Command sl -ErrorAction SilentlyContinue
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "Set-Location"
                $cmd.ResolvedCommand.Name | Should -Be "Set-Location"
                $cmd.ResolvedCommand.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                $cmd.ResolvedCommand.ModuleName | Should -Be "Microsoft.PowerShell.Management"
            }

            It "Disable-ImportDotEnvCdIntegration removes new vars and restores overwritten vars" {
                # This test verifies that Disable-ImportDotEnvCdIntegration correctly
                # 1. Removes variables that were newly created by a .env file.
                # 2. Restores variables that existed before but were overwritten by a .env file.

                $newVarName = "NEW_VAR_FOR_DISABLE_TEST"
                $existingVarName = "EXISTING_VAR_FOR_DISABLE_TEST"
                $initialExistingValue = "initial_value_for_existing"

                # Ensure $newVarName does not exist initially
                if (Test-Path "Env:\$newVarName") { Remove-Item "Env:\$newVarName" -Force }
                (Test-Path "Env:\$newVarName") | Should -Be $false

                # Set an initial value for $existingVarName
                [Environment]::SetEnvironmentVariable($existingVarName, $initialExistingValue)
                [Environment]::GetEnvironmentVariable($existingVarName) | Should -Be $initialExistingValue

                # Use DirB for this test, temporarily modifying its .env
                $dirBEnvPath = Join-Path $script:DirB.FullName ".env"
                $originalDirBEnvContent = Get-Content $dirBEnvPath -Raw -ErrorAction SilentlyContinue
                Set-Content -Path $dirBEnvPath -Value "$newVarName=new_value_from_env`n$existingVarName=overwritten_by_env"

                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv

                Microsoft.PowerShell.Management\Set-Location $script:DirB.FullName
                Enable-ImportDotEnvCdIntegration

                # Verify .env values are loaded
                [Environment]::GetEnvironmentVariable($newVarName) | Should -Be "new_value_from_env"
                [Environment]::GetEnvironmentVariable($existingVarName) | Should -Be "overwritten_by_env"

                Disable-ImportDotEnvCdIntegration

                # Verify $newVarName is NOT removed because Disable-ImportDotEnvCdIntegration no longer unloads
                (Test-Path "Env:\$newVarName") | Should -Be $true
                [Environment]::GetEnvironmentVariable($newVarName) | Should -Be "new_value_from_env"

                # Verify $existingVarName is NOT restored because Disable-ImportDotEnvCdIntegration no longer unloads
                [Environment]::GetEnvironmentVariable($existingVarName) | Should -Be "overwritten_by_env"

                # Restore original DirB .env content
                if ($null -ne $originalDirBEnvContent) { Set-Content -Path $dirBEnvPath -Value $originalDirBEnvContent -Force } else { Remove-Item $dirBEnvPath -Force -ErrorAction SilentlyContinue }
            }

            It "loads .env variables for the current directory upon enabling integration and restores on subsequent cd" -Tag "NewTest" {
                # Mock Get-EnvFilesUpstream for this specific test
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv

                # Ensure integration is disabled initially for this test
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue
                (Get-Command Set-Location).CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)

                # Store initial values of relevant vars (or ensure they are not set)
                $initialTestVarA = "initial_A_for_enable_test"
                $initialTestVarGlobal = "initial_GLOBAL_for_enable_test"
                [Environment]::SetEnvironmentVariable("TEST_VAR_A", $initialTestVarA)
                [Environment]::SetEnvironmentVariable("TEST_VAR_GLOBAL", $initialTestVarGlobal)

                # Go to a directory with a .env file ($script:DirA.FullName contains TEST_VAR_A=valA, TEST_VAR_GLOBAL=valA_override)
                # Use the original Set-Location for this setup step to avoid triggering any premature logic.
                Microsoft.PowerShell.Management\Set-Location $script:DirA.FullName

                # At this point, vars should still be their initial values as integration is off
                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be $initialTestVarA
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $initialTestVarGlobal

                # Enable integration (this should now trigger a load for $script:DirA)
                Enable-ImportDotEnvCdIntegration

                # Verify variables from DirA/.env are loaded
                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be "valA"
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be "valA_override"

                # Now, move out of DirA using the integrated Set-Location. This should trigger unload.
                Set-Location (Split-Path $script:DirA.FullName -Parent)

                # Verify restoration of original values
                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be $initialTestVarA
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $initialTestVarGlobal

                # The AfterEach for this context will call Disable-ImportDotEnvCdIntegration.
                # The mock for Get-EnvFilesUpstream will be automatically removed by Pester as it's It-scoped.
            }

            It "unloads .env variables for the current directory upon disabling integration" -Tag "NewTestDisable" {
                # Mock Get-EnvFilesUpstream for this specific test
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv

                # Ensure integration is disabled initially for this test
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue
                (Get-Command Set-Location).CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)

                # Store initial values of relevant vars
                $initialTestVarA = "initial_A_for_disable_test"
                $initialTestVarGlobal = "initial_GLOBAL_for_disable_test"
                [Environment]::SetEnvironmentVariable("TEST_VAR_A", $initialTestVarA)
                [Environment]::SetEnvironmentVariable("TEST_VAR_GLOBAL", $initialTestVarGlobal)

                # Go to a directory with a .env file ($script:DirA.FullName contains TEST_VAR_A=valA, TEST_VAR_GLOBAL=valA_override)
                # Use the original Set-Location for this setup step.
                Microsoft.PowerShell.Management\Set-Location $script:DirA.FullName

                # Enable integration (this should load .env for DirA)
                Enable-ImportDotEnvCdIntegration

                # Verify variables from DirA/.env are loaded
                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be "valA"
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be "valA_override"

                # Now, disable integration while still in DirA. This should trigger unload.
                Disable-ImportDotEnvCdIntegration

                # Verify variables from DirA/.env REMAIN loaded as Disable-ImportDotEnvCdIntegration no longer unloads
                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be "valA"
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be "valA_override"

                # Verify commands are restored (this is also covered by other tests, but good for completeness here)
                (Get-Command Set-Location).CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                (Get-Command cd).Definition | Should -Be "Set-Location"
            }
        }

        Context "Set-Location Integration - Variable Loading Scenarios" {
            BeforeEach {
                Enable-ImportDotEnvCdIntegration
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
            }
            AfterEach {
                Disable-ImportDotEnvCdIntegration
                # Mocks from BeforeEach are cleaned up when the Context scope ends.
            }

            It "loads variables from .env and restores global on exit" -Tag "First" {
                # Ensure TEST_VAR_A is non-existent at the start of this specific test,
                # overriding any potential BeforeEach restoration from a pre-Pester state.
                $testOne = (Test-Path Env:\TEST_VAR_A)
                if ($testOne) { Remove-Item Env:\TEST_VAR_A -Force }
                # Remove from .NET first
                [Environment]::SetEnvironmentVariable("TEST_VAR_A", $null)

                # Force PowerShell to reload its environment cache
                $env:TEST_VAR_A = $null  # Explicitly set to $null in PowerShell's drive

                # Now check
                $testTwo = (Test-Path Env:\TEST_VAR_A)  # Should now be $false
                $testTwo | Should -Be $false
                Write-Host "TEST SCRIPT (First Test - DIAGNOSTIC): TEST_VAR_A explicitly set to null. Test-Path is $(Test-Path Env:\TEST_VAR_A)" -ForegroundColor Green

                Set-Location $script:DirA.FullName
                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be "valA"
                Write-Host "TEST SCRIPT (First Test - DIAGNOSTIC): TEST_VAR_A after loading DirA is '$([Environment]::GetEnvironmentVariable("TEST_VAR_A"))'" -ForegroundColor Green

                Set-Location (Split-Path $script:DirA.FullName -Parent)

                # ▼ Enhanced validation ▼
                $actualValue = [Environment]::GetEnvironmentVariable("TEST_VAR_A")
                $existsInPSDrive = Test-Path "Env:\TEST_VAR_A"

                $actualValue | Should -BeNullOrEmpty
                $existsInPSDrive | Should -Be $false
            }

            It "loads hierarchically and restores correctly level by level" {
                [Environment]::SetEnvironmentVariable("TEST_VAR_BASE", "initial_base")
                [Environment]::SetEnvironmentVariable("TEST_VAR_OVERRIDE", "initial_override")

                Set-Location $script:SubDir.FullName
                [Environment]::GetEnvironmentVariable("TEST_VAR_BASE") | Should -Be "base_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_SUB") | Should -Be "sub_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "sub_override_val"

                Set-Location $script:BaseDir.FullName # Go to baseDir
                $expectedVarSub = if ($Global:InitialEnvironment.ContainsKey("TEST_VAR_SUB")) { $Global:InitialEnvironment["TEST_VAR_SUB"] } else { $null }
                $actualVarSub = [Environment]::GetEnvironmentVariable("TEST_VAR_SUB")
                Write-Host "TEST SCRIPT: Checking TEST_VAR_SUB. Expected: '$expectedVarSub' (IsNull: $($null -eq $expectedVarSub)). Actual: '$actualVarSub' (IsNull: $($null -eq $actualVarSub), Type: $(if ($null -ne $actualVarSub) { $actualVarSub.GetType().Name } else { 'null' }))"
                (Test-Path "Env:\TEST_VAR_SUB") | Should -Be $false # Expect variable to be non-existent
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "base_override_val"

                # Go to parent directory (which is the Pester test script's directory, effectively)
                Set-Location (Split-Path $script:BaseDir.FullName -Parent)
                [Environment]::GetEnvironmentVariable("TEST_VAR_BASE") | Should -Be "initial_base"
                $expectedVarSubGlobal = if ($Global:InitialEnvironment.ContainsKey("TEST_VAR_SUB")) { $Global:InitialEnvironment["TEST_VAR_SUB"] } else { $null }
                $actualVarSubGlobal = [Environment]::GetEnvironmentVariable("TEST_VAR_SUB")
                Write-Host "TEST SCRIPT: Checking TEST_VAR_SUB (Global). Expected: '$expectedVarSubGlobal' (IsNull: $($null -eq $expectedVarSubGlobal)). Actual: '$actualVarSubGlobal' (IsNull: $($null -eq $actualVarSubGlobal), Type: $(if ($null -ne $actualVarSubGlobal) { $actualVarSubGlobal.GetType().Name } else { 'null' }))"
                (Test-Path "Env:\TEST_VAR_SUB") | Should -Be $false # Expect variable to be non-existent
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "initial_override"
            }


            It "creates a new variable and removes it on exit (restores to non-existent)" {
                Set-Location $script:DirB.FullName
                [Environment]::GetEnvironmentVariable("NEW_VAR") | Should -Be "new_value"
                # Go to parent directory
                Set-Location (Split-Path $script:DirB.FullName -Parent)
                $expectedNewVar = if ($Global:InitialEnvironment.ContainsKey("NEW_VAR")) { $Global:InitialEnvironment["NEW_VAR"] } else { $null }
                $actualNewVar = [Environment]::GetEnvironmentVariable("NEW_VAR")
                Write-Host "TEST SCRIPT: Checking NEW_VAR. Expected: '$expectedNewVar' (IsNull: $($null -eq $expectedNewVar)). Actual: '$actualNewVar' (IsNull: $($null -eq $actualNewVar), Type: $(if ($null -ne $actualNewVar) { $actualNewVar.GetType().Name } else { 'null' }))"
                (Test-Path "Env:\NEW_VAR") | Should -Be $false # Expect variable to be non-existent
            }


            It "sets variable to empty string from .env and restores previous value on exit" {
                [Environment]::SetEnvironmentVariable("TEST_EMPTY_VAR", "initial_empty_test_val")

                Set-Location $script:DirC.FullName

                $actualValueInTest = [Environment]::GetEnvironmentVariable("TEST_EMPTY_VAR")
                if ($null -eq $actualValueInTest) {
                    Write-Host "TEST SCRIPT: TEST_EMPTY_VAR is NULL after Set-Location to DirC."
                }
                else {
                    Write-Host "TEST SCRIPT: TEST_EMPTY_VAR is '$actualValueInTest' (Length: $($actualValueInTest.Length)) after Set-Location to DirC."
                }
                # An empty value in .env should result in an empty string environment variable.
                $actualValueInTest | Should -Be ""
                # Go to parent directory
                Set-Location (Split-Path $script:DirC.FullName -Parent)
                [Environment]::GetEnvironmentVariable("TEST_EMPTY_VAR") | Should -Be "initial_empty_test_val"
            }


            It "correctly unloads project1 vars and loads project2 vars, then restores global" {
                [Environment]::SetEnvironmentVariable("PROJECT_ID", "global_project_id")

                Set-Location $script:Project1Dir.FullName
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be "P1"

                # Simulate cd project2 (which internally does Pop then Push or direct Set-Location)
                Set-Location $script:Project2Dir.FullName
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be "P2"

                # Go to parent directory
                Set-Location (Split-Path $script:Project2Dir.FullName -Parent)
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be "global_project_id"
            }


            It "should not alter existing environment variables when moving to a dir with no .env" {
                [Environment]::SetEnvironmentVariable("TEST_VAR_GLOBAL", "no_env_test_initial")
                $originalValue = [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL")
                Set-Location $script:NonEnvDir.FullName
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $originalValue
                # Go to parent directory
                Set-Location (Split-Path $script:NonEnvDir.FullName -Parent)
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $originalValue
            }
        }
    } # End of Describe "Import-DotEnv Core and Integration Tests"
} # End of InModuleScope
