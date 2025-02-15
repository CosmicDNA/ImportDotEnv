Describe "Import-DotEnv" {
  Context "Loading environment variables" {
      It "Loads environment variables from a .env file" {
          # Create a temporary .env file
          $tempDir = New-Item -ItemType Directory -Path "$env:TEMP\ImportDotEnvTest_$(Get-Random)"
          $envFilePath = Join-Path $tempDir.FullName ".env"

          Set-Content -Path $envFilePath -Value "TEST_VAR=123"

          try {
              # Change to the directory containing the .env file
              Set-Location -Path $tempDir

              # Assert that TEST_VAR is set to "123"
              $env:TEST_VAR | Should -Be "123"
          }
          finally {
              # Reset the working directory
              Set-Location -Path $env:TEMP

              # Clean up
              Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
              Remove-Item -Path Env:\TEST_VAR -Force -ErrorAction SilentlyContinue
          }
      }
  }

  Context "Unloading environment variables" {
      It "Unloads environment variables from a .env file" {
          # Create a temporary .env file
          $tempDir = New-Item -ItemType Directory -Path "$env:TEMP\ImportDotEnvTest_$(Get-Random)"
          $envFilePath = Join-Path $tempDir.FullName ".env"

          Set-Content -Path $envFilePath -Value "TEST_VAR=123"

          try {
              # Change to the directory containing the .env file
              Set-Location -Path $tempDir

              # Assert that TEST_VAR is set to "123"
              $env:TEST_VAR | Should -Be "123"

              # Unload the .env file, so reset the working directory
              Set-Location -Path $env:TEMP

              # Assert that TEST_VAR is unset (null)
              $env:TEST_VAR | Should -BeNullOrEmpty
          }
          finally {
              # Clean up
              Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
              Remove-Item -Path Env:\TEST_VAR -Force -ErrorAction SilentlyContinue
          }
      }
  }

  Context "Handling multiple .env files" {
      It "Loads and unloads multiple .env files correctly" {
          # Create a temporary directory with two .env files
          $tempDir = New-Item -ItemType Directory -Path "$env:TEMP\ImportDotEnvTest_$(Get-Random)"
          $envFilePath1 = Join-Path $tempDir.FullName ".env"
          $subDir = New-Item -ItemType Directory -Path "$tempDir\subdir"
          $envFilePath2 = Join-Path $subDir.FullName ".env"

          Set-Content -Path $envFilePath1 -Value "TEST_VAR1=123"
          Set-Content -Path $envFilePath2 -Value "TEST_VAR2=456"

          try {
              # Change to the directory containing the .env files
              Set-Location -Path $tempDir

              # Assert that TEST_VAR1 is set to "123" and TEST_VAR2 is not set
              $env:TEST_VAR1 | Should -Be "123"
              $env:TEST_VAR2 | Should -BeNullOrEmpty

              # Load the second .env file
              Set-Location -Path $subDir

              # Assert that both TEST_VAR1 and TEST_VAR2 are set
              $env:TEST_VAR1 | Should -Be "123"
              $env:TEST_VAR2 | Should -Be "456"

              # Unload the first .env file
              Set-Location -Path $tempDir

              # Assert that TEST_VAR1 is unset and TEST_VAR2 is still set
              $env:TEST_VAR1 | Should -Be "123"
              $env:TEST_VAR2 | Should -BeNullOrEmpty

              # Unload the second .env file
              Set-Location -Path $env:TEMP

              # Assert that both TEST_VAR1 and TEST_VAR2 are unset
              $env:TEST_VAR1 | Should -BeNullOrEmpty
              $env:TEST_VAR2 | Should -BeNullOrEmpty
          }
          finally {
              # Clean up
              Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
              Remove-Item -Path Env:\TEST_VAR1 -Force -ErrorAction SilentlyContinue
              Remove-Item -Path Env:\TEST_VAR2 -Force -ErrorAction SilentlyContinue
          }
      }
  }

  Context "Edge cases" {
      It "Does not throw an error if the .env file does not exist" {
          $tempDir = New-Item -ItemType Directory -Path "$env:TEMP\ImportDotEnvTest_$(Get-Random)"
          try {
              # Change to the directory containing the .env file
              { Set-Location -Path $tempDir } | Should -Not -Throw
          }
          finally {
              # Reset the working directory
              Set-Location -Path $env:TEMP

              # Clean up
              Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
          }
      }

      It "Handles empty .env files correctly" {
          # Create a temporary .env file with no content
          $tempDir = New-Item -ItemType Directory -Path "$env:TEMP\ImportDotEnvTest_$(Get-Random)"
          $envFilePath = Join-Path $tempDir.FullName ".env"

          Set-Content -Path $envFilePath -Value ""

          try {
              # Change to the directory containing the .env file
              Set-Location -Path $tempDir

              # Test the function
              { Import-DotEnv -Path $envFilePath } | Should -Not -Throw

              # Assert that no environment variables are set
              $env:TEST_VAR | Should -BeNullOrEmpty
          }
          finally {
              # Reset the working directory
              Set-Location -Path $env:TEMP

              # Clean up
              Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
          }
      }
  }
}