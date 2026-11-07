param(
    [string]$DestinoBase = (Join-Path $env:USERPROFILE 'Downloads'),
    [switch]$IncluirUserdata
)

$ErrorActionPreference = 'Stop'
$Serial = 'n7jzceuwof4xeiwk'
$Data = Get-Date -Format 'yyyyMMdd-HHmmss'
$Destino = Join-Path $DestinoBase "Taiko-ROM-Backup-$Data"
$Manifesto = Join-Path $Destino 'MANIFESTO-SHA256.txt'
$Inventario = Join-Path $Destino 'inventario.txt'

$Particoes = @(
    'boot_a', 'boot_b',
    'vendor_boot_a', 'vendor_boot_b',
    'init_boot_a', 'init_boot_b',
    'dtbo_a', 'dtbo_b', 'odmdtbo_a', 'odmdtbo_b',
    'vbmeta_a', 'vbmeta_b',
    'vbmeta_system_a', 'vbmeta_system_b',
    'vbmeta_vendor_a', 'vbmeta_vendor_b',
    'super', 'metadata',
    'misc', 'para', 'logo', 'frp', 'seccfg',
    'persist', 'nvdata', 'nvram', 'nvcfg',
    'protect1', 'protect2', 'proinfo'
)
if ($IncluirUserdata) { $Particoes += 'userdata' }

New-Item -ItemType Directory -Force -Path $Destino | Out-Null

$AdbCmd = Get-Command adb.exe -ErrorAction SilentlyContinue
if (-not $AdbCmd) { $AdbCmd = Get-Command adb -ErrorAction Stop }
$Adb = $AdbCmd.Source

function Invoke-AdbChecked {
    param([string[]]$Argumentos)
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Adb @Argumentos; $codigo = $LASTEXITCODE }
    finally { $ErrorActionPreference = $anterior }
    if ($codigo -ne 0) { throw "ADB falhou ($codigo): $($Argumentos -join ' ')" }
}

function Get-AdbChecked {
    param([string[]]$Argumentos)
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $saida = & $Adb @Argumentos 2>&1; $codigo = $LASTEXITCODE }
    finally { $ErrorActionPreference = $anterior }
    if ($codigo -ne 0) { throw "ADB falhou ($codigo): $($Argumentos -join ' ')`n$($saida -join "`n")" }
    return (($saida -join "`n").Trim())
}

function Test-RecoveryReady {
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $dispositivos = & $Adb devices -l 2>$null
        $codigoLista = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $anterior }
    if ($codigoLista -eq 0) {
        foreach ($linha in $dispositivos) {
            if ($linha -match ('^' + [regex]::Escape($Serial) + '\s+recovery(?:\s|$)')) { return $true }
        }
    }
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $estado = & $Adb -s $Serial get-state 2>$null; $codigo = $LASTEXITCODE }
    finally { $ErrorActionPreference = $anterior }
    if ($codigo -ne 0 -or (($estado -join '').Trim() -ne 'device')) { return $false }
    try {
        $modo = Get-AdbChecked @('-s', $Serial, 'shell', 'getprop', 'ro.bootmode')
        $produto = Get-AdbChecked @('-s', $Serial, 'shell', 'getprop', 'ro.product.device')
        $twrp = Get-AdbChecked @('-s', $Serial, 'shell', 'getprop', 'ro.twrp.version')
        return ($produto.Trim() -match 'taiko' -and ($modo -match 'recovery' -or $twrp.Trim().Length -gt 0))
    }
    catch { return $false }
}

function Wait-Recovery {
    param([int]$Segundos = 120)
    for ($n = 1; $n -le $Segundos; $n++) {
        if (Test-RecoveryReady) { return }
        if (($n % 15) -eq 0) { Write-Host "  aguardando recovery: $n s..." }
        Start-Sleep -Seconds 1
    }
    throw 'TWRP nao apareceu no ADB.'
}

function Test-RemotePartition {
    param([string]$Nome)
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Adb -s $Serial shell test -e "/dev/block/by-name/$Nome" 2>$null; $codigo = $LASTEXITCODE }
    finally { $ErrorActionPreference = $anterior }
    return $codigo -eq 0
}

function Convert-HashHex {
    param([byte[]]$Hash)
    return ([BitConverter]::ToString($Hash) -replace '-', '').ToLowerInvariant()
}

function Copy-PartitionGzip {
    param([string]$Nome)
    $remoto = "/dev/block/by-name/$Nome"
    $tamanho = [long](Get-AdbChecked @('-s', $Serial, 'shell', 'blockdev', '--getsize64', $remoto))
    if ($tamanho -le 0) { throw "Tamanho invalido para $Nome" }
    $hashRemoto = ((Get-AdbChecked @('-s', $Serial, 'shell', 'sha256sum', $remoto)) -split '\s+')[0].ToLowerInvariant()
    $arquivoSaida = Join-Path $Destino "$Nome.img.gz"

    Write-Host ("Copiando {0}: {1:N2} GiB..." -f $Nome, ($tamanho / 1GB))
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Adb
    $psi.Arguments = "-s $Serial exec-out `"dd if=$remoto bs=4M 2>/dev/null`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $processo = New-Object Diagnostics.Process
    $processo.StartInfo = $psi

    $arquivo = [IO.File]::Create($arquivoSaida)
    $gzip = [IO.Compression.GZipStream]::new($arquivo, [IO.Compression.CompressionLevel]::Optimal, $false)
    $sha = [Security.Cryptography.SHA256]::Create()
    $buffer = New-Object byte[] (4MB)
    $total = 0L
    try {
        if (-not $processo.Start()) { throw 'Nao foi possivel iniciar adb exec-out.' }
        $entrada = $processo.StandardOutput.BaseStream
        while (($lidos = $entrada.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $gzip.Write($buffer, 0, $lidos)
            [void]$sha.TransformBlock($buffer, 0, $lidos, $null, 0)
            $total += $lidos
            if (($total % 1GB) -lt $buffer.Length) {
                Write-Host ("  {0:N2}/{1:N2} GiB" -f ($total / 1GB), ($tamanho / 1GB))
            }
        }
        [void]$sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        $hashLocalRaw = Convert-HashHex $sha.Hash
        $erroAdb = $processo.StandardError.ReadToEnd()
        $processo.WaitForExit()
        if ($processo.ExitCode -ne 0) { throw "adb exec-out falhou ($($processo.ExitCode)): $erroAdb" }
    }
    finally {
        $gzip.Dispose()
        $arquivo.Dispose()
        $sha.Dispose()
        $processo.Dispose()
    }

    if ($total -ne $tamanho) { throw "Copia incompleta de ${Nome}: $total de $tamanho bytes" }
    if ($hashLocalRaw -ne $hashRemoto) { throw "SHA256 nao confere em ${Nome}: remoto=$hashRemoto local=$hashLocalRaw" }
    $hashGzip = (Get-FileHash -Algorithm SHA256 -LiteralPath $arquivoSaida).Hash.ToLowerInvariant()
    $tamanhoGzip = (Get-Item -LiteralPath $arquivoSaida).Length
    return [pscustomobject]@{
        Nome = $Nome
        RawSize = $tamanho
        RawHash = $hashLocalRaw
        GzipSize = $tamanhoGzip
        GzipHash = $hashGzip
        Arquivo = [IO.Path]::GetFileName($arquivoSaida)
    }
}

if (Test-RecoveryReady) {
    Write-Host 'TWRP ja esta conectado; iniciando backup somente leitura...'
}
else {
    Write-Host 'Reiniciando no TWRP para copiar os blocos em modo somente leitura...'
    Invoke-AdbChecked @('-s', $Serial, 'reboot', 'recovery')
}
Wait-Recovery

$id = Get-AdbChecked @('-s', $Serial, 'shell', 'id')
if ($id -notmatch 'uid=0\(root\)') { throw "ADB no recovery nao esta como root: $id" }

$deviceInfo = Get-AdbChecked @('-s', $Serial, 'shell', 'getprop', 'ro.product.device')
$bootmodeInfo = Get-AdbChecked @('-s', $Serial, 'shell', 'getprop', 'ro.bootmode')
$linhasInventario = @(
    'DATA=' + (Get-AdbChecked @('-s', $Serial, 'shell', 'date')),
    'ID=' + $id,
    'DEVICE=' + $deviceInfo,
    'BOOTMODE=' + $bootmodeInfo,
    'BY_NAME:',
    (Get-AdbChecked @('-s', $Serial, 'shell', 'ls', '-l', '/dev/block/by-name'))
)
$linhasInventario | Set-Content -Encoding UTF8 -LiteralPath $Inventario

$resultados = @()
foreach ($particao in $Particoes) {
    if (-not (Test-RemotePartition $particao)) {
        Write-Host "Ignorando particao ausente: $particao"
        continue
    }
    $resultados += Copy-PartitionGzip $particao
}

$manifestoLinhas = @(
    'TAIKO ROM BACKUP',
    "created=$Data",
    "serial=$Serial",
    "userdata_included=$($IncluirUserdata.IsPresent)",
    'format=raw partition image compressed independently with gzip',
    ''
)
foreach ($item in $resultados) {
    $manifestoLinhas += "$($item.GzipHash)  $($item.Arquivo)"
    $manifestoLinhas += "RAW  $($item.Nome) size=$($item.RawSize) sha256=$($item.RawHash) gzip_size=$($item.GzipSize)"
}
$manifestoLinhas | Set-Content -Encoding ASCII -LiteralPath $Manifesto

Write-Host 'Reiniciando no Android...'
Invoke-AdbChecked @('-s', $Serial, 'reboot', 'system')
Write-Host ''
Write-Host "BACKUP CONCLUIDO E VERIFICADO: $Destino" -ForegroundColor Green
if (-not $IncluirUserdata) {
    Write-Host 'A ROM e as particoes de recuperacao/calibracao foram salvas. Apps e arquivos de userdata nao estao neste backup.' -ForegroundColor Yellow
}
