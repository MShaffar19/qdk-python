# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

<#
    .SYNOPSIS
        Test: Run unit tests for given packages/environments
#>

param (
  [string[]] $PackageDirs,
  [string[]] $EnvNames
)

& (Join-Path $PSScriptRoot "set-env.ps1");

Import-Module (Join-Path $PSScriptRoot "conda-utils.psm1");

if ($null -eq $PackageDirs) {
  $ParentPath = Split-Path -parent $PSScriptRoot
  $PackageDirs = Get-ChildItem -Path $ParentPath -Recurse -Filter "environment.yml" | Select-Object -ExpandProperty Directory | Split-Path -Leaf
  Write-Host "##[info]No PackageDir. Setting to default '$PackageDirs'"
}

if ($null -eq $EnvNames) {
  $EnvNames = $PackageDirs | ForEach-Object {$_.replace("-", "")}
  Write-Host "##[info]No EnvNames. Setting to default '$EnvNames'"
}

# Check that input is valid
if ($EnvNames.length -ne $PackageDirs.length) {
  throw "Cannot run build script: '$EnvNames' and '$PackageDirs' lengths don't match"
}

function Invoke-Unit-Tests() {
  param(
    [string] $PackageDir,
    [string] $EnvName
  )
  $ParentPath = Split-Path -parent $PSScriptRoot
  $AbsPackageDir = Join-Path $ParentPath $PackageDir
  Write-Host "##[info]Run unit tests for package $AbsPackageDir in env $EnvName"
  # Activate env
  Use-CondaEnv $EnvName
  # Install testing deps
  python -m pip install --upgrade pip
  pip install pytest pytest-azurepipelines
  # Run tests
  pytest $AbsPackageDir
}

function Invoke-Integration-Tests() {
  param(
    [string] $PackageDir,
    [string] $EnvName
  )
  $ParentPath = Split-Path -parent $PSScriptRoot
  $AbsPackageDir = Join-Path $ParentPath $PackageDir
  $IntegrationTestsPath = Join-Path $AbsPackageDir "tests" "integration"
  if (Test-Path -Path $IntegrationTestsPath) {
    Write-Host "##[info]Run integration tests for package $AbsPackageDir in env $EnvName"
    # Activate env
    Use-CondaEnv $EnvName
    # Run integration tests
    $TestFiles = Get-ChildItem $IntegrationTestsPath -Filter *.py
    ForEach ($file in $TestFiles) {
      python $file.FullName
    }
  }
}

if ($Env:ENABLE_PYTHON -eq "false") {
  Write-Host "##vso[task.logissue type=warning;]Skipping testing Python packages. Env:ENABLE_PYTHON was set to 'false'."
} else {
  for ($i=0; $i -le $PackageDirs.length-1; $i++) {
    Invoke-Unit-Tests -PackageDir $PackageDirs[$i] -EnvName $EnvNames[$i]
    if ($Env:ENABLE_INTEGRATION_TESTS -eq "false") {
      Write-Host "##vso[task.logissue type=warning;]Skipping integration tests. Env:ENABLE_INTEGRATION_TESTS was set to 'false'."
    } else {
      Invoke-Integration-Tests -PackageDir $PackageDirs[$i] -EnvName $EnvNames[$i]
    }
  }
}
