$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$stage = Join-Path $PSScriptRoot public
$kit = Join-Path $env:USERPROFILE 'Desktop/RKDevTool_v3.37_for_window/RKDevTool_v3.37_for_window/bin'
$afp = Join-Path $kit 'AFPTool.exe'
$maker = Join-Path $kit 'RKImageMaker.exe'
$loader = Join-Path $PSScriptRoot 'outer/boot.bin'
$payload = Join-Path $stage payload
$name = 'update-xunlei-x1-fnos-beta3-fix1-public.img'
$img = Join-Path $stage $name
$rkaf = Join-Path $stage firmware.rkaf
$outer = Join-Path $stage verify-outer
$inner = Join-Path $stage verify-inner
$assets = Join-Path $stage assets
New-Item -ItemType Directory -Force $outer,$inner,$assets | Out-Null
& $afp -pack $payload $rkaf
& $maker -RK330C $loader $rkaf $img '-os_type:ANDROIDOS'
& $maker -unpack $img $outer
& $afp -unpack (Join-Path $outer firmware.img) $inner
if ((Get-FileHash $loader).Hash -ne (Get-FileHash (Join-Path $outer boot.bin)).Hash) {throw 'Loader mismatch'}
foreach ($part in 'parameter.txt','uboot.img','trust.img','boot.img','rootfs.img') {
    if ((Get-FileHash (Join-Path $payload $part)).Hash -ne (Get-FileHash (Join-Path $inner $part)).Hash) {throw "Mismatch: $part"}
}
$archive = Join-Path $assets "$name.7z"
$sevenZip = (Get-Command 7z).Source
& $sevenZip a -t7z -mx=5 -mmt=4 $archive $img
if ((Get-Item -LiteralPath $archive).Length -ge 2GB) {
    Move-Item -LiteralPath $archive -Destination (Join-Path $stage "$name.7z")
    & $sevenZip a -t7z -mx=5 -mmt=4 '-v1900m' $archive $img
    $archive += '.001'
}
& $sevenZip t $archive
$verify = Join-Path $stage verify-extracted
& $sevenZip x -y "-o$verify" $archive
if ((Get-FileHash $img).Hash -ne (Get-FileHash (Join-Path $verify $name)).Hash) {throw 'Extracted IMG mismatch'}
$deb = 'lshz-3399-dsi-timing_0.2~beta3+fix1_arm64.deb'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot $deb) -Destination $assets
$files = @($img) + @(Get-ChildItem -File $assets | Where-Object Name -ne 'SHA256SUMS.txt' | ForEach-Object FullName)
$files | ForEach-Object {
    $hash = Get-FileHash -LiteralPath $_
    "$($hash.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($_))"
} | Set-Content -Encoding ascii (Join-Path $assets SHA256SUMS.txt)
