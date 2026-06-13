param([switch]$Project)

$srcRoot = Join-Path $PSScriptRoot "skills"
if ($Project) {
    $destRoot = Join-Path (Get-Location) ".claude\skills"
} else {
    $destRoot = Join-Path $env:USERPROFILE ".claude\skills"
}

New-Item -ItemType Directory -Force $destRoot | Out-Null
foreach ($skill in Get-ChildItem -Directory $srcRoot) {
    $dest = Join-Path $destRoot $skill.Name
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Copy-Item -Recurse $skill.FullName $dest
    Write-Host "Installed /$($skill.Name) to $dest"
}

# Install the web_search tool (pi extension) globally so researchers can search.
$extSrc = Join-Path $PSScriptRoot "extensions\web-search"
$extDest = Join-Path $env:USERPROFILE ".pi\agent\extensions\web-search"
if (Test-Path $extSrc) {
    New-Item -ItemType Directory -Force (Split-Path $extDest) | Out-Null
    if (Test-Path $extDest) { Remove-Item -Recurse -Force $extDest }
    Copy-Item -Recurse $extSrc $extDest
    $nm = Join-Path $extDest "node_modules"
    if (Test-Path $nm) { Remove-Item -Recurse -Force $nm }
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        Push-Location $extDest; npm install --omit=dev --silent; Pop-Location
        Write-Host "Installed web_search extension to $extDest"
    } else {
        Write-Host "web_search extension copied to $extDest - run 'npm install' there once npm is available"
    }
}

# Builder: pi pointed at a cheap model (DeepSeek by default).
$pi = Get-Command pi -ErrorAction SilentlyContinue
if ($pi) {
    Write-Host "pi found: $(pi --version)"
} else {
    Write-Host "pi not found - install the builder: npm i -g --ignore-scripts @earendil-works/pi-coding-agent"
}
Write-Host "Set your builder key:  `$env:DEEPSEEK_API_KEY=sk-...   (see skills/architect/dispatch.md to switch models)"
Write-Host "Optional better search: `$env:TAVILY_API_KEY=tvly-...  (else web_search uses keyless DuckDuckGo)"
