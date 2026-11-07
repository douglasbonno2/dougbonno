param(
    [ValidateSet('executar', 'restaurar', 'status')]
    [string]$Acao = 'executar'
)

$ErrorActionPreference = 'Stop'
$Serial = 'n7jzceuwof4xeiwk'
$HashOriginal = 'e0b8548be3703338bdff8d141daed234e34fb84e1f26e3f149d30147ce6feacd'
$HashDiagnostico = '0f4a8f995db8b6afb25333a2a6158a87b261d05c24b27adaafe53077e4aa19d1'
$TamanhoBoot = 67108864
$Pasta = Join-Path $PSScriptRoot 'Taiko-Retain'
$Original = Join-Path $Pasta 'boot-original-taiko.img'
$Diagnostico = Join-Path $Pasta 'boot-retain-diagnostico.img'
$Coleta = Join-Path $Pasta 'coleta'

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
    & $Programa @Argumentos
    if ($LASTEXITCODE -ne 0) {
        throw "Falhou ($LASTEXITCODE): $Programa $($Argumentos -join ' ')"
    }
}

function Get-Checked {
    param([string]$Programa, [string[]]$Argumentos)
    $saida = & $Programa @Argumentos 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Falhou ($LASTEXITCODE): $Programa $($Argumentos -join ' ')`n$($saida -join "`n")"
    }
    return (($saida -join "`n").Trim())
}

function Get-HashLower {
    param([string]$Arquivo)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Arquivo).Hash.ToLowerInvariant()
}

function Assert-Image {
    param([string]$Arquivo, [string]$Hash)
    if (-not (Test-Path -LiteralPath $Arquivo)) { throw "Arquivo ausente: $Arquivo" }
    if ((Get-Item -LiteralPath $Arquivo).Length -ne $TamanhoBoot) { throw "Tamanho incorreto: $Arquivo" }
    $obtido = Get-HashLower $Arquivo
    if ($obtido -ne $Hash) { throw "Hash incorreto em $Arquivo`nEsperado: $Hash`nObtido:  $obtido" }
}

function Test-Adb {
    $saida = & $Adb -s $Serial get-state 2>$null
    return ($LASTEXITCODE -eq 0 -and (($saida -join '').Trim() -eq 'device'))
}

function Wait-AdbBoot {
    param([int]$Segundos = 180)
    Write-Host "Aguardando Android/ADB por ate $Segundos segundos..."
    for ($n = 1; $n -le $Segundos; $n++) {
        if (Test-Adb) {
            $completo = & $Adb -s $Serial shell getprop sys.boot_completed 2>$null
            if ($LASTEXITCODE -eq 0 -and (($completo -join '').Trim() -eq '1')) { return }
        }
        if (($n % 15) -eq 0) { Write-Host "  $n s..." }
        Start-Sleep -Seconds 1
    }
    throw 'Android nao apareceu. Entre manualmente no Fastboot e execute este script com: -Acao restaurar'
}

function Test-Fastboot {
    $linhas = & $Fastboot devices 2>$null
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
    throw 'Fastboot nao reconheceu o taiko. Verifique o cabo/driver Android Bootloader Interface.'
}

function Get-FastbootVar {
    param([string]$Nome)
    $saida = Get-Checked $Fastboot @('-s', $Serial, 'getvar', $Nome)
    $padrao = '(?m)^' + [regex]::Escape($Nome) + ':\s*(\S+)'
    $m = [regex]::Match($saida, $padrao)
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
    Write-Host 'Tablet nao esta no ADB. Coloque-o manualmente no Fastboot agora.'
    Wait-Fastboot 90
}

function Assert-FastbootTarget {
    if ((Get-FastbootVar 'product') -ne 'taiko') { throw 'Produto Fastboot nao e taiko.' }
    $userspace = Get-FastbootVar 'is-userspace'
    if ($userspace -eq 'yes') {
        Invoke-Checked $Fastboot @('-s', $Serial, 'reboot', 'bootloader')
        Wait-Fastboot
        $userspace = Get-FastbootVar 'is-userspace'
    }
    if ($userspace -ne 'no') { throw "Modo Fastboot inesperado: is-userspace=$userspace" }
    if ((Get-FastbootVar 'unlocked') -ne 'yes') { throw 'Bootloader nao esta desbloqueado.' }
    $tam = Get-FastbootVar 'partition-size:boot_a'
    $hex = $tam -replace '^0x', ''
    if ([Convert]::ToInt64($hex, 16) -ne $TamanhoBoot) { throw "Tamanho inesperado de boot_a: $tam" }
}

function Get-RootShell {
    param([string]$Comando)
    return Get-Checked $Adb @('-s', $Serial, 'shell', '-n', "su -mm -c '$Comando'")
}

function Prepare-Diagnostic {
    if (-not (Test-Adb)) { throw 'Conecte o tablet taiko no Android com depuracao USB autorizada.' }
    $produto = (Get-Checked $Adb @('-s', $Serial, 'shell', 'getprop', 'ro.product.device')).Trim()
    if ($produto -ne 'taiko') { throw "ADB conectado ao produto errado: $produto" }
    $slot = Get-RootShell 'grep androidboot.slot_suffix /proc/bootconfig'
    if ($slot -notmatch '"?_a"?\s*$') { throw "Slot Android inesperado: $slot" }
    $flags = (Get-RootShell 'od -An -tx1 -j120 -N4 /dev/block/by-name/vbmeta_a').ToLowerInvariant() -replace '\s', ''
    if ($flags -ne '00000003') { throw "Flags AVB inesperadas: $flags" }
    $hashFisico = ((Get-RootShell 'sha256sum /dev/block/by-name/boot_a') -split '\s+')[0].ToLowerInvariant()
    if ($hashFisico -ne $HashOriginal) {
        throw "boot_a nao e o original conhecido.`nEsperado: $HashOriginal`nObtido:  $hashFisico"
    }

    Write-Host 'Copiando boot_a original para backup local...'
    Get-RootShell 'dd if=/dev/block/by-name/boot_a of=/data/local/tmp/boot-original-taiko.img bs=4M 2>/dev/null && chmod 0644 /data/local/tmp/boot-original-taiko.img' | Out-Null
    Invoke-Checked $Adb @('-s', $Serial, 'pull', '/data/local/tmp/boot-original-taiko.img', $Original)
    Assert-Image $Original $HashOriginal

    Write-Host 'Construindo imagem retain_initrd a partir do backup verificado...'
    $dados = [IO.File]::ReadAllBytes($Original)
    if ([Text.Encoding]::ASCII.GetString($dados, 0, 8) -ne 'ANDROID!') { throw 'Cabecalho boot invalido.' }
    if ([BitConverter]::ToUInt32($dados, 40) -ne 4) { throw 'Versao de cabecalho boot inesperada.' }
    $argumento = [Text.Encoding]::ASCII.GetBytes('loglevel=8          retain_initrd')
    [Array]::Clear($dados, 44, 1536)
    [Array]::Copy($argumento, 0, $dados, 44, $argumento.Length)
    [IO.File]::WriteAllBytes($Diagnostico, $dados)
    Assert-Image $Diagnostico $HashDiagnostico
    Write-Host "Backup:      $Original"
    Write-Host "Diagnostico: $Diagnostico"
}

function Flash-Diagnostic {
    Assert-Image $Original $HashOriginal
    Assert-Image $Diagnostico $HashDiagnostico
    Enter-Fastboot
    Assert-FastbootTarget
    if ((Get-FastbootVar 'current-slot') -ne 'a') { throw 'Teste permitido somente com slot a ativo.' }
    Write-Host 'GRAVANDO SOMENTE boot_a COM DIAGNOSTICO retain_initrd...'
    $script:precisaRestaurar = $true
    Invoke-Checked $Fastboot @('-s', $Serial, 'flash', 'boot_a', $Diagnostico)
    Invoke-Checked $Fastboot @('-s', $Serial, 'reboot')
}

function Collect-Initrd {
    if (-not (Test-Adb)) { throw 'ADB indisponivel para coleta.' }
    $hashFisico = ((Get-RootShell 'sha256sum /dev/block/by-name/boot_a') -split '\s+')[0].ToLowerInvariant()
    if ($hashFisico -ne $HashDiagnostico) { throw "Imagem diagnostica nao esta em boot_a: $hashFisico" }

    $info = @()
    $info += 'DATE=' + (Get-Checked $Adb @('-s', $Serial, 'shell', 'date'))
    $info += 'CMDLINE=' + (Get-RootShell 'cat /proc/cmdline')
    $info += 'BOOTCONFIG=' + (Get-RootShell 'cat /proc/bootconfig')
    $info += 'BOOT_A_SHA256=' + (Get-RootShell 'sha256sum /dev/block/by-name/boot_a')
    $info | Set-Content -Encoding UTF8 (Join-Path $Coleta 'informacoes.txt')

    Write-Host 'Copiando initrd real entregue pelo bootloader...'
    Get-RootShell 'test -r /sys/firmware/initrd && cat /sys/firmware/initrd > /data/local/tmp/taiko-loader-initrd.bin && chmod 0644 /data/local/tmp/taiko-loader-initrd.bin' | Out-Null
    $Initrd = Join-Path $Coleta 'taiko-loader-initrd.bin'
    Invoke-Checked $Adb @('-s', $Serial, 'pull', '/data/local/tmp/taiko-loader-initrd.bin', $Initrd)
    if ((Get-Item -LiteralPath $Initrd).Length -le 0) { throw 'initrd coletado esta vazio.' }
    $hashInitrd = Get-HashLower $Initrd
    "$hashInitrd  taiko-loader-initrd.bin" | Set-Content -Encoding ASCII (Join-Path $Coleta 'SHA256SUMS.txt')

    Get-RootShell 'dmesg > /data/local/tmp/taiko-retain-dmesg.txt && chmod 0644 /data/local/tmp/taiko-retain-dmesg.txt' | Out-Null
    Invoke-Checked $Adb @('-s', $Serial, 'pull', '/data/local/tmp/taiko-retain-dmesg.txt', (Join-Path $Coleta 'dmesg.txt'))
    Get-RootShell 'for F in /sys/fs/pstore/*; do [ -r "$F" ] || continue; echo "===== $F ====="; cat "$F"; done > /data/local/tmp/taiko-retain-pstore.txt; chmod 0644 /data/local/tmp/taiko-retain-pstore.txt' | Out-Null
    Invoke-Checked $Adb @('-s', $Serial, 'pull', '/data/local/tmp/taiko-retain-pstore.txt', (Join-Path $Coleta 'pstore.txt'))
    Write-Host "COLETA CONCLUIDA: $Coleta"
}

function Restore-Original {
    Assert-Image $Original $HashOriginal
    Enter-Fastboot
    Assert-FastbootTarget
    $slot = Get-FastbootVar 'current-slot'
    if ($slot -ne 'a' -and $slot -ne 'b') { throw "Slot Fastboot inesperado: $slot" }
    Write-Host 'RESTAURANDO SOMENTE boot_a ORIGINAL...'
    Invoke-Checked $Fastboot @('-s', $Serial, 'flash', 'boot_a', $Original)
    if ($slot -ne 'a') { Invoke-Checked $Fastboot @('-s', $Serial, 'set_active', 'a') }
    Invoke-Checked $Fastboot @('-s', $Serial, 'reboot')
    Wait-AdbBoot 180
    $hashFisico = ((Get-RootShell 'sha256sum /dev/block/by-name/boot_a') -split '\s+')[0].ToLowerInvariant()
    if ($hashFisico -ne $HashOriginal) { throw "Restauracao nao confirmou hash original: $hashFisico" }
    & $Adb -s $Serial shell -n "su -mm -c 'rm -f /data/local/tmp/boot-original-taiko.img /data/local/tmp/taiko-loader-initrd.bin /data/local/tmp/taiko-retain-dmesg.txt /data/local/tmp/taiko-retain-pstore.txt'" | Out-Null
    Write-Host 'RESTAURACAO CONFIRMADA. Android voltou com boot_a original.' -ForegroundColor Green
}

function Show-Status {
    if (Test-Adb) {
        Write-Host 'Estado: Android/ADB'
        Write-Host ('Produto: ' + (Get-Checked $Adb @('-s', $Serial, 'shell', 'getprop', 'ro.product.device')))
        try { Write-Host ('boot_a: ' + (Get-RootShell 'sha256sum /dev/block/by-name/boot_a')) } catch { Write-Warning $_ }
        return
    }
    if (Test-Fastboot) {
        Write-Host 'Estado: Fastboot'
        Assert-FastbootTarget
        Write-Host ('Slot: ' + (Get-FastbootVar 'current-slot'))
        return
    }
    Write-Host 'Tablet taiko nao encontrado no ADB nem no Fastboot.'
}

if ($Acao -eq 'status') {
    Show-Status
    exit 0
}

if ($Acao -eq 'restaurar') {
    Restore-Original
    exit 0
}

$precisaRestaurar = $false
try {
    Prepare-Diagnostic
    Flash-Diagnostic
    Wait-AdbBoot 180
    Collect-Initrd
}
finally {
    if ($precisaRestaurar) {
        try {
            Restore-Original
        }
        catch {
            Write-Host ''
            Write-Host 'RESTAURACAO AUTOMATICA NAO FOI CONCLUIDA.' -ForegroundColor Red
            Write-Host 'Entre no Fastboot e execute:' -ForegroundColor Yellow
            Write-Host "powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Acao restaurar" -ForegroundColor Yellow
            throw
        }
    }
}

Write-Host ''
Write-Host 'TESTE FINALIZADO: coleta salva e boot original restaurado.' -ForegroundColor Green
