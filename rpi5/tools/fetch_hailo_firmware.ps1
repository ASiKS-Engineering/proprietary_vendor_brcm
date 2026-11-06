# Downloads the Hailo-8 firmware used by the hailo_pci kernel driver and verifies its SHA256.
# The blob is not stored in git (see ../.gitignore); run this before building the vendor image.
#
#   .\fetch_hailo_firmware.ps1                 # 4.24.0, matches the in-kernel driver version
#   .\fetch_hailo_firmware.ps1 -Force          # re-download
param(
    [string]$Version = '4.24.0',
    [string]$Sha256 = '3EBEB209987BB0E484353BE23774D3893908DE84069016C4E37361C871D8433A',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ($Version -ne '4.24.0' -and $Sha256 -eq '3EBEB209987BB0E484353BE23774D3893908DE84069016C4E37361C871D8433A') {
    throw "The default SHA256 only applies to 4.24.0; pass -Sha256 for version $Version."
}

$url = "https://hailo-hailort.s3.eu-west-2.amazonaws.com/Hailo8/$Version/FW/hailo8_fw.$Version.bin"
$destDir = Join-Path $PSScriptRoot '..\proprietary\vendor\firmware\hailo'
$dest = Join-Path $destDir 'hailo8_fw.bin'

New-Item -ItemType Directory -Force $destDir | Out-Null

if ((Test-Path $dest) -and -not $Force) {
    if ((Get-FileHash $dest -Algorithm SHA256).Hash -eq $Sha256) {
        Write-Host "Already present and verified: $dest"
        return
    }
}

$tmp = "$dest.download"
Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
$hash = (Get-FileHash $tmp -Algorithm SHA256).Hash
if ($hash -ne $Sha256) {
    Remove-Item $tmp -Force
    throw "SHA256 mismatch for $url`n expected $Sha256`n actual   $hash"
}
Move-Item $tmp $dest -Force
Write-Host "Firmware $Version written to $dest ($((Get-Item $dest).Length) bytes)"
