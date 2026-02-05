# Analyze PLY file quality
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName
$plyFile = "$scene1\output_simple_radial\scene.ply"
$python = "C:\Users\共通パソコンsfmPC⑦\AppData\Local\Programs\Python\Python311\python.exe"

Write-Host "=== PLY File Analysis ==="
Write-Host "File: $plyFile"
Write-Host ""

# Check file size
$sizeMB = [math]::Round((Get-Item $plyFile).Length / 1MB, 1)
Write-Host "File size: $sizeMB MB"
Write-Host ""

# Read PLY header
Write-Host "=== PLY Header ==="
$reader = [System.IO.StreamReader]::new($plyFile)
$lineCount = 0
while ($lineCount -lt 20 -and -not $reader.EndOfStream) {
    $line = $reader.ReadLine()
    Write-Host $line
    if ($line -eq "end_header") { break }
    $lineCount++
}
$reader.Close()
