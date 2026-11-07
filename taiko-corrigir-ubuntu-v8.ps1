param(
    [ValidateSet('aplicar', 'status')]
    [string]$Acao = 'aplicar'
)

$ErrorActionPreference = 'Stop'
$Serial = 'n7jzceuwof4xeiwk'
$TamanhoParticao = 67108864
$HashBootPermitido = '1a7ce84bc588754a15f39366727e86cc9743ca7704d7aba254f29f2d2ac0fc36'
$HashVendorPermitido = '549b34688599ed728e6f283b8d0ba57844162aefa974c299da039e8ba7d5bf1b'
$HashRecoveryPermitido = '118e7f36d87feb73168aa4821fb09e544e284c502e7e5f7ff56e403555920070'
$HashPlatformOriginal = 'ea2afb8097f95b8f5b97b9ce6ba7d70aaaeb4a3b0b112a2a219401ffe64ddf04'
$HashOverlayV8 = 'fed067917df4cb0d43f95b4d5ccdc624adc74ec66533c39bc1ac923c6783467f'
$OverlayV8 = Join-Path $PSScriptRoot 'taiko-linux-v8-overlay.lz4'
$HashBootV1 = '1a7ce84bc588754a15f39366727e86cc9743ca7704d7aba254f29f2d2ac0fc36'
$HashVendorV1 = '549b34688599ed728e6f283b8d0ba57844162aefa974c299da039e8ba7d5bf1b'
$Pasta = Join-Path $PSScriptRoot 'Taiko-Ubuntu-Installer'
$BootOriginal = Join-Path $Pasta 'boot_a-original.img'
$VendorOriginal = Join-Path $Pasta 'vendor_boot_a-original.img'
$BootProbeV8 = Join-Path $Pasta 'boot_a-ubuntu-v8.img'
$VendorProbeV8 = Join-Path $Pasta 'vendor_boot_a-ubuntu-v8.img'

New-Item -ItemType Directory -Force -Path $Pasta | Out-Null

$AdbCmd = Get-Command adb.exe -ErrorAction SilentlyContinue
if (-not $AdbCmd) { $AdbCmd = Get-Command adb -ErrorAction Stop }
$FastbootCmd = Get-Command fastboot.exe -ErrorAction SilentlyContinue
if (-not $FastbootCmd) { $FastbootCmd = Get-Command fastboot -ErrorAction Stop }
$Adb = $AdbCmd.Source
$Fastboot = $FastbootCmd.Source

function Invoke-Checked {
    param([string]$Programa, [string[]]$Argumentos)
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Programa @Argumentos; $codigo = $LASTEXITCODE }
    finally { $ErrorActionPreference = $anterior }
    if ($codigo -ne 0) { throw "Falhou ($codigo): $Programa $($Argumentos -join ' ')" }
}

function Get-Checked {
    param([string]$Programa, [string[]]$Argumentos)
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $saida = & $Programa @Argumentos 2>&1; $codigo = $LASTEXITCODE }
    finally { $ErrorActionPreference = $anterior }
    if ($codigo -ne 0) { throw "Falhou ($codigo): $Programa $($Argumentos -join ' ')`n$($saida -join "`n")" }
    return (($saida -join "`n").Trim())
}

function Get-HashLower {
    param([string]$Arquivo)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Arquivo).Hash.ToLowerInvariant()
}

function Get-BytesHash {
    param([byte[]]$Dados, [int]$Offset, [int]$Tamanho)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($Dados, $Offset, $Tamanho) }
    finally { $sha.Dispose() }
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Align-Up {
    param([long]$Valor, [long]$Alinhamento)
    return [long]([Math]::Floor(($Valor + $Alinhamento - 1) / $Alinhamento) * $Alinhamento)
}

function Assert-PartitionImage {
    param([string]$Arquivo, [string]$Magic)
    if (-not (Test-Path -LiteralPath $Arquivo)) { throw "Arquivo ausente: $Arquivo" }
    if ((Get-Item -LiteralPath $Arquivo).Length -ne $TamanhoParticao) { throw "Tamanho incorreto: $Arquivo" }
    $stream = [IO.File]::OpenRead($Arquivo)
    try {
        $cabecalho = New-Object byte[] $Magic.Length
        if ($stream.Read($cabecalho, 0, $cabecalho.Length) -ne $cabecalho.Length) { throw 'Cabecalho incompleto.' }
    }
    finally { $stream.Dispose() }
    if ([Text.Encoding]::ASCII.GetString($cabecalho) -ne $Magic) { throw "Magic incorreto em $Arquivo" }
}

function Test-Adb {
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $saida = & $Adb -s $Serial get-state 2>$null; $codigo = $LASTEXITCODE }
    finally { $ErrorActionPreference = $anterior }
    $estado = (($saida -join '').Trim())
    return ($codigo -eq 0 -and ($estado -eq 'device' -or $estado -eq 'recovery'))
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

function Wait-Fastboot {
    param([int]$Segundos = 60)
    for ($n = 1; $n -le $Segundos; $n++) {
        if (Test-Fastboot) { return }
        Start-Sleep -Seconds 1
    }
    throw 'Fastboot nao reconheceu o taiko.'
}

function Wait-AdbBoot {
    param([int]$Segundos = 180)
    Write-Host "Aguardando Android/ADB por ate $Segundos segundos..."
    for ($n = 1; $n -le $Segundos; $n++) {
        if (Test-Adb) {
            $anterior = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try { $completo = & $Adb -s $Serial shell getprop sys.boot_completed 2>$null; $codigo = $LASTEXITCODE }
            finally { $ErrorActionPreference = $anterior }
            if ($codigo -eq 0 -and (($completo -join '').Trim() -eq '1')) { return }
        }
        if (($n % 15) -eq 0) { Write-Host "  $n s..." }
        Start-Sleep -Seconds 1
    }
    throw 'Android nao retornou. Entre manualmente no Fastboot e use -Acao restaurar.'
}

function Get-FastbootVar {
    param([string]$Nome)
    $saida = Get-Checked $Fastboot @('-s', $Serial, 'getvar', $Nome)
    $m = [regex]::Match($saida, '(?m)^' + [regex]::Escape($Nome) + ':\s*(\S+)')
    if (-not $m.Success) { throw "Fastboot nao informou $Nome.`n$saida" }
    return $m.Groups[1].Value.Trim()
}

function Enter-Fastboot {
    if (Test-Fastboot) { return }
    if (Test-Adb) {
        Invoke-Checked $Adb @('-s', $Serial, 'reboot', 'bootloader')
        Wait-Fastboot
        return
    }
    Write-Host 'Coloque o tablet manualmente no Fastboot.'
    Wait-Fastboot 90
}

function Assert-FastbootTarget {
    if ((Get-FastbootVar 'product') -ne 'taiko') { throw 'Produto Fastboot nao e taiko.' }
    if ((Get-FastbootVar 'is-userspace') -ne 'no') { throw 'Use o Fastboot do bootloader, nao FastbootD.' }
    if ((Get-FastbootVar 'unlocked') -ne 'yes') { throw 'Bootloader bloqueado.' }
    if ((Get-FastbootVar 'current-slot') -ne 'a') { throw 'Teste permitido somente no slot a.' }
}

function Get-RootShell {
    param([string]$Comando)
    return Get-Checked $Adb @('-s', $Serial, 'shell', '-n', "su -mm -c '$Comando'")
}

function Assert-AndroidTarget {
    if (-not (Test-Adb)) { throw 'Conecte o taiko no Android com depuracao USB autorizada.' }
    $produto = (Get-Checked $Adb @('-s', $Serial, 'shell', 'getprop', 'ro.product.device')).Trim()
    if ($produto -ne 'taiko') { throw "Produto ADB incorreto: $produto" }
    $slot = Get-RootShell 'grep androidboot.slot_suffix /proc/bootconfig'
    if ($slot -notmatch '"?_a"?\s*$') { throw "Slot inesperado: $slot" }
    $flags = (Get-RootShell 'od -An -tx1 -j120 -N4 /dev/block/by-name/vbmeta_a').ToLowerInvariant() -replace '\s', ''
    if ($flags -ne '00000003') { throw "Flags AVB inesperadas: $flags" }
}

function Pull-Partition {
    param([string]$Particao, [string]$Destino)
    Get-RootShell "dd if=/dev/block/by-name/$Particao of=/data/local/tmp/$Particao.img bs=4M 2>/dev/null && chmod 0644 /data/local/tmp/$Particao.img" | Out-Null
    Invoke-Checked $Adb @('-s', $Serial, 'pull', "/data/local/tmp/$Particao.img", $Destino)
}

function Build-BootProbeV8 {
    Assert-PartitionImage $BootOriginal 'ANDROID!'
    $dados = [IO.File]::ReadAllBytes($BootOriginal)
    if ([BitConverter]::ToUInt32($dados, 40) -ne 4) { throw 'boot_a nao usa cabecalho v4.' }
    # LK reads the v4 cmdline at offset 44 and also uses the legacy view at
    # offset 64. Keep the actionable parameter at that proven legacy offset.
    $cmd = [Text.Encoding]::ASCII.GetBytes('loglevel=8          rdinit=/p')
    [Array]::Clear($dados, 44, 1536)
    [Array]::Copy($cmd, 0, $dados, 44, $cmd.Length)
    [IO.File]::WriteAllBytes($BootProbeV8, $dados)
    Assert-PartitionImage $BootProbeV8 'ANDROID!'
    if ([Text.Encoding]::ASCII.GetString($dados, 44, $cmd.Length) -ne 'loglevel=8          rdinit=/p') { throw 'Cmdline Ubuntu incorreta.' }
}

function Build-VendorProbeV8 {
    Assert-PartitionImage $VendorOriginal 'VNDRBOOT'
    if (-not (Test-Path -LiteralPath $OverlayV8)) { throw "Overlay v8 ausente: $OverlayV8" }
    if ((Get-HashLower $OverlayV8) -ne $HashOverlayV8) { throw 'Hash do overlay v8 incorreto.' }
    $overlay = [IO.File]::ReadAllBytes($OverlayV8)
    $dados = [IO.File]::ReadAllBytes($VendorOriginal)
    if ([BitConverter]::ToUInt32($dados, 8) -ne 4) { throw 'vendor_boot_a nao usa cabecalho v4.' }
    $pagina = [int][BitConverter]::ToUInt32($dados, 12)
    $ramdiskSize = [int][BitConverter]::ToUInt32($dados, 24)
    $headerSize = [int][BitConverter]::ToUInt32($dados, 2096)
    $dtbSize = [int][BitConverter]::ToUInt32($dados, 2100)
    $tableSize = [int][BitConverter]::ToUInt32($dados, 2112)
    $entryCount = [int][BitConverter]::ToUInt32($dados, 2116)
    $entrySize = [int][BitConverter]::ToUInt32($dados, 2120)
    $bootconfigSize = [int][BitConverter]::ToUInt32($dados, 2124)
    if ($pagina -ne 4096 -or $headerSize -ne 2128 -or $entrySize -lt 108 -or $entryCount -lt 2) { throw 'Layout vendor_boot inesperado.' }
    $ramdiskStart = [int](Align-Up $headerSize $pagina)
    $dtbStart = [int](Align-Up ($ramdiskStart + $ramdiskSize) $pagina)
    $tableStart = [int](Align-Up ($dtbStart + $dtbSize) $pagina)
    $bootconfigStart = [int](Align-Up ($tableStart + $tableSize) $pagina)
    $dataEnd = [int](Align-Up ($bootconfigStart + $bootconfigSize) $pagina)
    $entries = @()
    $platformIndex = -1
    $recoveryIndex = -1
    for ($n = 0; $n -lt $entryCount; $n++) {
        $pos = $tableStart + $n * $entrySize
        $item = [pscustomobject]@{
            Index = $n
            Size = [int][BitConverter]::ToUInt32($dados, $pos)
            Offset = [int][BitConverter]::ToUInt32($dados, $pos + 4)
            Type = [int][BitConverter]::ToUInt32($dados, $pos + 8)
            Name = ([Text.Encoding]::ASCII.GetString($dados, $pos + 12, 32)).Trim([char]0)
            TableBytes = $dados[$pos..($pos + $entrySize - 1)]
        }
        if ($item.Offset + $item.Size -gt $ramdiskSize) { throw "Entrada $n fora dos limites." }
        if ($item.Type -eq 1 -and $platformIndex -lt 0) { $platformIndex = $n }
        if ($item.Type -eq 2 -and $recoveryIndex -lt 0) { $recoveryIndex = $n }
        $entries += $item
    }
    if ($platformIndex -lt 0 -or $recoveryIndex -lt 0) { throw 'Fragmentos platform/recovery nao encontrados.' }
    $platOriginal = $entries[$platformIndex]
    $platOriginalSize = $platOriginal.Size
    $hashPlatOriginal = Get-BytesHash $dados ($ramdiskStart + $platOriginal.Offset) $platOriginal.Size
    if ($hashPlatOriginal -ne $HashPlatformOriginal) { throw "Platform original inesperado: $hashPlatOriginal" }
    $rec = $entries[$recoveryIndex]
    $hashRecovery = Get-BytesHash $dados ($ramdiskStart + $rec.Offset) $rec.Size
    $script:HashRecoveryAtual = $hashRecovery
    if ($hashRecovery -ne $HashRecoveryPermitido) { throw "TWRP inesperado: $hashRecovery" }
    $novoRamdiskSize = $ramdiskSize + $overlay.Length
    $novoDtbStart = [int](Align-Up ($ramdiskStart + $novoRamdiskSize) $pagina)
    $novoTableStart = [int](Align-Up ($novoDtbStart + $dtbSize) $pagina)
    $novoBootconfigStart = [int](Align-Up ($novoTableStart + $tableSize) $pagina)
    $novoDataEnd = [int](Align-Up ($novoBootconfigStart + $bootconfigSize) $pagina)
    if ($novoDataEnd -ne $dataEnd) { throw 'Overlay v8 nao cabe na folga validada do vendor_boot.' }
    $novo = [byte[]]$dados.Clone()
    $cursor = 0
    foreach ($item in $entries) {
        [Array]::Copy($dados, $ramdiskStart + $item.Offset, $novo, $ramdiskStart + $cursor, $item.Size)
        $novoSize = $item.Size
        if ($item.Index -eq $platformIndex) {
            [Array]::Copy($overlay, 0, $novo, $ramdiskStart + $cursor + $item.Size, $overlay.Length)
            $novoSize += $overlay.Length
        }
        $item.Offset = $cursor
        $item.Size = $novoSize
        $cursor += $novoSize
    }
    if ($cursor -ne $novoRamdiskSize) { throw 'Tamanho reconstruido incorreto.' }
    [BitConverter]::GetBytes([uint32]$novoRamdiskSize).CopyTo($novo, 24)
    [Array]::Copy($dados, $dtbStart, $novo, $novoDtbStart, $dtbSize)
    for ($n = 0; $n -lt $entryCount; $n++) {
        $item = $entries[$n]
        $pos = $novoTableStart + $n * $entrySize
        [Array]::Copy($item.TableBytes, 0, $novo, $pos, $entrySize)
        [BitConverter]::GetBytes([uint32]$item.Size).CopyTo($novo, $pos)
        [BitConverter]::GetBytes([uint32]$item.Offset).CopyTo($novo, $pos + 4)
    }
    [Array]::Copy($dados, $bootconfigStart, $novo, $novoBootconfigStart, $bootconfigSize)
    $platNovo = $entries[$platformIndex]
    if ((Get-BytesHash $novo ($ramdiskStart + $platNovo.Offset) $platOriginalSize) -ne $HashPlatformOriginal) { throw 'Platform original mudou.' }
    $overlayOffset = $ramdiskStart + $platNovo.Offset + $platOriginalSize
    if ((Get-BytesHash $novo $overlayOffset $overlay.Length) -ne $HashOverlayV8) { throw 'Overlay v8 nao foi preservado.' }
    $recNovo = $entries[$recoveryIndex]
    if ((Get-BytesHash $novo ($ramdiskStart + $recNovo.Offset) $recNovo.Size) -ne $hashRecovery) { throw 'TWRP mudou na reconstrucao.' }
    [IO.File]::WriteAllBytes($VendorProbeV8, $novo)
    Assert-PartitionImage $VendorProbeV8 'VNDRBOOT'
}

function Assert-RecoveryState {
    if (-not (Test-Adb)) { throw 'TWRP nao esta conectado no ADB.' }
    $produto = (Get-Checked $Adb @('-s', $Serial, 'shell', 'getprop', 'ro.product.device')).Trim()
    if ($produto -and $produto -ne 'taiko') { throw "Produto inesperado: $produto" }
    $bootInfo = Get-Checked $Adb @('-s', $Serial, 'shell', 'cat', '/sys/class/block/sdc32/uevent')
    $vendorInfo = Get-Checked $Adb @('-s', $Serial, 'shell', 'cat', '/sys/class/block/sdc33/uevent')
    if ($bootInfo -notmatch '(?m)^PARTNAME=boot_a\s*$' -or $vendorInfo -notmatch '(?m)^PARTNAME=vendor_boot_a\s*$') {
        throw "Mapeamento fisico inesperado.`nSdc32:`n$bootInfo`nSdc33:`n$vendorInfo"
    }
    $bootDev = ((Get-Checked $Adb @('-s', $Serial, 'shell', 'cat', '/sys/class/block/sdc32/dev')).Trim() -split ':')
    $vendorDev = ((Get-Checked $Adb @('-s', $Serial, 'shell', 'cat', '/sys/class/block/sdc33/dev')).Trim() -split ':')
    if ($bootDev.Count -ne 2 -or $vendorDev.Count -ne 2) { throw 'Major/minor das particoes nao encontrado.' }
    Invoke-Checked $Adb @('-s', $Serial, 'shell', 'rm', '-f', '/tmp/taiko-boot_a', '/tmp/taiko-vendor_boot_a')
    Invoke-Checked $Adb @('-s', $Serial, 'shell', 'mknod', '/tmp/taiko-boot_a', 'b', $bootDev[0], $bootDev[1])
    Invoke-Checked $Adb @('-s', $Serial, 'shell', 'mknod', '/tmp/taiko-vendor_boot_a', 'b', $vendorDev[0], $vendorDev[1])
    $hashes = Get-Checked $Adb @('-s', $Serial, 'shell', 'sha256sum', '/tmp/taiko-boot_a', '/tmp/taiko-vendor_boot_a')
    if ($hashes -notmatch $HashBootV1 -or $hashes -notmatch $HashVendorV1) {
        throw "boot/vendor atuais nao sao os backups originais esperados.`n$hashes"
    }
    $release = Get-Checked $Adb @('-s', $Serial, 'shell', 'cat', '/data/etc/taiko-image-release')
    if ($release -notmatch 'TAIKO_IMAGE=ubuntu-24.04-arm64') { throw 'Ubuntu nao esta montado em /data.' }
    Write-Host 'TWRP, Ubuntu e imagens originais confirmados.'
}

function Prepare-V8 {
    Assert-PartitionImage $BootOriginal 'ANDROID!'
    Assert-PartitionImage $VendorOriginal 'VNDRBOOT'
    $hashBoot = Get-HashLower $BootOriginal
    $hashVendor = Get-HashLower $VendorOriginal
    if ($hashBoot -ne $HashBootPermitido) { throw "Backup boot_a inesperado: $hashBoot" }
    if ($hashVendor -ne $HashVendorPermitido) { throw "Backup vendor_boot_a inesperado: $hashVendor" }
    Build-BootProbeV8
    Build-VendorProbeV8
    if ($HashRecoveryAtual -ne $HashRecoveryPermitido) { throw "Fragmento TWRP mudou: $HashRecoveryAtual" }
    $hashBootV8 = Get-HashLower $BootProbeV8
    $hashVendorV8 = Get-HashLower $VendorProbeV8
    @(
        "$hashBoot  boot_a-original.img",
        "$hashVendor  vendor_boot_a-original.img",
        "$hashBootV8  boot_a-ubuntu-v8.img",
        "$hashVendorV8  vendor_boot_a-ubuntu-v8.img",
        "$HashRecoveryAtual  recovery-fragment-preservado"
    ) | Set-Content -Encoding ASCII (Join-Path $Pasta 'IMAGENS-V8-SHA256.txt')
    Write-Host "boot Ubuntu v8:   $hashBootV8"
    Write-Host "vendor Ubuntu v8: $hashVendorV8"
    Write-Host "TWRP preservado:  $HashRecoveryAtual"
}

function Show-Status {
    if (Test-Adb) {
        Write-Host (Get-Checked $Adb @('-s', $Serial, 'shell', 'sha256sum', '/tmp/taiko-boot_a', '/tmp/taiko-vendor_boot_a'))
    } elseif (Test-Fastboot) { Write-Host 'Taiko no Fastboot.' }
    else { Write-Host 'Taiko nao detectado.' }
}

if ($Acao -eq 'status') { Show-Status; exit 0 }
Assert-RecoveryState
Prepare-V8
Enter-Fastboot
Assert-FastbootTarget
Write-Host 'Gravando somente vendor_boot_a v8 integrado; TWRP preservado...'
Invoke-Checked $Fastboot @('-s', $Serial, 'flash', 'vendor_boot_a', $VendorProbeV8)
Write-Host 'Confirmando boot_a v8 com rdinit=/p...'
Invoke-Checked $Fastboot @('-s', $Serial, 'flash', 'boot_a', $BootProbeV8)
Write-Host 'Reiniciando no Ubuntu interno; userdata nao foi alterada...'
Invoke-Checked $Fastboot @('-s', $Serial, 'reboot')
Write-Host 'CORRECAO V8 APLICADA.' -ForegroundColor Green
