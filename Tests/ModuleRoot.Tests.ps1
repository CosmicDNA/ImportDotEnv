# This module should simply test with pester importing the module with
# Import-Module "$PSScriptRoot/../ImportDotEnv.psm1" -Force
# and then calling the function Import-DotEnv with a .env file in the same directory
# and then checking that the environment variables are set correctly
Describe "Import-DotEnv" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../ImportDotEnv.psm1" -Force
        New-Item -ItemType File -Path "$PSScriptRoot/.env" -Force -Value "TEST_VAR=test_value"
    }

    AfterAll {
        Remove-Item -Path "$PSScriptRoot/.env" -Force
    }

    It "should import environment variables from .env file" {
        Import-DotEnv -Path "$PSScriptRoot/.env"
        $env:TEST_VAR | Should -Be "test_value"
    }
}
