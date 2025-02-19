param(
  [String]$str
)
if ($str -match 'v(\d+\.\d+\.\d+)(-(beta|alpha|rc)(\.(\d+))?)?') {
  $BUILD_VERSION = $matches[1]
  Write-Output "BUILD_VERSION: $BUILD_VERSION"
  # Write-Output "BUILD_VERSION=$BUILD_VERSION" >> $env:GITHUB_ENV
  if ($matches[3]) {
    $TAG_TYPE = $matches[3]
    Write-Output "TAG_TYPE=$TAG_TYPE"
    if ($matches[5]) {
      $BUILD_NUMBER = $matches[5]
      Write-Output "BUILD_NUMBER=$BUILD_NUMBER"
    }
  }
}