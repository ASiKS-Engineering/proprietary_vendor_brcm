# Downloads a compiled Hailo-8 model (HEF) and installs it as default.hef (or another name).
# There is no built-in default URL: the HEF must be compiled for the HailoRT version that is
# packaged in the vendor image (4.24.0) - check with `hailortcli parse-hef` once the runtime is built.
# Models from the Hailo Model Zoo are published at
# https://hailo-model-zoo.s3.eu-west-2.amazonaws.com/ModelZoo/Compiled/<zoo-version>/hailo8/<model>.hef
#
#   .\fetch_hailo_model.ps1 -Url <https-url-to-hef> [-Sha256 <hash>] [-Name default.hef]
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$Sha256,
    [string]$Name = 'default.hef',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ($Name -notmatch '^[A-Za-z0-9._-]+\.hef$') {
    throw "Invalid model name '$Name'; expected something like default.hef."
}

$destDir = Join-Path $PSScriptRoot '..\proprietary\vendor\etc\hailo\models'
$dest = Join-Path $destDir $Name

New-Item -ItemType Directory -Force $destDir | Out-Null

if ((Test-Path $dest) -and -not $Force) {
    throw "$dest already exists; use -Force to overwrite."
}

$tmp = "$dest.download"
Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
$hash = (Get-FileHash $tmp -Algorithm SHA256).Hash
if ($Sha256 -and $hash -ne $Sha256) {
    Remove-Item $tmp -Force
    throw "SHA256 mismatch for $Url`n expected $Sha256`n actual   $hash"
}
Move-Item $tmp $dest -Force
Write-Host "Model written to $dest ($((Get-Item $dest).Length) bytes, SHA256 $hash)"
