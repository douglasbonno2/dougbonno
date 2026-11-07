param(
    [ValidateSet('aplicar', 'preparar')]
    [string]$Acao = 'aplicar'
)

$ErrorActionPreference = 'Stop'
$Serial = 'n7jzceuwof4xeiwk'
$HashBootStock = 'e0b8548be3703338bdff8d141daed234e34fb84e1f26e3f149d30147ce6feacd'
$HashVendorStock = 'e2c8c2674f50179715fb276f6fa6ae35f197c69c2910786120a92a6053a87280'
$HashPlatformStock = '4e6ea0bf2dd6c58448bdee9743ad7e2fdd8bd5b4cb5c7519bcb52e0866763555'
$HashRecoveryStock = '33b9c99aaa0a553e933dac9e93b47b751800e640c3577e11deb66c08a6239c27'
$HashPlatformV17 = 'beabc9a6dc40331d059e32957788746b7c671dbb04a1ffa0d145b20059038ed3'
$HashVendorV17 = '5a8f1c64e159f6b7962ddcdd4de01115fdc2ef9c7b11181ddfae90f9e0a7b3da'
$PlatformV17 = Join-Path $PSScriptRoot 'platform-taiko-linux-v17.lz4'

$RaizRom = Join-Path $env:USERPROFILE 'Downloads\ROM-RedmiPad2'
$Backup = Get-ChildItem -LiteralPath $RaizRom -Directory -Filter 'backup-taiko-*' -ErrorAction Stop |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Backup) { throw "Backup HyperOS nao localizado em $RaizRom" }
$BootStock = Join-Path $Backup.FullName 'boot_a.img'
$VendorStock = Join-Path $Backup.FullName 'vendor_boot_a.img'
$PastaSaida = Join-Path $env:USERPROFILE 'Downloads\Taiko-Ubuntu-Installer'
$VendorV17 = Join-Path $PastaSaida 'vendor_boot_a-ubuntu-v17-stock-base.img'
New-Item -ItemType Directory -Force -Path $PastaSaida | Out-Null

$FastbootCmd = Get-Command fastboot.exe -ErrorAction SilentlyContinue
if (-not $FastbootCmd) { $FastbootCmd = Get-Command fastboot -ErrorAction Stop }
$Fastboot = $FastbootCmd.Source

function Get-HashLower([string]$Arquivo) {
    return (Get-FileHash -LiteralPath $Arquivo -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Align-Up([long]$Valor, [long]$Alinhamento) {
    return [long]([Math]::Floor(($Valor + $Alinhamento - 1) / $Alinhamento) * $Alinhamento)
}

function Get-BytesHash([byte[]]$Dados, [int]$Offset, [int]$Tamanho) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($Dados, $Offset, $Tamanho) }
    finally { $sha.Dispose() }
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Invoke-Checked([string]$Programa, [string[]]$Argumentos) {
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Programa @Argumentos; $codigo = $LASTEXITCODE }
    finally { $ErrorActionPreference = $anterior }
    if ($codigo -ne 0) { throw "Falhou ($codigo): $Programa $($Argumentos -join ' ')" }
}

function Get-Checked([string]$Programa, [string[]]$Argumentos) {
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $saida = & $Programa @Argumentos 2>&1; $codigo = $LASTEXITCODE }
    finally { $ErrorActionPreference = $anterior }
    if ($codigo -ne 0) { throw "Falhou ($codigo): $Programa $($Argumentos -join ' ')`n$($saida -join "`n")" }
    return (($saida -join "`n").Trim())
}

function Test-Fastboot {
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $linhas = & $Fastboot devices 2>$null }
    finally { $ErrorActionPreference = $anterior }
    foreach ($linha in $linhas) {
        $partes = ($linha.ToString().Trim() -split '\s+')
        if ($partes.Count -gt 0 -and $partes[0].ToLowerInvariant() -eq $Serial.ToLowerInvariant()) { return $true }
    }
    return $false
}

function Wait-Fastboot([int]$Segundos = 120) {
    Write-Host 'Aguardando o Taiko no Fastboot...'
    for ($n = 1; $n -le $Segundos; $n++) {
        if (Test-Fastboot) { return }
        if (($n % 15) -eq 0) { Write-Host "  $n s..." }
        Start-Sleep -Seconds 1
    }
    throw 'Fastboot nao reconheceu o Taiko.'
}

function Get-FastbootVar([string]$Nome) {
    $saida = Get-Checked $Fastboot @('-s', $Serial, 'getvar', $Nome)
    $m = [regex]::Match($saida, '(?m)^' + [regex]::Escape($Nome) + ':\s*(\S+)')
    if (-not $m.Success) { throw "Fastboot nao informou $Nome.`n$saida" }
    return $m.Groups[1].Value.Trim()
}

function Assert-StockFiles {
    foreach ($arquivo in @($BootStock, $VendorStock, $PlatformV17)) {
        if (-not (Test-Path -LiteralPath $arquivo)) { throw "Arquivo ausente: $arquivo" }
    }
    if ((Get-HashLower $BootStock) -ne $HashBootStock) { throw 'boot_a do backup nao e o HyperOS original esperado.' }
    if ((Get-HashLower $VendorStock) -ne $HashVendorStock) { throw 'vendor_boot_a do backup nao e o HyperOS original esperado.' }
    if ((Get-HashLower $PlatformV17) -ne $HashPlatformV17) { throw 'Ramdisk Linux V17 incorreto.' }
    if ((Get-Item -LiteralPath $VendorStock).Length -ne 67108864) { throw 'Tamanho do vendor_boot stock incorreto.' }
}

function Build-VendorV17 {
    $platform = [IO.File]::ReadAllBytes($PlatformV17)
    $dados = [IO.File]::ReadAllBytes($VendorStock)
    if ([Text.Encoding]::ASCII.GetString($dados, 0, 8) -ne 'VNDRBOOT') { throw 'Magic vendor_boot incorreto.' }
    if ([BitConverter]::ToUInt32($dados, 8) -ne 4) { throw 'vendor_boot nao usa cabecalho v4.' }
    $pagina = [int][BitConverter]::ToUInt32($dados, 12)
    $ramdiskSize = [int][BitConverter]::ToUInt32($dados, 24)
    $headerSize = [int][BitConverter]::ToUInt32($dados, 2096)
    $dtbSize = [int][BitConverter]::ToUInt32($dados, 2100)
    $tableSize = [int][BitConverter]::ToUInt32($dados, 2112)
    $entryCount = [int][BitConverter]::ToUInt32($dados, 2116)
    $entrySize = [int][BitConverter]::ToUInt32($dados, 2120)
    $bootconfigSize = [int][BitConverter]::ToUInt32($dados, 2124)
    if ($pagina -ne 4096 -or $headerSize -ne 2128 -or $entryCount -ne 2 -or $entrySize -lt 108) {
        throw 'Layout do vendor_boot stock inesperado.'
    }
    $ramdiskStart = [int](Align-Up $headerSize $pagina)
    $dtbStart = [int](Align-Up ($ramdiskStart + $ramdiskSize) $pagina)
    $tableStart = [int](Align-Up ($dtbStart + $dtbSize) $pagina)
    $bootconfigStart = [int](Align-Up ($tableStart + $tableSize) $pagina)
    $entries = @()
    for ($n = 0; $n -lt $entryCount; $n++) {
        $pos = $tableStart + $n * $entrySize
        $entries += [pscustomobject]@{
            Index = $n
            Size = [int][BitConverter]::ToUInt32($dados, $pos)
            Offset = [int][BitConverter]::ToUInt32($dados, $pos + 4)
            Type = [int][BitConverter]::ToUInt32($dados, $pos + 8)
            Name = ([Text.Encoding]::ASCII.GetString($dados, $pos + 12, 32)).Trim([char]0)
            TableBytes = [byte[]]$dados[$pos..($pos + $entrySize - 1)]
        }
    }
    $platformEntry = $entries | Where-Object Type -eq 1 | Select-Object -First 1
    $recoveryEntry = $entries | Where-Object Type -eq 2 | Select-Object -First 1
    if (-not $platformEntry -or -not $recoveryEntry) { throw 'Fragmentos PLATFORM/recovery ausentes.' }
    if ((Get-BytesHash $dados ($ramdiskStart + $platformEntry.Offset) $platformEntry.Size) -ne $HashPlatformStock) {
        throw 'Fragmento PLATFORM nao e o original HyperOS esperado.'
    }
    if ((Get-BytesHash $dados ($ramdiskStart + $recoveryEntry.Offset) $recoveryEntry.Size) -ne $HashRecoveryStock) {
        throw 'Fragmento recovery nao e o original HyperOS esperado.'
    }

    $novoRamdiskSize = $ramdiskSize - $platformEntry.Size + $platform.Length
    $novoDtbStart = [int](Align-Up ($ramdiskStart + $novoRamdiskSize) $pagina)
    $novoTableStart = [int](Align-Up ($novoDtbStart + $dtbSize) $pagina)
    $novoBootconfigStart = [int](Align-Up ($novoTableStart + $tableSize) $pagina)
    $novoDataEnd = [int](Align-Up ($novoBootconfigStart + $bootconfigSize) $pagina)
    if ($novoDataEnd -gt ($dados.Length - 1048576)) { throw 'Imagem V17 nao cabe com margem no vendor_boot.' }

    $novo = [byte[]]$dados.Clone()
    $cursor = 0
    foreach ($item in $entries) {
        if ($item.Type -eq 1) { $conteudo = $platform }
        else { $conteudo = [byte[]]$dados[($ramdiskStart + $item.Offset)..($ramdiskStart + $item.Offset + $item.Size - 1)] }
        [Array]::Copy($conteudo, 0, $novo, $ramdiskStart + $cursor, $conteudo.Length)
        $item.Offset = $cursor
        $item.Size = $conteudo.Length
        $cursor += $conteudo.Length
    }
    if ($cursor -ne $novoRamdiskSize) { throw 'Tamanho reconstruido incorreto.' }
    [BitConverter]::GetBytes([uint32]$novoRamdiskSize).CopyTo($novo, 24)
    [Array]::Copy($dados, $dtbStart, $novo, $novoDtbStart, $dtbSize)
    foreach ($item in $entries) {
        $pos = $novoTableStart + $item.Index * $entrySize
        [Array]::Copy($item.TableBytes, 0, $novo, $pos, $entrySize)
        [BitConverter]::GetBytes([uint32]$item.Size).CopyTo($novo, $pos)
        [BitConverter]::GetBytes([uint32]$item.Offset).CopyTo($novo, $pos + 4)
    }
    [Array]::Copy($dados, $bootconfigStart, $novo, $novoBootconfigStart, $bootconfigSize)
    [IO.File]::WriteAllBytes($VendorV17, $novo)
    if ((Get-HashLower $VendorV17) -ne $HashVendorV17) { throw 'Hash final do vendor_boot V17 divergiu.' }
    Write-Host "IMAGEM V17 VALIDADA: $VendorV17" -ForegroundColor Green
    Write-Host "Recovery HyperOS preservado: $HashRecoveryStock"
    Write-Host 'boot_a permanece original e nao sera gravado.'
}

Assert-StockFiles
Build-VendorV17
if ($Acao -eq 'preparar') { exit 0 }
Wait-Fastboot
if ((Get-FastbootVar 'product') -ne 'taiko') { throw 'Produto Fastboot nao e taiko.' }
if ((Get-FastbootVar 'is-userspace') -ne 'no') { throw 'Use o Fastboot do bootloader.' }
if ((Get-FastbootVar 'unlocked') -ne 'yes') { throw 'Bootloader bloqueado.' }
if ((Get-FastbootVar 'current-slot') -ne 'a') { throw 'Slot atual nao e a.' }
Write-Host 'Gravando somente vendor_boot_a V17; boot_a e recovery HyperOS preservados...'
Invoke-Checked $Fastboot @('-s', $Serial, 'flash', 'vendor_boot_a', $VendorV17)
Write-Host 'Iniciando Ubuntu interno...'
Invoke-Checked $Fastboot @('-s', $Serial, 'reboot')
Write-Host 'V17 APLICADA. O boot_a permaneceu original.' -ForegroundColor Green
