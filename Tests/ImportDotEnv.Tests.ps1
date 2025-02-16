Describe "Import-DotEnv" {
    BeforeAll {
        Import-Module .\ImportDotEnv.psm1
        # Create a temporary directory in TestDrive
        $tempDir = New-Item -ItemType Directory -Path "$TestDrive\ImportDotEnvTest"
    }
    Context "With TEST_VAR=123 within .env" {
        BeforeAll {
            $envFilePath = Join-Path $tempDir.FullName ".env"
            Set-Content -Path $envFilePath -Value "TEST_VAR=123"
        }
        It "Loads environment variables from a .env file" {
            # Change to the directory containing the .env file
            Set-Location -Path $tempDir

            # Assert that TEST_VAR is set to "123"
            $env:TEST_VAR | Should -Be "123"
        }
        It "Unloads environment variables from a .env file" {
            # Change to the directory containing the .env file
            Set-Location -Path $tempDir

            # Assert that TEST_VAR is set to "123"
            $env:TEST_VAR | Should -Be "123"

            # Unload the .env file, so reset the working directory
            Set-Location -Path $TestDrive

            # Assert that TEST_VAR is unset (null)
            $env:TEST_VAR | Should -BeNullOrEmpty
        }
        Context "Handling multiple .env files" {
            BeforeAll {
                # Create another temporary .env file
                $subDir = New-Item -ItemType Directory -Path "$tempDir\subdir"
                $envFilePath2 = Join-Path $subDir.FullName ".env"
                Set-Content -Path $envFilePath2 -Value "TEST_VAR2=456"
            }
            It "Loads and unloads multiple .env files correctly" {
                # Change to the directory containing the .env files
                Set-Location -Path $tempDir

                # Assert that TEST_VAR1 is set to "123" and TEST_VAR2 is not set
                $env:TEST_VAR | Should -Be "123"
                $env:TEST_VAR2 | Should -BeNullOrEmpty

                # Load the second .env file
                Set-Location -Path $subDir

                # Assert that both TEST_VAR1 and TEST_VAR2 are set
                $env:TEST_VAR | Should -Be "123"
                $env:TEST_VAR2 | Should -Be "456"

                # Unload the first .env file
                Set-Location -Path $tempDir

                # Assert that TEST_VAR1 is unset and TEST_VAR2 is still set
                $env:TEST_VAR | Should -Be "123"
                $env:TEST_VAR2 | Should -BeNullOrEmpty

                # Unload the second .env file
                Set-Location -Path $TestDrive

                # Assert that both TEST_VAR1 and TEST_VAR2 are unset
                $env:TEST_VAR | Should -BeNullOrEmpty
                $env:TEST_VAR2 | Should -BeNullOrEmpty
            }
        }
    }

    Context "Edge cases" {
        It "Does not throw an error if the .env file does not exist" {
            # Change to the directory containing the .env file
            { Set-Location -Path $tempDir } | Should -Not -Throw
        }

        It "Handles empty .env files correctly" {
            # Create a temporary .env file with no content
            $envFilePath = Join-Path $tempDir.FullName ".env"

            Set-Content -Path $envFilePath -Value ""

            # Change to the directory containing the .env file
            Set-Location -Path $tempDir

            # Test the function
            { Import-DotEnv -Path $envFilePath } | Should -Not -Throw

            # Assert that no environment variables are set
            $env:TEST_VAR | Should -BeNullOrEmpty
        }
    }

    AfterAll {
        Remove-Module ImportDotEnv
    }
}