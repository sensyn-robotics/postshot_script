# Debug: Test short path conversion

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Debug: Short Path Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

function Get-ShortPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LongPath
    )

    if (-not (Test-Path $LongPath)) {
        Write-Host "  Path does not exist: $LongPath" -ForegroundColor Red
        return $LongPath
    }

    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        $item = Get-Item -LiteralPath $LongPath
        if ($item.PSIsContainer) {
            $shortPath = $fso.GetFolder($LongPath).ShortPath
        } else {
            $shortPath = $fso.GetFile($LongPath).ShortPath
        }
        return $shortPath
    }
    catch {
        Write-Host "  ERROR getting short path: $_" -ForegroundColor Red
        return $LongPath
    }
}

# Test with each scene
$scenes = Get-ChildItem "C:\postshot_test_data" -Directory

foreach ($scene in $scenes) {
    Write-Host ""
    Write-Host "Scene: $($scene.Name)" -ForegroundColor Yellow
    Write-Host "  Long path: $($scene.FullName)" -ForegroundColor Gray

    $shortPath = Get-ShortPath -LongPath $scene.FullName
    Write-Host "  Short path: $shortPath" -ForegroundColor Green

    # Test a deeper path
    $imagesPath = Join-Path $scene.FullName "output\images"
    if (Test-Path $imagesPath) {
        $shortImagesPath = Get-ShortPath -LongPath $imagesPath
        Write-Host "  Images short: $shortImagesPath" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
