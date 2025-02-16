# Run Pester tests and capture the results
$parentPath = Split-Path "$PSScriptRoot" -Parent
$testsPath = Join-Path $parentPath "Tests"

$results = Invoke-Pester -Path "$testsPath" -Output Detailed -PassThru

# Check if any tests failed
if ($results.FailedCount -gt 0) {
    Write-Error "Pester tests failed. See the output for details."
    # You can optionally throw an error to stop the script
    throw "Pester tests failed."
} else {
    Write-Host "All Pester tests passed successfully."
}

# You can also use a more detailed message
$results | ForEach-Object {
    if ($_.FailedCount -gt 0) {
        $_.TestResult.Failed | ForEach-Object {
            Write-Error "Test '$($_.Name)' failed in script '$($_.ScriptPath)' with message: $($_.FailureMessage)"
        }
    }
}
