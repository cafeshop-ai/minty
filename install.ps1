$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRef = if ($env:MINTY_REF) { $env:MINTY_REF } else { "main" }
$baseUrl = if ($env:MINTY_BASE_URL) {
    $env:MINTY_BASE_URL.TrimEnd("/")
} else {
    "https://raw.githubusercontent.com/cafeshop-ai/minty/$repoRef"
}
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$target = Join-Path (Join-Path $codexHome "pets") "minty"
$downloadDir = Join-Path ([System.IO.Path]::GetTempPath()) ("minty-install-" + [guid]::NewGuid().ToString("N"))
$pendingFiles = [System.Collections.Generic.List[string]]::new()
$assets = @("pet.json", "spritesheet.webp")

try {
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

    foreach ($file in @($assets + "checksums.sha256")) {
        $uri = "$baseUrl/$file"
        $output = Join-Path $downloadDir $file
        Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $output
    }

    $expectedHashes = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $downloadDir "checksums.sha256")) {
        if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
            throw "Invalid checksum manifest line: $line"
        }
        $expectedHashes[$Matches[2].Trim()] = $Matches[1].ToLowerInvariant()
    }

    foreach ($file in $assets) {
        if (-not $expectedHashes.ContainsKey($file)) {
            throw "Missing checksum for $file"
        }
        $actual = (Get-FileHash -LiteralPath (Join-Path $downloadDir $file) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expectedHashes[$file]) {
            throw "Checksum mismatch for $file"
        }
    }

    $pet = Get-Content -LiteralPath (Join-Path $downloadDir "pet.json") -Raw | ConvertFrom-Json
    if ($pet.id -ne "minty" -or [int]$pet.spriteVersionNumber -ne 2 -or $pet.spritesheetPath -ne "spritesheet.webp") {
        throw "Downloaded pet.json does not describe the Minty v2 pet"
    }

    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $installId = [guid]::NewGuid().ToString("N")
    foreach ($file in $assets) {
        $pending = Join-Path $target (".$file.$installId.tmp")
        Copy-Item -LiteralPath (Join-Path $downloadDir $file) -Destination $pending -Force
        $pendingFiles.Add($pending)
    }
    foreach ($file in $assets) {
        $pending = $pendingFiles | Where-Object { $_ -like "*.$file.$installId.tmp" }
        Move-Item -LiteralPath $pending -Destination (Join-Path $target $file) -Force
    }

    Write-Host "Minty installed to $target"
    Write-Host "Open Codex Settings > Pets, refresh the list, and select Minty."
} finally {
    foreach ($pending in $pendingFiles) {
        if (Test-Path -LiteralPath $pending) {
            Remove-Item -LiteralPath $pending -Force
        }
    }
    if (Test-Path -LiteralPath $downloadDir) {
        Remove-Item -LiteralPath $downloadDir -Recurse -Force
    }
}
