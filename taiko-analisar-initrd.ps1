param(
    [string]$Pasta = (Join-Path $PSScriptRoot 'Taiko-Retain')
)

$ErrorActionPreference = 'Stop'

$Boot = Join-Path $Pasta 'boot-original-taiko.img'
$Initrd = Join-Path $Pasta 'coleta\taiko-loader-initrd.bin'
$Saida = Join-Path $Pasta 'analise-initrd'
$Relatorio = Join-Path $Saida 'analise-initrd.txt'
$RamdiskRetido = Join-Path $Saida 'generic-ramdisk-retido.bin'
$Pacote = Join-Path $Pasta 'taiko-initrd-analisado.zip'
$HashKernelConhecido = 'e4121682a5dc9e637710642eb4daaea57697f3b501a959715c4cc323f3e15e35'
$HashVendorConhecido = 'd45d7d33ca368de5a1dc8e6689d996e2a1b15359b3547e2237e762b0957a97f9'
$TamanhoVendorConhecido = 43361868L

function Read-Exactly {
    param(
        [IO.Stream]$Stream,
        [byte[]]$Buffer,
        [int]$Count
    )
    $total = 0
    while ($total -lt $Count) {
        $lidos = $Stream.Read($Buffer, $total, $Count - $total)
        if ($lidos -le 0) { throw 'Fim inesperado do arquivo.' }
        $total += $lidos
    }
}

function Get-SegmentHash {
    param(
        [string]$Arquivo,
        [long]$Offset,
        [long]$Tamanho
    )
    $stream = [IO.File]::OpenRead($Arquivo)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream.Position = $Offset
        $buffer = New-Object byte[] (1024 * 1024)
        $restante = $Tamanho
        while ($restante -gt 0) {
            $pedido = [int][Math]::Min([long]$buffer.Length, $restante)
            $lidos = $stream.Read($buffer, 0, $pedido)
            if ($lidos -le 0) { throw 'Fim inesperado ao calcular SHA256.' }
            [void]$sha.TransformBlock($buffer, 0, $lidos, $null, 0)
            $restante -= $lidos
        }
        [void]$sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        return ([BitConverter]::ToString($sha.Hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Get-SegmentMagic {
    param(
        [string]$Arquivo,
        [long]$Offset,
        [int]$Tamanho = 16
    )
    $stream = [IO.File]::OpenRead($Arquivo)
    try {
        $stream.Position = $Offset
        $buffer = New-Object byte[] $Tamanho
        Read-Exactly $stream $buffer $Tamanho
        return ([BitConverter]::ToString($buffer) -replace '-', '').ToLowerInvariant()
    }
    finally { $stream.Dispose() }
}

function Copy-Segment {
    param(
        [string]$Origem,
        [long]$Offset,
        [long]$Tamanho,
        [string]$Destino
    )
    $entrada = [IO.File]::OpenRead($Origem)
    $saidaStream = [IO.File]::Create($Destino)
    try {
        $entrada.Position = $Offset
        $buffer = New-Object byte[] (1024 * 1024)
        $restante = $Tamanho
        while ($restante -gt 0) {
            $pedido = [int][Math]::Min([long]$buffer.Length, $restante)
            $lidos = $entrada.Read($buffer, 0, $pedido)
            if ($lidos -le 0) { throw 'Fim inesperado ao extrair segmento.' }
            $saidaStream.Write($buffer, 0, $lidos)
            $restante -= $lidos
        }
    }
    finally {
        $saidaStream.Dispose()
        $entrada.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $Boot)) { throw "Arquivo ausente: $Boot" }
if (-not (Test-Path -LiteralPath $Initrd)) { throw "Arquivo ausente: $Initrd" }

$cabecalho = New-Object byte[] 44
$streamBoot = [IO.File]::OpenRead($Boot)
try { Read-Exactly $streamBoot $cabecalho 44 }
finally { $streamBoot.Dispose() }

if ([Text.Encoding]::ASCII.GetString($cabecalho, 0, 8) -ne 'ANDROID!') {
    throw 'boot-original-taiko.img nao possui cabecalho ANDROID!'
}
$versao = [BitConverter]::ToUInt32($cabecalho, 40)
if ($versao -ne 4) { throw "Versao inesperada do cabecalho boot: $versao" }

$tamanhoKernel = [long][BitConverter]::ToUInt32($cabecalho, 8)
$tamanhoRamdisk = [long][BitConverter]::ToUInt32($cabecalho, 12)
$offsetKernelBoot = 4096L
$offsetRamdiskBoot = $offsetKernelBoot + [long]([Math]::Ceiling($tamanhoKernel / 4096.0) * 4096)
$tamanhoInitrd = (Get-Item -LiteralPath $Initrd).Length
$offsetRamdiskRetido = $tamanhoKernel
$offsetVendorRetido = $tamanhoKernel + $tamanhoRamdisk
$tamanhoVendorRetido = $tamanhoInitrd - $offsetVendorRetido

if ($tamanhoKernel -le 0 -or $tamanhoRamdisk -le 0 -or $tamanhoVendorRetido -le 0) {
    throw 'Tamanhos invalidos ao separar a captura.'
}

$hashKernelBoot = Get-SegmentHash $Boot $offsetKernelBoot $tamanhoKernel
$hashRamdiskBoot = Get-SegmentHash $Boot $offsetRamdiskBoot $tamanhoRamdisk
$hashKernelRetido = Get-SegmentHash $Initrd 0 $tamanhoKernel
$hashRamdiskRetido = Get-SegmentHash $Initrd $offsetRamdiskRetido $tamanhoRamdisk
$hashVendorRetido = Get-SegmentHash $Initrd $offsetVendorRetido $tamanhoVendorRetido

$kernelConfere = $hashKernelBoot -eq $hashKernelRetido
$ramdiskConfere = $hashRamdiskBoot -eq $hashRamdiskRetido
$kernelConhecido = $hashKernelRetido -eq $HashKernelConhecido
$vendorConhecido = ($tamanhoVendorRetido -eq $TamanhoVendorConhecido) -and ($hashVendorRetido -eq $HashVendorConhecido)

New-Item -ItemType Directory -Force -Path $Saida | Out-Null
Copy-Segment $Initrd $offsetRamdiskRetido $tamanhoRamdisk $RamdiskRetido

$linhas = @(
    'TAIKO RETAIN_INITRD - ANALISE SOMENTE LEITURA',
    "boot=$Boot",
    "initrd=$Initrd",
    "boot_header_version=$versao",
    "initrd_total=$tamanhoInitrd",
    "kernel_offset=0",
    "kernel_size=$tamanhoKernel",
    "kernel_magic=$(Get-SegmentMagic $Initrd 0)",
    "kernel_sha256=$hashKernelRetido",
    "kernel_matches_boot=$kernelConfere",
    "kernel_matches_known=$kernelConhecido",
    "generic_ramdisk_offset=$offsetRamdiskRetido",
    "generic_ramdisk_size=$tamanhoRamdisk",
    "generic_ramdisk_magic=$(Get-SegmentMagic $Initrd $offsetRamdiskRetido)",
    "generic_ramdisk_sha256=$hashRamdiskRetido",
    "generic_ramdisk_matches_boot=$ramdiskConfere",
    "vendor_ramdisk_offset=$offsetVendorRetido",
    "vendor_ramdisk_size=$tamanhoVendorRetido",
    "vendor_ramdisk_magic=$(Get-SegmentMagic $Initrd $offsetVendorRetido)",
    "vendor_ramdisk_sha256=$hashVendorRetido",
    "vendor_ramdisk_matches_known=$vendorConhecido"
)
$linhas | Set-Content -Encoding ASCII -LiteralPath $Relatorio

if (-not $kernelConfere) { throw 'O kernel da captura nao coincide com o kernel de boot-original-taiko.img.' }
if (-not $ramdiskConfere) { throw 'O ramdisk generico da captura nao coincide com o ramdisk do boot salvo.' }
if (-not $vendorConhecido) { throw 'O segmento vendor da captura nao coincide com o vendor_boot conhecido.' }

if (Test-Path -LiteralPath $Pacote) { Remove-Item -Force -LiteralPath $Pacote }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($Saida, $Pacote)

Write-Host ''
Write-Host 'COMPOSICAO CONFIRMADA: kernel + generic ramdisk + vendor ramdisk'
Write-Host "Ramdisk generico: $RamdiskRetido"
Write-Host "Relatorio:         $Relatorio"
Write-Host "Pacote para envio: $Pacote"
