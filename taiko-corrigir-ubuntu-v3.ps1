param(
    [ValidateSet('aplicar', 'status')]
    [string]$Acao = 'aplicar'
)

$ErrorActionPreference = 'Stop'
$Serial = 'n7jzceuwof4xeiwk'
$TamanhoParticao = 67108864
$HashBootPermitido = '1a7ce84bc588754a15f39366727e86cc9743ca7704d7aba254f29f2d2ac0fc36'
$OverlayBase64 = 'AiFMGJ4DAAByMDcwNzAxMAEAAQgAXzgxZTgwAQADGTEOAE81YWIwAQATFDIJAPgGcAAjIS9zeXN0ZW0vYmluL3NoClQ9EQDxKnRveWJveApsb2coKXsgZWNobyAiPDY+VEFJS09fTElOVVhfVjI6ICQqIiA+IC9kZXYva21zZyAyPgwAwG51bGw7IH0KZmFpbEAAoGxvZyAiRkFMSEEyAMA7IGV4ZWMgL2luaXQmAPIBJFQgbW91bnQgLXQgcHJvYwUAES8GAAdRAIkgfHwgdHJ1ZTAAU3N5c2ZzBgAAwAAPMQAOhmRldnRtcGZzCQAAMAAPNwAGcmtkaXIgLXDjAMxwdHMgL25ld3Jvb3RVAAAcAAMHAAUsAA9VAAEBCwHwK1BJRDEgY29uZmlybWFkbyIKd2hpbGUgSUZTPSByZWFkIC1yIG07IGRvCiAgWyAtbiAiJG0iIF0gfHw2AFF0aW51ZRoAARcA+AI9IG10a193ZHQua28gXSAmJiQA0W49JHttJS5rb30KICCzAPsEZHByb2JlIC1kIC8gLXEgIiRuIqkAACgA8AZpbnNtb2QgIi9saWIvbW9kdWxlcy9uAA/UAAEBpQARZYAB8gMvY2xhc3MvYmxvY2svc2RjNzOTANlicmVhawpkb25lIDwgVQADCABSLmxvYWQeAQESABBvTwHzDyBhcm1hemVuYW1lbnRvIGNhcnJlZ2Fkb3MiCmk9MDYBslsgJGkgLWx0IDIwbABiWyAhIC1ihwEDgwAATAHAIGk9JCgoaSsxKSk74wCQc2xlZXAgMTsglgAsClszAADeAADAAiIgIhEAiWF1c2VudGUi+QH4A2V4dDQgLW8gcncsbm9hdGltZUQABCwCDDUBAlcAAkUAAEIAECJ+ABV4LwAgL3OCAwAeAwmGAAGdAxZkiAABLAGxVWJ1bnR1IG1vbnRJAgm0AgRQAAJQAwVeABZ5xgIB/AIFDQAicnV3AFdyYW1mc+gAay1tb3ZlIEcAD58DEAM4AAlxAA+kAw8DNgAJmgAOowMNNgBGYmluZHIBD3sBCwAsADciCmMwAAUbACFjZEUBYXBpdm90XxsAKS4gGAEPUgADATAAISIKKQUeJykFAfIEc3V0YW5kbyDJAR8nOQUFEgoeBQUFAikKABwGETIFAD8xODAcBhIOAQAMKAAEPAYUORkABJQAGgB4AB8zUAAUDwEAHQW8Br9UUkFJTEVSISEhAAEA21AAAAAAAA=='
$HashOverlay = '333ce690c3dc58ad51a2b81641fcca8add04ea72dc10c2fbc3c8927b1b6fdf84'
$HashVendorPermitido = '549b34688599ed728e6f283b8d0ba57844162aefa974c299da039e8ba7d5bf1b'
$HashRecoveryPermitido = '118e7f36d87feb73168aa4821fb09e544e284c502e7e5f7ff56e403555920070'
$HashPlatformOriginal = 'ea2afb8097f95b8f5b97b9ce6ba7d70aaaeb4a3b0b112a2a219401ffe64ddf04'
$HashPlatformV3 = 'b441ba9bac03fded03202dfe7ca3812a47d480228f12dd6e8b82ed9f2fe24d14'
$PlatformV3 = Join-Path $PSScriptRoot 'platform-taiko-linux-v3.lz4'
$HashBootV1 = '72ce5c80691d05e84350fc81e72befc1d8d4a0ee40ae4daf2bdc7a02a3dc4c24'
$HashVendorV1 = 'f88a938e52ddd99e6dfac7124cb33bcaae1ee9efa3a838e21625d949072bd2f7'
$Pasta = Join-Path $PSScriptRoot 'Taiko-Ubuntu-Installer'
$BootOriginal = Join-Path $Pasta 'boot_a-original.img'
$VendorOriginal = Join-Path $Pasta 'vendor_boot_a-original.img'
$BootProbe = Join-Path $Pasta 'boot_a-ubuntu-v3.img'
$VendorProbe = Join-Path $Pasta 'vendor_boot_a-ubuntu-v3.img'

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

function Build-BootProbe {
    Assert-PartitionImage $BootOriginal 'ANDROID!'
    $dados = [IO.File]::ReadAllBytes($BootOriginal)
    if ([BitConverter]::ToUInt32($dados, 40) -ne 4) { throw 'boot_a nao usa cabecalho v4.' }
    # LK reads the v4 cmdline at offset 44 and also uses the legacy view at
    # offset 64. Keep the actionable parameter at that proven legacy offset.
    $cmd = [Text.Encoding]::ASCII.GetBytes('loglevel=8          rdinit=/p')
    [Array]::Clear($dados, 44, 1536)
    [Array]::Copy($cmd, 0, $dados, 44, $cmd.Length)
    [IO.File]::WriteAllBytes($BootProbe, $dados)
    Assert-PartitionImage $BootProbe 'ANDROID!'
    if ([Text.Encoding]::ASCII.GetString($dados, 44, $cmd.Length) -ne 'loglevel=8          rdinit=/p') { throw 'Cmdline Ubuntu incorreta.' }
}

function Build-VendorProbe {
    Assert-PartitionImage $VendorOriginal 'VNDRBOOT'
    if (-not (Test-Path -LiteralPath $PlatformV3)) { throw "Ramdisk v3 ausente: $PlatformV3" }
    if ((Get-HashLower $PlatformV3) -ne $HashPlatformV3) { throw 'Hash do ramdisk v3 incorreto.' }
    $platform = [IO.File]::ReadAllBytes($PlatformV3)
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
    $hashPlatOriginal = Get-BytesHash $dados ($ramdiskStart + $platOriginal.Offset) $platOriginal.Size
    if ($hashPlatOriginal -ne $HashPlatformOriginal) { throw "Platform original inesperado: $hashPlatOriginal" }
    $rec = $entries[$recoveryIndex]
    $hashRecovery = Get-BytesHash $dados ($ramdiskStart + $rec.Offset) $rec.Size
    $script:HashRecoveryAtual = $hashRecovery
    if ($hashRecovery -ne $HashRecoveryPermitido) { throw "TWRP inesperado: $hashRecovery" }
    $novoRamdiskSize = $ramdiskSize - $platOriginal.Size + $platform.Length
    $novoDtbStart = [int](Align-Up ($ramdiskStart + $novoRamdiskSize) $pagina)
    $novoTableStart = [int](Align-Up ($novoDtbStart + $dtbSize) $pagina)
    $novoBootconfigStart = [int](Align-Up ($novoTableStart + $tableSize) $pagina)
    $novoDataEnd = [int](Align-Up ($novoBootconfigStart + $bootconfigSize) $pagina)
    if ($novoDataEnd -gt $dataEnd) { throw 'Platform v3 ultrapassa a folga do vendor_boot.' }
    $novo = [byte[]]$dados.Clone()
    $cursor = 0
    foreach ($item in $entries) {
        $novoSize = $item.Size
        if ($item.Index -eq $platformIndex) {
            [Array]::Copy($platform, 0, $novo, $ramdiskStart + $cursor, $platform.Length)
            $novoSize = $platform.Length
        } else {
            [Array]::Copy($dados, $ramdiskStart + $item.Offset, $novo, $ramdiskStart + $cursor, $item.Size)
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
    if ((Get-BytesHash $novo ($ramdiskStart + $platNovo.Offset) $platNovo.Size) -ne $HashPlatformV3) { throw 'Platform v3 nao foi preservado.' }
    $recNovo = $entries[$recoveryIndex]
    if ((Get-BytesHash $novo ($ramdiskStart + $recNovo.Offset) $recNovo.Size) -ne $hashRecovery) { throw 'TWRP mudou na reconstrucao.' }
    [IO.File]::WriteAllBytes($VendorProbe, $novo)
    Assert-PartitionImage $VendorProbe 'VNDRBOOT'
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
        throw "boot/vendor atuais nao sao a instalacao v1 esperada.`n$hashes"
    }
    $release = Get-Checked $Adb @('-s', $Serial, 'shell', 'cat', '/data/etc/taiko-image-release')
    if ($release -notmatch 'TAIKO_IMAGE=ubuntu-24.04-arm64') { throw 'Ubuntu nao esta montado em /data.' }
    Write-Host 'TWRP, Ubuntu e imagens v2 confirmados.'
}

function Prepare-V3 {
    Assert-PartitionImage $BootOriginal 'ANDROID!'
    Assert-PartitionImage $VendorOriginal 'VNDRBOOT'
    $hashBoot = Get-HashLower $BootOriginal
    $hashVendor = Get-HashLower $VendorOriginal
    if ($hashBoot -ne $HashBootPermitido) { throw "Backup boot_a inesperado: $hashBoot" }
    if ($hashVendor -ne $HashVendorPermitido) { throw "Backup vendor_boot_a inesperado: $hashVendor" }
    Build-BootProbe
    Build-VendorProbe
    if ($HashRecoveryAtual -ne $HashRecoveryPermitido) { throw "Fragmento TWRP mudou: $HashRecoveryAtual" }
    $hashBootV2 = Get-HashLower $BootProbe
    $hashVendorV2 = Get-HashLower $VendorProbe
    @(
        "$hashBoot  boot_a-original.img",
        "$hashVendor  vendor_boot_a-original.img",
        "$hashBootV2  boot_a-ubuntu-v3.img",
        "$hashVendorV2  vendor_boot_a-ubuntu-v3.img",
        "$HashRecoveryAtual  recovery-fragment-preservado"
    ) | Set-Content -Encoding ASCII (Join-Path $Pasta 'IMAGENS-V3-SHA256.txt')
    Write-Host "boot Ubuntu v3:   $hashBootV2"
    Write-Host "vendor Ubuntu v3: $hashVendorV2"
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
Prepare-V3
Enter-Fastboot
Assert-FastbootTarget
Write-Host 'Gravando somente vendor_boot_a v3 integrado; TWRP preservado...'
Invoke-Checked $Fastboot @('-s', $Serial, 'flash', 'vendor_boot_a', $VendorProbe)
Write-Host 'Confirmando boot_a v3 com rdinit=/p...'
Invoke-Checked $Fastboot @('-s', $Serial, 'flash', 'boot_a', $BootProbe)
Write-Host 'Reiniciando no Ubuntu interno; userdata nao foi alterada...'
Invoke-Checked $Fastboot @('-s', $Serial, 'reboot')
Write-Host 'CORRECAO V3 APLICADA.' -ForegroundColor Green
