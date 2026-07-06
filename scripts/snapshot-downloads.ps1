<#
.SYNOPSIS
  Snapshot the current filenames in the OS Downloads folder, before triggering a
  ChatGPT image download. Used together with capture-download.ps1 to detect the
  new file by diffing filenames (network-request-based detection does not work:
  the ChatGPT "Download" button produces zero network requests, it's a pure
  client-side blob save).

.PARAMETER SnapshotPath
  Where to write the snapshot. Defaults to a fixed temp file so the paired
  capture-download.ps1 call can find it without extra plumbing.

.OUTPUTS
  Prints the resolved Downloads folder path (so the caller can log it), and
  writes the filename list to SnapshotPath.
#>
param(
    [string]$SnapshotPath = "$env:TEMP\chatgpt-image-gen-downloads-snapshot.txt",
    # Override for unit testing against a throwaway folder instead of the real
    # Downloads folder. Leave unset in normal skill usage.
    [string]$DownloadsPath
)

if (-not $DownloadsPath) {
    $DownloadsPath = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path
}

Get-ChildItem -Path $DownloadsPath -File | Select-Object -ExpandProperty Name |
    Out-File -FilePath $SnapshotPath -Encoding utf8

Write-Output $DownloadsPath
