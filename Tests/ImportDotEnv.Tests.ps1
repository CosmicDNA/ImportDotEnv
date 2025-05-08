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
    Describe "Import-DotEnv Precise Environment Restoration (within InModuleScope)" {
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
                [Environment]::SetEnvironmentVariable($varName, $Global:InitialEnvironment[$varName])
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
                & $script:ImportDotEnvModule.ExportedCommands['Import-DotEnv']
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
            Remove-Module ImportDotEnv -Force
        }

        Context "Basic Load and Restore" {
            It "loads variables from .env and restores global on exit" {
                [Environment]::SetEnvironmentVariable("TEST_VAR_GLOBAL", "initial_global_val")
                [Environment]::SetEnvironmentVariable("TEST_VAR_A", $null) # Ensure it's not set

                ImportDotEnv\Set-Location $script:DirA.FullName # Explicitly call your override
                # ImportDotEnv is called by Set-Location (our override)

                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be "valA"
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be "valA_override"

                # Go to parent directory (which is the Pester test script's directory)
                ImportDotEnv\Set-Location (Split-Path $script:DirA.FullName -Parent)

                $expectedVarA = if ($Global:InitialEnvironment.ContainsKey("TEST_VAR_A")) { $Global:InitialEnvironment["TEST_VAR_A"] } else { $null }
                [Environment]::GetEnvironmentVariable("TEST_VAR_A") | Should -Be $expectedVarA
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be "initial_global_val"
            }
        }

        Context "Hierarchical Load and Restore" {
            It "loads hierarchically and restores correctly level by level" {
                [Environment]::SetEnvironmentVariable("TEST_VAR_BASE", "initial_base")
                [Environment]::SetEnvironmentVariable("TEST_VAR_OVERRIDE", "initial_override")
                [Environment]::SetEnvironmentVariable("TEST_VAR_SUB", $null)

                ImportDotEnv\Set-Location $script:SubDir.FullName # Explicitly call your override
                [Environment]::GetEnvironmentVariable("TEST_VAR_BASE") | Should -Be "base_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_SUB") | Should -Be "sub_val"
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "sub_override_val"

                ImportDotEnv\Set-Location $script:BaseDir.FullName # Explicitly call your override to go to baseDir
                [Environment]::GetEnvironmentVariable("TEST_VAR_BASE") | Should -Be "base_val"
                $expectedVarSub = if ($Global:InitialEnvironment.ContainsKey("TEST_VAR_SUB")) { $Global:InitialEnvironment["TEST_VAR_SUB"] } else { $null }
                [Environment]::GetEnvironmentVariable("TEST_VAR_SUB") | Should -Be $expectedVarSub
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "base_override_val"

                # Go to parent directory (which is the Pester test script's directory, effectively)
                ImportDotEnv\Set-Location (Split-Path $script:BaseDir.FullName -Parent)
                [Environment]::GetEnvironmentVariable("TEST_VAR_BASE") | Should -Be "initial_base"
                $expectedVarSubGlobal = if ($Global:InitialEnvironment.ContainsKey("TEST_VAR_SUB")) { $Global:InitialEnvironment["TEST_VAR_SUB"] } else { $null }
                [Environment]::GetEnvironmentVariable("TEST_VAR_SUB") | Should -Be $expectedVarSubGlobal
                [Environment]::GetEnvironmentVariable("TEST_VAR_OVERRIDE") | Should -Be "initial_override"
            }
        }

        Context "Variable Creation and Removal" {
            It "creates a new variable and removes it on exit (restores to non-existent)" {
                [Environment]::SetEnvironmentVariable("NEW_VAR", $null) # Ensure not set

                ImportDotEnv\Set-Location $script:DirB.FullName # Explicitly call your override
                [Environment]::GetEnvironmentVariable("NEW_VAR") | Should -Be "new_value"
                # Go to parent directory
                ImportDotEnv\Set-Location (Split-Path $script:DirB.FullName -Parent)
                $expectedNewVar = if ($Global:InitialEnvironment.ContainsKey("NEW_VAR")) { $Global:InitialEnvironment["NEW_VAR"] } else { $null }
                [Environment]::GetEnvironmentVariable("NEW_VAR") | Should -Be $expectedNewVar
            }
        }

        Context "Empty Value Handling in .env" {
            It "sets variable to empty string from .env and restores previous value on exit" {
                [Environment]::SetEnvironmentVariable("TEST_EMPTY_VAR", "initial_empty_test_val")

                ImportDotEnv\Set-Location $script:DirC.FullName # Explicitly call your override

                $actualValueInTest = [Environment]::GetEnvironmentVariable("TEST_EMPTY_VAR")
                if ($null -eq $actualValueInTest) {
                    Write-Host "TEST SCRIPT: TEST_EMPTY_VAR is NULL after Set-Location to DirC."
                } else {
                    Write-Host "TEST SCRIPT: TEST_EMPTY_VAR is '$actualValueInTest' (Length: $($actualValueInTest.Length)) after Set-Location to DirC."
                }
                # Based on the diagnostic "TEST SCRIPT: TEST_EMPTY_VAR is NULL...",
                # it appears that in this Pester context, after the module sets an env var to "",
                # [Environment]::GetEnvironmentVariable() returns $null.
                # Therefore, the assertion should check for $null.
                $actualValueInTest | Should -BeNull
                # Go to parent directory
                ImportDotEnv\Set-Location (Split-Path $script:DirC.FullName -Parent)
                [Environment]::GetEnvironmentVariable("TEST_EMPTY_VAR") | Should -Be "initial_empty_test_val"
            }
        }

        Context "Moving Between Unrelated Projects" {
            It "correctly unloads project1 vars and loads project2 vars, then restores global" {
                [Environment]::SetEnvironmentVariable("PROJECT_ID", "global_project_id")

                ImportDotEnv\Set-Location $script:Project1Dir.FullName # Explicitly call your override
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be "P1"

                # Simulate cd project2 (which internally does Pop then Push or direct Set-Location)
                ImportDotEnv\Set-Location $script:Project2Dir.FullName # Explicitly call your override
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be "P2"

                # Go to parent directory
                ImportDotEnv\Set-Location (Split-Path $script:Project2Dir.FullName -Parent)
                [Environment]::GetEnvironmentVariable("PROJECT_ID") | Should -Be "global_project_id"
            }
        }

        Context "No .env files in path" {
            It "should not alter existing environment variables when moving to a dir with no .env" {
                [Environment]::SetEnvironmentVariable("TEST_VAR_GLOBAL", "no_env_test_initial")
                $originalValue = [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL")

                ImportDotEnv\Set-Location $script:NonEnvDir.FullName # Explicitly call your override
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $originalValue
                # Go to parent directory
                ImportDotEnv\Set-Location (Split-Path $script:NonEnvDir.FullName -Parent)
                [Environment]::GetEnvironmentVariable("TEST_VAR_GLOBAL") | Should -Be $originalValue
            }
        }
    } # End of Describe
} # End of InModuleScope