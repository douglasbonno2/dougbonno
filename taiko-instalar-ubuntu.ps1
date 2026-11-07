param(
    [ValidateSet('instalar', 'preparar', 'status')]
    [string]$Acao = 'instalar',
    [string]$Imagem = (Join-Path $env:USERPROFILE 'Downloads\Taiko-Ubuntu-24.04\taiko-ubuntu-24.04-arm64-userdata-sparse.img')
)

$ErrorActionPreference = 'Stop'
$Serial = 'n7jzceuwof4xeiwk'
$TamanhoParticao = 67108864
$HashBootPermitido = '1a7ce84bc588754a15f39366727e86cc9743ca7704d7aba254f29f2d2ac0fc36'
$OverlayBase64 = 'AiFMGAUFAAByMDcwNzAxMAEAAQgAXzgxZTgwAQADGTEOAE84MzcwAQASFTE4APgWdGFpa28tbGludXgtaW5pdAAAIyEvc3lzdGVtL2Jpbi9zaApUPREA8Sh0b3lib3gKbG9nKCkgeyBlY2hvICI8Nj5UQUlLT19MSU5VWDogJCoiID4gL2Rldi9rbXNnIDI+DADBbnVsbDsgfQpmYWlsPgCgbG9nICJGQUxIQTQA8AE7IHJldG9ybmFuZG8gYW8gkADwAiBBbmRyb2lkIjsgZXhlYyAvFQAARADyAgokVCBtb3VudCAtdCBwcm9jBQARLwYAB3AAiSB8fCB0cnVlMABTc3lzZnMGAADdAA8xAA6GZGV2dG1wZnMJAAAwAA83AAZya2RpciAtcAIBMnB0cwkA7GJsb2NrIC9uZXdyb290YAAAJwADBwAFNwAPYAABATQBsFBJRDEgVWJ1bnR1JwHRY2lhZG87IGNhcnJlZz8BwG1vZHVsb3MgZG8gVOMB8QEiCgppZiBbIC1mIC9saWIvIAAkZXMIAPIULmxvYWQgXTsgdGhlbgogIHdoaWxlIElGUz0gcmVhZCAtciAqAIA7IGRvCiAgIEsAQm4gIiQWADAiIF2gAIFjb250aW51ZSEAcm5hbWU9JHshAFElLmtvfRcAAfYA8AJkcHJvYmUgLWQgLyAtcSAiJC0AGyLvAAArAIlpbnNtb2QgIrQABXUADh8BAHsAb2RvbmUgPOcAB/IDCmZpCgpST09UREVWPQpuPTAK7gDwAVsgJG4gLWx0IDMwIF0gJibjAEN6ICIkKwAzIiBd/QDRZm9yIHVldmVudCBpbkACYi9jbGFzc+EBMi8qLx0ACCsBQmYgIiQWAA8rAQFBcGFydC8BAA4AAAUCBg0ABokBNSc9J4wBhmtleSB2YWx1jwEAZgDyAiIka2V5IiA9IFBBUlROQU1FxwAFXgARJDMADi8ANkRFVi4ABH4ABy0AA1EBBcIAARUAIWlmQwAEXQAASACFdXNlcmRhdGE+AQAhAgNQABciXQIDFAExYiAivwEHIwAAOAAEmgELHQAOOAACbgEPPgAKCyMAA0QAUWJyZWFrDAAjZmkwAhUK0QIG7gEATwAEKwDRbj0kKChuICsgMSkpCsUCgXNsZWVwIDEKPgAdCj0AAOQBAOcEICAiIgFGaWNhbx8BYG5hbyBlbgICUnJhZGEi0gNBbW9udLoDBEUA+QEgY29tbyByYWl6IGV4dDQiMAQAEgDoIC1vIHJ3LG5vYXRpbWV+AARjBAwhAwKRAAB/AABuACVvdZMAECLBABV4OAAgL3PqBQF/BQfJAAIFBvoGZCBhdXNlbnRlIG5hIGltYWdlbSIK9QQERgACkQUFVAAmeXMNAAA9BQUNACJydW0AV3JhbWZz5wBrLW1vdmUgRwAP4AUQAzgACXEAD+UFDwM2AAmaAA7kBQ02AEZiaW5kcQEPegELASwAImRh1QGXZmFsaG91IgpjPwAFKgApY2QlAABxAGFwaXZvdF8nACkuIDMBD20AAwcwAARGAAGtBxwnrQcAWAcSdXwCBOMBI2RvXQYfJ8cHBRIKjgcFKQIpCgC4CBAyBQBPNDFlZLgIEg8BABcUNAkAWmRldgAAdAARM3kAPzE4MHQALAQoABNiCAAXOXQAAQgBC3gABZQAD+wAPBRiCQC/VFJBSUxFUiEhIQABAP/MUAAAAAAA'
$HashOverlay = 'c4fef955fbf2e7b1a87f534b12aea799822d8a3e0e17bce24e6491924474db30'
$HashVendorPermitido = '549b34688599ed728e6f283b8d0ba57844162aefa974c299da039e8ba7d5bf1b'
$HashRecoveryPermitido = '118e7f36d87feb73168aa4821fb09e544e284c502e7e5f7ff56e403555920070'
$HashImagem = '4f18988839b420a3c9eefad9e252789a42560c6324b9ea547ff17af7b48bdd4c'
$Pasta = Join-Path $PSScriptRoot 'Taiko-Ubuntu-Installer'
$Coleta = Join-Path $Pasta 'coleta'
$BootOriginal = Join-Path $Pasta 'boot_a-original.img'
$VendorOriginal = Join-Path $Pasta 'vendor_boot_a-original.img'
$BootProbe = Join-Path $Pasta 'boot_a-ubuntu.img'
$VendorProbe = Join-Path $Pasta 'vendor_boot_a-ubuntu.img'

New-Item -ItemType Directory -Force -Path $Pasta | Out-Null
New-Item -ItemType Directory -Force -Path $Coleta | Out-Null

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
    return ($codigo -eq 0 -and (($saida -join '').Trim() -eq 'device'))
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
    $cmd = [Text.Encoding]::ASCII.GetBytes('loglevel=8          rdinit=/taiko-linux-init')
    [Array]::Clear($dados, 44, 1536)
    [Array]::Copy($cmd, 0, $dados, 44, $cmd.Length)
    [IO.File]::WriteAllBytes($BootProbe, $dados)
    Assert-PartitionImage $BootProbe 'ANDROID!'
    if ([Text.Encoding]::ASCII.GetString($dados, 44, $cmd.Length) -ne 'loglevel=8          rdinit=/taiko-linux-init') { throw 'Cmdline Ubuntu incorreta.' }
}

function Build-VendorProbe {
    Assert-PartitionImage $VendorOriginal 'VNDRBOOT'
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
    $overlay = [Convert]::FromBase64String($OverlayBase64)
    if ((Get-BytesHash $overlay 0 $overlay.Length) -ne $HashOverlay) { throw 'Overlay interno corrompido.' }

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
        if ($item.Offset + $item.Size -gt $ramdiskSize) { throw "Entrada ramdisk $n fora dos limites." }
        if ($item.Type -eq 1 -and $platformIndex -lt 0) { $platformIndex = $n }
        if ($item.Type -eq 2 -and $recoveryIndex -lt 0) { $recoveryIndex = $n }
        $entries += $item
    }
    if ($platformIndex -lt 0 -or $recoveryIndex -lt 0) { throw 'Fragmentos platform/recovery nao encontrados.' }
    $rec = $entries[$recoveryIndex]
    if ($rec.Name -ne 'recovery') { throw "Nome inesperado do fragmento recovery: $($rec.Name)" }
    if ([BitConverter]::ToUInt32($dados, $ramdiskStart + $rec.Offset) -ne 0x184c2102) { throw 'Recovery atual nao inicia com legacy LZ4.' }
    $hashRecovery = Get-BytesHash $dados ($ramdiskStart + $rec.Offset) $rec.Size
    $script:HashRecoveryAtual = $hashRecovery

    $novoRamdiskSize = $ramdiskSize + $overlay.Length
    $novoDtbStart = [int](Align-Up ($ramdiskStart + $novoRamdiskSize) $pagina)
    $novoTableStart = [int](Align-Up ($novoDtbStart + $dtbSize) $pagina)
    $novoBootconfigStart = [int](Align-Up ($novoTableStart + $tableSize) $pagina)
    $novoDataEnd = [int](Align-Up ($novoBootconfigStart + $bootconfigSize) $pagina)
    if ($novoDataEnd -ne $dataEnd) { throw 'Overlay ultrapassaria a folga existente; nada foi criado.' }

    $novo = [byte[]]$dados.Clone()
    $cursor = 0
    foreach ($item in $entries) {
        $origem = $ramdiskStart + $item.Offset
        [Array]::Copy($dados, $origem, $novo, $ramdiskStart + $cursor, $item.Size)
        $novoSize = $item.Size
        if ($item.Index -eq $platformIndex) {
            [Array]::Copy($overlay, 0, $novo, $ramdiskStart + $cursor + $item.Size, $overlay.Length)
            $novoSize += $overlay.Length
        }
        $item.Offset = $cursor
        $item.Size = $novoSize
        $cursor += $novoSize
    }
    if ($cursor -ne $novoRamdiskSize) { throw 'Tamanho reconstruido do vendor ramdisk incorreto.' }
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

    $plat = $entries[$platformIndex]
    $overlayOffset = $ramdiskStart + $plat.Offset + $plat.Size - $overlay.Length
    if ((Get-BytesHash $novo $overlayOffset $overlay.Length) -ne $HashOverlay) { throw 'Overlay nao foi preservado no candidato.' }
    $recNovo = $entries[$recoveryIndex]
    if ((Get-BytesHash $novo ($ramdiskStart + $recNovo.Offset) $recNovo.Size) -ne $hashRecovery) { throw 'Recovery atual mudou durante a reconstrucao.' }
    [IO.File]::WriteAllBytes($VendorProbe, $novo)
    Assert-PartitionImage $VendorProbe 'VNDRBOOT'
}

function Prepare-Probe {
    Assert-AndroidTarget
    Write-Host 'Copiando boot_a e vendor_boot_a atuais antes da instalacao...'
    Pull-Partition 'boot_a' $BootOriginal
    Pull-Partition 'vendor_boot_a' $VendorOriginal
    Assert-PartitionImage $BootOriginal 'ANDROID!'
    Assert-PartitionImage $VendorOriginal 'VNDRBOOT'
    $hashBoot = Get-HashLower $BootOriginal
    if ($hashBoot -ne $HashBootPermitido) { throw "boot_a inesperado: $hashBoot" }
    $hashVendor = Get-HashLower $VendorOriginal
    if ($hashVendor -ne $HashVendorPermitido) { throw "vendor_boot_a inesperado: $hashVendor" }
    Build-BootProbe
    Build-VendorProbe
    if ($HashRecoveryAtual -ne $HashRecoveryPermitido) { throw "Fragmento TWRP inesperado: $HashRecoveryAtual" }
    $script:HashBootOriginal = $hashBoot
    $script:HashVendorOriginal = Get-HashLower $VendorOriginal
    $script:HashBootProbe = Get-HashLower $BootProbe
    $script:HashVendorProbe = Get-HashLower $VendorProbe
    @(
        "$HashBootOriginal  boot_a-original.img",
        "$HashVendorOriginal  vendor_boot_a-original.img",
        "$HashBootProbe  boot_a-ubuntu.img",
        "$HashVendorProbe  vendor_boot_a-ubuntu.img",
        "$HashRecoveryAtual  recovery-fragment-preservado"
    ) | Set-Content -Encoding ASCII (Join-Path $Pasta 'IMAGENS-SHA256.txt')
    Write-Host "boot original:   $HashBootOriginal"
    Write-Host "vendor original: $HashVendorOriginal"
    Write-Host "boot Ubuntu:     $HashBootProbe"
    Write-Host "vendor Ubuntu:   $HashVendorProbe"
    Write-Host "TWRP preservado: $HashRecoveryAtual"
}


function Assert-BackupRom {
    $base = Join-Path $env:USERPROFILE 'Downloads'
    $backup = Get-ChildItem -LiteralPath $base -Directory -Filter 'Taiko-ROM-Backup-*' -ErrorAction SilentlyContinue |
        Where-Object { (Test-Path (Join-Path $_.FullName 'MANIFESTO-SHA256.txt')) -and (Test-Path (Join-Path $_.FullName 'super.img.gz')) } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $backup) { throw 'Backup completo da ROM nao encontrado em Downloads.' }
    Write-Host "Backup de retorno encontrado: $($backup.FullName)"
}

function Assert-UbuntuImage {
    if (-not (Test-Path -LiteralPath $Imagem)) { throw "Imagem Ubuntu ausente: $Imagem" }
    $hash = Get-HashLower $Imagem
    if ($hash -ne $HashImagem) { throw "Hash da imagem Ubuntu incorreto: $hash" }
    $stream = [IO.File]::OpenRead($Imagem)
    try {
        $cabecalho = New-Object byte[] 4
        [void]$stream.Read($cabecalho, 0, 4)
    } finally { $stream.Dispose() }
    if ([BitConverter]::ToString($cabecalho) -ne '3A-FF-26-ED') { throw 'Imagem nao esta no formato Android sparse.' }
    Write-Host "Imagem Ubuntu verificada: $Imagem"
}

function Show-Status {
    if (Test-Adb) {
        Write-Host 'Tablet no Android/ADB.'
        Write-Host (Get-RootShell 'sha256sum /dev/block/by-name/boot_a /dev/block/by-name/vendor_boot_a')
    } elseif (Test-Fastboot) {
        Write-Host 'Tablet no Fastboot.'
    } else {
        Write-Host 'Tablet nao detectado no ADB nem Fastboot.'
    }
}

if ($Acao -eq 'status') { Show-Status; exit 0 }
Assert-UbuntuImage
Assert-BackupRom
Prepare-Probe
if ($Acao -eq 'preparar') {
    Write-Host "PREPARACAO CONCLUIDA: imagens em $Pasta" -ForegroundColor Green
    exit 0
}

Write-Host 'ATENCAO: a proxima etapa substitui userdata pelo Ubuntu; apps e arquivos Android serao apagados.' -ForegroundColor Yellow
Enter-Fastboot
Assert-FastbootTarget
Write-Host 'Gravando Ubuntu em userdata (imagem sparse)...'
Invoke-Checked $Fastboot @('-s', $Serial, 'flash', 'userdata', $Imagem)
Write-Host 'Gravando vendor_boot_a Ubuntu; fragmento TWRP preservado byte a byte...'
Invoke-Checked $Fastboot @('-s', $Serial, 'flash', 'vendor_boot_a', $VendorProbe)
Write-Host 'Gravando boot_a Ubuntu...'
Invoke-Checked $Fastboot @('-s', $Serial, 'flash', 'boot_a', $BootProbe)
Write-Host 'Reiniciando no Ubuntu interno...'
Invoke-Checked $Fastboot @('-s', $Serial, 'reboot')
Write-Host 'INSTALACAO CONCLUIDA. Usuario: taiko  Senha: taiko' -ForegroundColor Green
Write-Host "Backups exatos de boot/vendor: $Pasta"
