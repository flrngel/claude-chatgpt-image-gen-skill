<#
.SYNOPSIS
  Wait for the new file that appeared in the OS Downloads folder after clicking
  ChatGPT's image "Download" button, then move it to the caller's target
  directory (optionally renaming it) and print the final absolute path.

.DESCRIPTION
  Must be called AFTER snapshot-downloads.ps1 (same $SnapshotPath) and AFTER the
  browser-side click on the Download button. Detects the new file by diffing the
  Downloads folder's filename list against the snapshot -- NOT by watching
  network requests (ChatGPT's download is a client-side blob save with zero
  network activity) and NOT by timestamp alone. Confirms the file is fully
  written by checking its size is stable across two reads 0.5s apart, and skips
  any lingering .crdownload temp file.

.PARAMETER SnapshotPath
  Must match the SnapshotPath used by snapshot-downloads.ps1 for this call.

.PARAMETER DestDir
  Target directory to move the downloaded file into. Created if missing.

.PARAMETER DestFileName
  Optional final filename (extension inferred from the source file if omitted).
  If a file with that name already exists in DestDir, a numeric suffix is
  appended rather than overwriting.

.PARAMETER TimeoutSeconds
  How long to wait for a new stable file before giving up. Default 30s -- the
  download itself is near-instant (client-side blob save), this just covers
  polling slack.

.OUTPUTS
  Prints the final absolute path of the moved file on success. Writes a
  terminating error and exits 1 if no new stable file showed up in time.
#>
param(
    [Parameter(Mandatory = $true)][string]$SnapshotPath,
    [Parameter(Mandatory = $true)][string]$DestDir,
    [string]$DestFileName,
    [int]$TimeoutSeconds = 30,
    # Override for unit testing against a throwaway folder instead of the real
    # Downloads folder. Leave unset in normal skill usage.
    [string]$DownloadsPath
)

if (-not $DownloadsPath) {
    $DownloadsPath = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path
}
$before = @(Get-Content -Path $SnapshotPath -ErrorAction SilentlyContinue)

if (-not (Test-Path $DestDir)) {
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$stableFile = $null

while ((Get-Date) -lt $deadline) {
    $after = Get-ChildItem -Path $DownloadsPath -File
    $candidates = $after | Where-Object {
        ($before -notcontains $_.Name) -and ($_.Extension -ne '.crdownload')
    }

    if ($candidates) {
        $candidate = $candidates | Sort-Object CreationTime -Descending | Select-Object -First 1
        $size1 = $candidate.Length
        Start-Sleep -Milliseconds 500
        $candidate.Refresh()
        if ((Test-Path $candidate.FullName) -and $candidate.Length -eq $size1 -and $size1 -gt 0) {
            $stableFile = $candidate
            break
        }
    }

    Start-Sleep -Milliseconds 500
}

if (-not $stableFile) {
    Write-Error "No new stable download detected within $TimeoutSeconds second(s) in '$DownloadsPath'."
    exit 1
}

$ext = $stableFile.Extension
if (-not $DestFileName) {
    $DestFileName = $stableFile.Name
} elseif (-not [System.IO.Path]::HasExtension($DestFileName)) {
    $DestFileName = "$DestFileName$ext"
}

$destPath = Join-Path $DestDir $DestFileName
$finalPath = $destPath
$counter = 1
while (Test-Path $finalPath) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($destPath)
    $finalPath = Join-Path $DestDir "${baseName}_$counter$ext"
    $counter++
}

Move-Item -Path $stableFile.FullName -Destination $finalPath
Write-Output $finalPath
