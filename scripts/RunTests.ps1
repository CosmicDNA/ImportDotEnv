# Run Pester tests and capture the results
param (
    [switch]$EnableCoverage = $false,
    [switch]$GenerateReport = $false
)

$coverage = $EnableCoverage.IsPresent
$generateReport = $GenerateReport.IsPresent

$config = New-PesterConfiguration
$config.Run.PassThru = $true
$config.Output.Verbosity = "Detailed"

if ($coverage){
  $coverageReportPath = "coverage.xml"
  $callingDirectory = Get-Location
  $config.CodeCoverage.Enabled = $true
  $config.CodeCoverage.Path = "*.psm1"
  $config.CodeCoverage.OutputPath = Join-Path $callingDirectory $coverageReportPath
  $config.CodeCoverage.OutputFormat = 'JaCoCo'
}

$results = Invoke-Pester -Configuration $config

# Check if any tests failed
if ($results.FailedCount -gt 0) {
    Write-Error "Pester tests failed. See the output for details."
    # Throw an error to stop the script
    throw "Pester tests failed."
} else {
    Write-Host "All Pester tests passed successfully."
}

if ($coverage){
  # Access code coverage information
  $coverage = $results.CodeCoverage
  $coveragePercentage = [math]::Round($coverage.CoveragePercent, 2)
  Write-Host "Coverage Percentage: " -NoNewline
  Write-Host "$coveragePercentage %`n" -ForegroundColor Green

  if ($generateReport){
    Write-Host Generating coverage report... -ForegroundColor Magenta
    ./reportgenerator/ReportGenerator.exe -reports:$coverageReportPath -targetdir:reports -reporttypes:'Latex;Html' -sourcedirs:.\ | Out-Null
  }
  # Return the rounded coverage percentage
  return $coveragePercentage
}