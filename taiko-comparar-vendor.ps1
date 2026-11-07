param(
    [string]$Pasta = "$env:USERPROFILE\Downloads\Taiko-Ubuntu-Installer"
)

$ErrorActionPreference = 'Stop'

function Align-Up([long]$Valor, [long]$Alinhamento) {
    return [long]([Math]::Floor(($Valor + $Alinhamento - 1) / $Alinhamento) * $Alinhamento)
}

function Get-RangeHash([byte[]]$Dados, [int]$Offset, [int]$Tamanho) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($Dados, $Offset, $Tamanho) }
    finally { $sha.Dispose() }
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Read-Vendor([string]$Arquivo) {
    $d = [IO.File]::ReadAllBytes($Arquivo)
    if ($d.Length -ne 67108864 -or [Text.Encoding]::ASCII.GetString($d, 0, 8) -ne 'VNDRBOOT') {
        throw "Imagem vendor_boot invalida: $Arquivo"
    }
    $page = [int][BitConverter]::ToUInt32($d, 12)
    $ramdiskSize = [int][BitConverter]::ToUInt32($d, 24)
    $headerSize = [int][BitConverter]::ToUInt32($d, 2096)
    $dtbSize = [int][BitConverter]::ToUInt32($d, 2100)
    $tableSize = [int][BitConverter]::ToUInt32($d, 2112)
    $count = [int][BitConverter]::ToUInt32($d, 2116)
    $entrySize = [int][BitConverter]::ToUInt32($d, 2120)
    $bootconfigSize = [int][BitConverter]::ToUInt32($d, 2124)
    $ramdiskStart = [int](Align-Up $headerSize $page)
    $dtbStart = [int](Align-Up ($ramdiskStart + $ramdiskSize) $page)
    $tableStart = [int](Align-Up ($dtbStart + $dtbSize) $page)
    $bootconfigStart = [int](Align-Up ($tableStart + $tableSize) $page)
    $dataEnd = [int](Align-Up ($bootconfigStart + $bootconfigSize) $page)
    $items = @()
    for ($n = 0; $n -lt $count; $n++) {
        $p = $tableStart + $n * $entrySize
        $size = [int][BitConverter]::ToUInt32($d, $p)
        $offset = [int][BitConverter]::ToUInt32($d, $p + 4)
        $type = [int][BitConverter]::ToUInt32($d, $p + 8)
        $name = ([Text.Encoding]::ASCII.GetString($d, $p + 12, 32)).Trim([char]0)
        $items += [pscustomobject]@{
            index = $n
            type = $type
            name = $name
            size = $size
            offset = $offset
            sha256 = Get-RangeHash $d ($ramdiskStart + $offset) $size
        }
    }
    return [pscustomobject]@{
        file = [IO.Path]::GetFileName($Arquivo)
        full_sha256 = (Get-FileHash -LiteralPath $Arquivo -Algorithm SHA256).Hash.ToLowerInvariant()
        ramdisk_size = $ramdiskSize
        ramdisk_start = $ramdiskStart
        dtb_start = $dtbStart
        dtb_size = $dtbSize
        dtb_sha256 = Get-RangeHash $d $dtbStart $dtbSize
        table_start = $tableStart
        table_size = $tableSize
        bootconfig_start = $bootconfigStart
        bootconfig_size = $bootconfigSize
        bootconfig_sha256 = Get-RangeHash $d $bootconfigStart $bootconfigSize
        structured_end = $dataEnd
        footer_magic = [Text.Encoding]::ASCII.GetString($d, $d.Length - 64, 4)
        entries = $items
    }
}

$nomes = @(
    'vendor_boot_a-original.img',
    'vendor_boot_a-ubuntu-v3.img',
    'vendor_boot_a-ubuntu-v4.img',
    'vendor_boot_a-ubuntu-v5.img',
    'vendor_boot_a-ubuntu-v6.img'
)
$resultado = @()
foreach ($nome in $nomes) {
    $arquivo = Join-Path $Pasta $nome
    if (Test-Path -LiteralPath $arquivo) { $resultado += Read-Vendor $arquivo }
}
if ($resultado.Count -lt 2) { throw "Imagens insuficientes em $Pasta" }
$destino = Join-Path $Pasta 'comparacao-vendor-boot.json'
$resultado | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $destino
Write-Host "CRIADO: $destino"
Get-Content -LiteralPath $destino
