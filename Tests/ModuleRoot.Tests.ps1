# This module should simply test with pester importing the module with
# Import-Module "$PSScriptRoot/../ImportDotEnv.psm1" -Force
Describe "Import-DotEnv" {
    It "should import environment variables from .env file" {
        Import-Module "$PSScriptRoot/../ImportDotEnv.psm1" -Force
    }
}
