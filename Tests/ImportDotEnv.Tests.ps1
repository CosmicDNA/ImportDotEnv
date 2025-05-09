# c:\Users\dani_\Workspaces\ImportDotEnv\Tests\ImportDotEnv.Tests.ps1

#Requires -Modules Pester
param(
    [string]$ModulePath = (Resolve-Path (Join-Path $PSScriptRoot "..\ImportDotEnv.psm1")).Path # Assuming tests are in a subfolder
)

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
            $testVarNames = @("TEST_VAR_GLOBAL", "TEST_VAR_A", "TEST_VAR_BASE", "TEST_VAR_OVERRIDE", "TEST_VAR_SUB", "NEW_VAR", "TEST_EMPTY_VAR", "PROJECT_ID")
            foreach ($varName in $testVarNames) {
                $initialVal = $Global:InitialEnvironment[$varName]
                if ($null -eq $initialVal) {
                    # Ensure it's truly non-existent if its initial state was null.
                    # Remove-Item is the most reliable way to ensure GetEnvironmentVariable returns $null.
                    if (Test-Path "Env:\$varName") { Remove-Item "Env:\$varName" -Force -ErrorAction SilentlyContinue }
                } else {
                    [Environment]::SetEnvironmentVariable($varName, $initialVal)
                }
            }
            Write-Host "BeforeEach (Start): Environment variables reset."
            # Ensure TestRoot is accessible. It should be inherited from BeforeAll's $script: scope.
            $currentTestRoot = $script:TestRoot
            Write-Host "BeforeEach: Value of currentTestRoot (from script:TestRoot) is '$currentTestRoot'"
            if (-not $currentTestRoot) { throw "BeforeEach: currentTestRoot (from script:TestRoot) is not set!" }

            # Reset module's internal state by cd'ing to a neutral location and triggering ImportDotEnv
            # This ensures the module's $script:previousEnvFiles and $script:originalEnvironmentVariables are reset.
            $parentOfTestRoot = Split-Path $currentTestRoot -Parent
            Write-Host "BeforeEach: Attempting to Push-Location to '$parentOfTestRoot'"
            Push-Location $parentOfTestRoot # Go to a neutral place (parent of test root)
            Write-Host "BeforeEach: Pushed location. Current PWD: $($PWD.Path)"

            # Ensure ImportDotEnv is available (should be from BeforeAll)
            # Try to invoke the command directly from the stored module object
            if (-not $script:ImportDotEnvModule) {
                throw "BeforeEach: script:ImportDotEnvModule is not available!"
            }

            try {
                # Call Import-DotEnv to reset its internal state.
                # This will now use the actual Get-EnvFilesUpstream. Ensure $parentOfTestRoot is clean.
                # Call Import-DotEnv directly by name, relying on InModuleScope
                Import-DotEnv -Path "." # Path is $parentOfTestRoot
                Write-Host "BeforeEach: Import-DotEnv (via direct invoke) SUCCEEDED and called."
            }
            catch {
                Write-Host "BeforeEach: FAILED to invoke Import-DotEnv directly from module object. Error: $($_.Exception.Message)"
                throw "BeforeEach: FAILED to invoke Import-DotEnv directly. See logs."
            }
            Pop-Location
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
            foreach ($varName in $Global:InitialEnvironment.Keys) {
                [Environment]::SetEnvironmentVariable($varName, $Global:InitialEnvironment[$varName])
            }
            # Ensure cd integration is disabled after all tests in this describe block
            if (Get-Command Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue) {
                Disable-ImportDotEnvCdIntegration
            }
            Remove-Module ImportDotEnv -Force
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
                Remove-Item $manualEnvFile -ErrorAction SilentlyContinue
            }
        }

        Context "Set-Location Integration (Enable/Disable Functionality)" {
            AfterEach {
                # Ensure integration is disabled after each test in this context
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue
                # No mocks are set up in the BeforeEach or It blocks of this specific Context,
                # so no Remove-Mock is needed here.
            }

            It "Set-Location should be the original cmdlet by default after module import" {
                # Ensure a clean state for this specific test, in case of prior partial runs
                Disable-ImportDotEnvCdIntegration -ErrorAction SilentlyContinue
                (Get-Command Set-Location).CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                (Get-Command Set-Location).ModuleName | Should -Be "Microsoft.PowerShell.Management"
            }

            It "Enable-ImportDotEnvCdIntegration should alias Set-Location, cd, sl" {
                Enable-ImportDotEnvCdIntegration # This function is called from within InModuleScope 'ImportDotEnv'

                # Check Set-Location
                $cmd = Get-Command Set-Location -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNull
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                $cmd.Definition | Should -Be "ImportDotEnv\Invoke-ImportDotEnvSetLocationWrapper"
                $cmd.ResolvedCommand.Name | Should -Be "Invoke-ImportDotEnvSetLocationWrapper"
                $cmd.ResolvedCommand.ModuleName | Should -Be "ImportDotEnv"

                # Check cd
                # Get all commands named 'cd' and find the function one, if it exists.
                # This is to handle cases where the default alias might still be present but our function also exists.
                $cdCommands = Get-Command cd -All -ErrorAction SilentlyContinue
                $cdCommands | Should -Not -BeNullOrEmpty
                $cdFunction = $cdCommands | Where-Object { $_.CommandType -eq [System.Management.Automation.CommandTypes]::Function }
                $cdFunction | Should -Not -BeNull "Expected to find a 'cd' command that is a Function."
                $cdFunction.Definition | Should -Match ([regex]::Escape("ImportDotEnv\Invoke-ImportDotEnvSetLocationWrapper"))
                $cdFunction.Name | Should -Be "cd"
                # If multiple 'cd' commands exist (e.g., Alias and Function), ensure the Function is what would be resolved by default
                # This is harder to test directly without invoking. The Disable-ImportDotEnvCdIntegration log is good evidence.
                # $cmd.ModuleName | Should -Be "__DynamicModule_" # Or "ImportDotEnv" if it was the wrapper itself

                # Check sl
                $cmd = Get-Command sl -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNull
                $cmd.CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Function)
                $cmd.Definition | Should -Match ([regex]::Escape("ImportDotEnv\Invoke-ImportDotEnvSetLocationWrapper"))
                $cmd.Name | Should -Be "sl"
                # $cmd.ModuleName | Should -Be "__DynamicModule_"
            }

            It "Disable-ImportDotEnvCdIntegration should restore Set-Location, cd, sl to defaults" {
                Enable-ImportDotEnvCdIntegration # Enable it first
                # At this point, cd and sl are functions. Set-Location is an alias.
                Disable-ImportDotEnvCdIntegration # Then disable

                (Get-Command Set-Location -ErrorAction SilentlyContinue).CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Cmdlet)
                (Get-Command Set-Location).ModuleName | Should -Be "Microsoft.PowerShell.Management"
                (Get-Command cd).CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                (Get-Command cd).Definition | Should -Be "Set-Location" # Default alias target
                (Get-Command sl).CommandType | Should -Be ([System.Management.Automation.CommandTypes]::Alias)
                (Get-Command sl).Definition | Should -Be "Set-Location" # Default alias target
            }
        }

        Context "Behavior with Set-Location integration enabled" {
            BeforeEach {
                Enable-ImportDotEnvCdIntegration
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
            }
            AfterEach {
                Disable-ImportDotEnvCdIntegration
                # Mocks from BeforeEach are cleaned up when the Context scope ends.
            }

            It "loads variables from .env and restores global on exit" {
                [Environment]::SetEnvironmentVariable("TEST_VAR_GLOBAL", "initial_global_val")
                Set-Location $script:DirA.FullName

                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be "valA"
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be "valA_override"

                # Go to parent directory (which is the Pester test script's directory)
                Set-Location (Split-Path $script:DirA.FullName -Parent)

                $expectedVarA = if ($Global:InitialEnvironment.ContainsKey("TEST_VAR_A")) { $Global:InitialEnvironment["TEST_VAR_A"] } else { $null }
                $actualVarA = [Environment]::GetEnvironmentVariable("TEST_VAR_A")
                Write-Host "TEST SCRIPT: Checking TEST_VAR_A. Expected: '$expectedVarA' (IsNull: $($null -eq $expectedVarA)). Actual: '$actualVarA' (IsNull: $($null -eq $actualVarA), Type: $(if ($null -ne $actualVarA) { $actualVarA.GetType().Name } else { 'null' }))"
                (Test-Path "Env:\TEST_VAR_A") | Should -Be $false # Expect variable to be non-existent
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be "initial_global_val"
            }
        }

        Context "Hierarchical Load and Restore (with cd integration)" {
            BeforeEach {
                Enable-ImportDotEnvCdIntegration
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
            }
            AfterEach {
                Disable-ImportDotEnvCdIntegration
                # Mocks from BeforeEach are cleaned up when the Context scope ends.
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
        }

        Context "Variable Creation and Removal (with cd integration)" {
            BeforeEach {
                Enable-ImportDotEnvCdIntegration
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
            }
            AfterEach {
                Disable-ImportDotEnvCdIntegration
                # Mocks from BeforeEach are cleaned up when the Context scope ends.
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
        }

        Context "Empty Value Handling in .env (with cd integration)" {
            BeforeEach {
                Enable-ImportDotEnvCdIntegration
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
            }
            AfterEach {
                Disable-ImportDotEnvCdIntegration
                # Mocks from BeforeEach are cleaned up when the Context scope ends.
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
        }

        Context "Moving Between Unrelated Projects (with cd integration)" {
            BeforeEach {
                Enable-ImportDotEnvCdIntegration
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
            }
            AfterEach {
                Disable-ImportDotEnvCdIntegration
                # Mocks from BeforeEach are cleaned up when the Context scope ends.
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
        }

        Context "No .env files in path (with cd integration)" {
            BeforeEach {
                Enable-ImportDotEnvCdIntegration
                Mock Get-EnvFilesUpstream -MockWith $script:GetEnvFilesUpstreamMock -ModuleName ImportDotEnv
            }
            AfterEach {
                Disable-ImportDotEnvCdIntegration
                # Mocks from BeforeEach are cleaned up when the Context scope ends.
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
    } # End of Describe
} # End of InModuleScope
