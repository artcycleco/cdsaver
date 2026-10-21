<#
    CD-Kurtar.ps1  v2  --  Hasarli CD/DVD'den inatci dosya kurtarma
    ================================================================
    v2 YENILIKLERI:
      * ZAMAN ASIMI: bir okuma N saniyede gelmezse GERCEKTEN iptal edilir
        (asenkron G/C + CancelIoEx). Donma sorununun asil cozumu budur.
      * CANLI DURUM: 3 saniyeden uzun suren her okuma ekrana yazilir.
        Ekranda hareket varsa program donmamis, calisiyor demektir.
      * LOG DOSYASI: her olay zaman damgali kaydedilir (teshis icin).
      * UYKU ENGELI: calisirken Windows'un uyumasini engeller.
      * TOPARLANMA: surucu USB'den duserse bekler, geri gelince devam eder.
      * TERS GECIS: bozuk bolgelere sondan da yaklasir (daha cok veri kurtarir).
      * KLASOR MODU: bir klasordeki butun dosyalari sirayla kurtarir.
      * QuickEdit kapatilir (pencereye tiklayinca islem durmasin diye).

    KULLANIM - TEK DOSYA:
      .\CD-Kurtar.ps1 -Kaynak "E:\MPEGAV\AVSEQ01.DAT" -Hedef "C:\...\video1.DAT"

    KULLANIM - TUM DISK (klasor modu):
      .\CD-Kurtar.ps1 -Klasor "E:\" -Hedef "C:\...\disk1"

    Yarida kesilirse ayni komutu tekrar calistir; kaldigi yerden devam eder.
#>
[CmdletBinding(DefaultParameterSetName='Dosya')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='Dosya')][string]$Kaynak,
    [Parameter(Mandatory=$true, ParameterSetName='Klasor')][string]$Klasor,
    [Parameter(Mandatory=$true)][string]$Hedef,
    [int]$Gecis      = 6,
    [int]$Deneme     = 3,
    [int]$Hiz        = 4,
    [int]$KayitSn    = 20,
    [int]$ZamanAsimi = 0,     # 0 = gecise gore otomatik
    [switch]$Rapor            # sadece mevcut durumu yaz, okuma yapma
)

$ErrorActionPreference = 'Stop'
$SEKTOR   = 2048
$script:LogYolu = $null

# ================================================================ yardimcilar

function Yaz-Log {
    param([string]$Mesaj, [string]$Seviye = 'BILGI')
    $satir = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Seviye, $Mesaj
    if ($script:LogYolu) { try { Add-Content -Path $script:LogYolu -Value $satir -Encoding UTF8 } catch {} }
}

function Yaz-Ekran {
    param([string]$Mesaj, [string]$Renk = 'Gray', [switch]$Loglama)
    Write-Host $Mesaj -ForegroundColor $Renk
    if ($Loglama) { Yaz-Log $Mesaj }
}

# --- Windows API'leri (uyku engeli, konsol, surucu hizi) ---
if (-not ('Win32.Sys' -as [type])) {
    Add-Type -Namespace Win32 -Name Sys -MemberDefinition '
[DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern IntPtr CreateFile(string name, uint access, uint share,
    IntPtr sec, uint disp, uint flags, IntPtr templ);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool DeviceIoControl(IntPtr h, uint code, byte[] inBuf,
    uint inSize, IntPtr outBuf, uint outSize, out uint ret, IntPtr ov);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool CloseHandle(IntPtr h);
'
}

function Engelle-Uyku {
    # DIKKAT: PowerShell'de -bor uint32'yi Int32'ye dusurur ve 0x80000000 tasar.
    # Bu yuzden birlesik degerler ondalik sabit olarak yazildi:
    #   ES_CONTINUOUS(0x80000000) + ES_SYSTEM_REQUIRED(1) + ES_AWAYMODE_REQUIRED(0x40) = 2147483713
    #   ES_CONTINUOUS + ES_SYSTEM_REQUIRED                                             = 2147483649
    try {
        $r = [Win32.Sys]::SetThreadExecutionState([uint32]2147483713)
        if ($r -ne 0) { return $true }
        $r = [Win32.Sys]::SetThreadExecutionState([uint32]2147483649)
        return ($r -ne 0)
    } catch { return $false }
}
function Serbest-Birak-Uyku {
    try { [void][Win32.Sys]::SetThreadExecutionState([uint32]2147483648) } catch {}   # ES_CONTINUOUS
}

function Kapat-QuickEdit {
    try {
        $h = [Win32.Sys]::GetStdHandle(-10)   # STD_INPUT_HANDLE
        $m = 0
        if ([Win32.Sys]::GetConsoleMode($h, [ref]$m)) {
            $yeni = ($m -band (-bnot 0x0040)) -bor 0x0080   # QUICK_EDIT kapat, EXTENDED_FLAGS ac
            [void][Win32.Sys]::SetConsoleMode($h, $yeni)
            return $true
        }
    } catch {}
    return $false
}

function Set-OkumaHizi {
    param([string]$Surucu, [int]$Kat)
    if ($Kat -le 0) { return "dokunulmadi" }
    try {
        $h = [Win32.Sys]::CreateFile("\\.\$Surucu", 0xC0000000, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
        if ($h -eq [IntPtr]::Zero -or $h -eq [IntPtr](-1)) { return "surucu acilamadi (sorun degil)" }
        $buf = New-Object byte[] 12
        [BitConverter]::GetBytes([int]0).CopyTo($buf, 0)
        [BitConverter]::GetBytes([uint16]($Kat * 176)).CopyTo($buf, 4)
        [BitConverter]::GetBytes([uint16]65535).CopyTo($buf, 6)
        [BitConverter]::GetBytes([int]0).CopyTo($buf, 8)
        $r = 0
        $ok = [Win32.Sys]::DeviceIoControl($h, 0x00024060, $buf, 12, [IntPtr]::Zero, 0, [ref]$r, [IntPtr]::Zero)
        [void][Win32.Sys]::CloseHandle($h)
        if ($ok) { return "$Kat" + "x (yavas) olarak ayarlandi" }
        return "surucu kabul etmedi (sorun degil)"
    } catch { return "ayarlanamadi (sorun degil)" }
}

# ================================================================ harita

function Kaydet-Harita {
    param([string]$Yol, [byte[]]$D, [long]$Uzunluk)
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("# CD-Kurtar harita v1")
    [void]$sb.AppendLine("LEN $Uzunluk")
    $i = 0
    while ($i -lt $D.Length) {
        $s = $D[$i]; $j = $i
        while ($j -lt $D.Length -and $D[$j] -eq $s) { $j++ }
        [void]$sb.AppendLine("$i $($j - $i) $s")
        $i = $j
    }
    [IO.File]::WriteAllText($Yol, $sb.ToString())
}

function Yukle-Harita {
    param([string]$Yol, [int]$Adet, [long]$Uzunluk)
    if (-not (Test-Path $Yol)) { return $null }
    try {
        $satir = [IO.File]::ReadAllLines($Yol)
        if ($satir.Length -lt 2 -or $satir[1] -ne "LEN $Uzunluk") { return $null }
        $D = New-Object byte[] $Adet
        for ($n = 2; $n -lt $satir.Length; $n++) {
            $s = $satir[$n]
            if ([string]::IsNullOrWhiteSpace($s)) { continue }
            $p = $s -split ' '
            $bas = [int]$p[0]; $adt = [int]$p[1]; $dur = [byte]$p[2]
            if ($dur -ne 0) { for ($k = $bas; $k -lt $bas + $adt -and $k -lt $Adet; $k++) { $D[$k] = $dur } }
        }
        return $D
    } catch { return $null }
}

function Ozet-Eksikler {
    param([byte[]]$D, [int]$EnFazla = 12)
    $liste = @(); $i = 0
    while ($i -lt $D.Length) {
        if ($D[$i] -ne 1) {
            $j = $i
            while ($j -lt $D.Length -and $D[$j] -ne 1) { $j++ }
            $liste += ,@($i, ($j - $i))
            $i = $j
        } else { $i++ }
    }
    return ,$liste
}

# ================================================================ zaman asimli okuma
# Donus: >=0 okunan bayt | -1 okuma hatasi | -2 ZAMAN ASIMI (asildi)

function Oku-ZamanAsimli {
    param($fs, [long]$Ofset, [int]$Adet, [byte[]]$Tampon, [int]$SaniyeSiniri)
    $ms = $SaniyeSiniri * 1000
    try { $fs.Position = $Ofset } catch { return -1 }
    $alinan = 0
    while ($alinan -lt $Adet) {
        $cts = New-Object Threading.CancellationTokenSource
        try {
            $cts.CancelAfter($ms)
            $t = $fs.ReadAsync($Tampon, $alinan, ($Adet - $alinan), $cts.Token)
            # CancelAfter tetiklenirse task iptal olur; yine de sert bir ust sinir koyuyoruz
            if (-not $t.Wait($ms + 5000)) { return -2 }
            if ($t.IsCanceled) { return -2 }
            $n = $t.Result
            if ($n -le 0) { break }
            $alinan += $n
        }
        catch [System.AggregateException] {
            $ic = $_.Exception.InnerException
            if ($ic -is [System.OperationCanceledException]) { return -2 }
            return -1
        }
        catch { return -1 }
        finally { $cts.Dispose() }
    }
    return $alinan
}

# ================================================================ akis yonetimi

function Ac-Kaynak {
    param([string]$Yol)
    # Asynchronous = overlapped G/C  -> iptal (CancelIoEx) gercekten calisir
    # RandomAccess = Windows'un ileri-okuma tahminini azaltir (bozuk diskte onemli)
    $sec = [IO.FileOptions]::Asynchronous -bor [IO.FileOptions]::RandomAccess
    return New-Object IO.FileStream($Yol, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite, 4096, $sec)
}

function Bekle-Surucu {
    param([string]$Yol, [int]$AzamiSaniye = 180)
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $AzamiSaniye) {
        if (Test-Path $Yol) {
            try { $s = Ac-Kaynak $Yol; return $s } catch {}
        }
        Start-Sleep -Seconds 5
        Write-Host "    ...surucu bekleniyor ($([int]((Get-Date)-$t0).TotalSeconds) sn)" -ForegroundColor DarkYellow
    }
    return $null
}

# ================================================================ ANA KURTARMA

function Kurtar-Dosya {
    param([string]$Kaynak, [string]$Hedef, [int]$Gecis, [int]$Deneme, [int]$KayitSn, [int]$ZamanAsimi, [switch]$Rapor)

    if (-not (Test-Path $Kaynak)) { Yaz-Ekran "  ! Kaynak yok: $Kaynak" 'Red' -Loglama; return $null }
    $UZUNLUK  = (Get-Item $Kaynak).Length
    if ($UZUNLUK -le 0) { Yaz-Ekran "  ! Bos dosya, atlandi: $Kaynak" 'Yellow' -Loglama; return $null }
    $BLOKADET = [int][Math]::Ceiling($UZUNLUK / $SEKTOR)
    $HARITA   = "$Hedef.harita"

    $durum = Yukle-Harita -Yol $HARITA -Adet $BLOKADET -Uzunluk $UZUNLUK
    $devam = $true
    if (-not $durum) { $durum = New-Object byte[] $BLOKADET; $devam = $false }

    $iyiToplam = 0
    foreach ($b in $durum) { if ($b -eq 1) { $iyiToplam++ } }

    Write-Host ""
    Yaz-Ekran "  DOSYA : $Kaynak" 'White' -Loglama
    Yaz-Ekran ("  Boyut : {0} bayt ({1} MB / {2} sektor)" -f $UZUNLUK, [math]::Round($UZUNLUK/1MB,1), $BLOKADET) 'Gray'
    if ($devam) { Yaz-Ekran "  Durum : onceki oturumdan devam ($iyiToplam sektor hazir)" 'Yellow' -Loglama }

    if ($Rapor) {
        $eks = Ozet-Eksikler $durum
        Yaz-Ekran ("  Kurtarilan: {0}/{1} (%{2})" -f $iyiToplam, $BLOKADET, [math]::Round(100*$iyiToplam/$BLOKADET,2)) 'Green'
        Yaz-Ekran ("  Eksik bolge sayisi: {0}" -f $eks.Count) 'Yellow'
        $g = 0
        foreach ($e in $eks) { if ($g -ge 12) { break }; Yaz-Ekran ("    sektor {0} - {1}  ({2} MB civari)" -f $e[0], ($e[0]+$e[1]-1), [math]::Round($e[0]*$SEKTOR/1MB,1)) 'DarkYellow'; $g++ }
        return @{ Iyi = $iyiToplam; Toplam = $BLOKADET }
    }

    $dizin = Split-Path -Parent $Hedef
    if ($dizin -and -not (Test-Path $dizin)) { New-Item -ItemType Directory -Path $dizin -Force | Out-Null }

    $fsIn = $null; $fsOut = $null
    $sayac = [Diagnostics.Stopwatch]::StartNew()
    $sonKayit = 0.0; $sonYazi = 0.0
    $asilmaSayisi = 0; $hataSayisi = 0

    try {
        $fsIn  = Ac-Kaynak $Kaynak
        $fsOut = New-Object IO.FileStream($Hedef, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::Read, 4096, [IO.FileOptions]::None)
        if ($fsOut.Length -ne $UZUNLUK) { $fsOut.SetLength($UZUNLUK) }

        # gecis plani: blok(sektor), yon, deneme, zaman asimi(sn)
        $plan = @(
            @{ Blok = 32; Ters = $false; Tekrar = 1;       ZA = 10 },
            @{ Blok = 8;  Ters = $true;  Tekrar = 1;       ZA = 15 },
            @{ Blok = 2;  Ters = $false; Tekrar = 1;       ZA = 20 },
            @{ Blok = 1;  Ters = $true;  Tekrar = $Deneme; ZA = 30 },
            @{ Blok = 1;  Ters = $false; Tekrar = $Deneme; ZA = 30 },
            @{ Blok = 1;  Ters = $true;  Tekrar = $Deneme; ZA = 45 }
        )

        for ($g = 1; $g -le $Gecis; $g++) {
            $p = $plan[[Math]::Min($g - 1, $plan.Count - 1)]
            $blokSek = $p.Blok; $ters = $p.Ters; $tekrar = $p.Tekrar
            $za = $p.ZA
            if ($ZamanAsimi -gt 0) { $za = $ZamanAsimi }

            $kalan = $BLOKADET - $iyiToplam
            if ($kalan -le 0) { Yaz-Ekran "  Tamami kurtarildi, kalan gecise gerek yok." 'Green' -Loglama; break }

            $yonAd = 'ileri'; if ($ters) { $yonAd = 'GERI' }
            Yaz-Ekran ("  --- GECIS {0}/{1} | blok {2} sektor | yon {3} | deneme {4} | zaman asimi {5} sn | kalan {6} sektor" -f $g, $Gecis, $blokSek, $yonAd, $tekrar, $za, $kalan) 'Yellow' -Loglama

            # islenecek parcalari topla
            $parca = New-Object Collections.ArrayList
            $i = 0
            while ($i -lt $BLOKADET) {
                if ($durum[$i] -eq 1) { $i++; continue }
                $n = 0
                while ($n -lt $blokSek -and ($i + $n) -lt $BLOKADET -and $durum[$i + $n] -ne 1) { $n++ }
                [void]$parca.Add(@($i, $n))
                $i += $n
            }
            if ($ters) { $parca.Reverse() }

            $buf = New-Object byte[] ($blokSek * $SEKTOR)

            foreach ($pr in $parca) {
                $i = $pr[0]; $n = $pr[1]
                # arada baska gecis doldurmus olabilir
                $halaGerekli = $false
                for ($k = 0; $k -lt $n; $k++) { if ($durum[$i + $k] -ne 1) { $halaGerekli = $true; break } }
                if (-not $halaGerekli) { continue }

                $ofs = [long]$i * $SEKTOR
                $ist = [int][Math]::Min([long]($n * $SEKTOR), $UZUNLUK - $ofs)
                $basarili = $false

                for ($d = 0; $d -lt $tekrar -and -not $basarili; $d++) {
                    $krono = [Diagnostics.Stopwatch]::StartNew()
                    $sonuc = Oku-ZamanAsimli -fs $fsIn -Ofset $ofs -Adet $ist -Tampon $buf -SaniyeSiniri $za
                    $krono.Stop()

                    if ($krono.Elapsed.TotalSeconds -ge 3) {
                        $d2 = 'OK'; if ($sonuc -eq -1) { $d2 = 'HATA' } elseif ($sonuc -eq -2) { $d2 = 'ASILDI' }
                        Yaz-Ekran ("    yavas okuma: sektor {0} | {1:N1} sn | {2}" -f $i, $krono.Elapsed.TotalSeconds, $d2) 'DarkYellow'
                        Yaz-Log ("yavas okuma sektor=$i sure=$([math]::Round($krono.Elapsed.TotalSeconds,1))sn sonuc=$d2") 'IZLE'
                    }

                    if ($sonuc -eq $ist) {
                        $fsOut.Position = $ofs
                        $fsOut.Write($buf, 0, $sonuc)
                        for ($k = 0; $k -lt $n; $k++) {
                            if ($durum[$i + $k] -ne 1) { $iyiToplam++ }
                            $durum[$i + $k] = 1
                        }
                        $basarili = $true
                    }
                    elseif ($sonuc -eq -2) {
                        $asilmaSayisi++
                        Yaz-Log "ZAMAN ASIMI sektor=$i blok=$n -> akis yeniden aciliyor" 'UYARI'
                        # asilan akisi at, yenisini ac (bozuk durumda kalmis olabilir)
                        try { $fsIn.Dispose() } catch {}
                        $fsIn = $null
                        Start-Sleep -Milliseconds 500
                        try { $fsIn = Ac-Kaynak $Kaynak }
                        catch {
                            Yaz-Ekran "    ! Surucu kayboldu. Geri gelmesi bekleniyor..." 'Red' -Loglama
                            $fsOut.Flush(); Kaydet-Harita -Yol $HARITA -D $durum -Uzunluk $UZUNLUK
                            $fsIn = Bekle-Surucu -Yol $Kaynak
                            if (-not $fsIn) { Yaz-Ekran "    ! Surucu geri gelmedi. Ilerleme kaydedildi, cikiliyor." 'Red' -Loglama; return @{ Iyi = $iyiToplam; Toplam = $BLOKADET; Kesildi = $true } }
                            Yaz-Ekran "    Surucu geri geldi, devam ediliyor." 'Green' -Loglama
                        }
                    }
                    elseif ($sonuc -eq -1) {
                        $hataSayisi++
                        Start-Sleep -Milliseconds 150
                    }
                }

                if (-not $basarili -and $blokSek -eq 1) { $durum[$i] = 2 }

                $gecen = $sayac.Elapsed.TotalSeconds
                if ($gecen - $sonYazi -ge 3) {
                    Write-Host ("    %{0} | kurtarilan {1} MB | sektor {2}/{3} | gecen {4} | asilma {5} hata {6}" -f `
                        [math]::Round(100*$iyiToplam/$BLOKADET,2), [math]::Round($iyiToplam*$SEKTOR/1MB,1),
                        $i, $BLOKADET, $sayac.Elapsed.ToString('hh\:mm\:ss'), $asilmaSayisi, $hataSayisi)
                    $sonYazi = $gecen
                }
                if ($gecen - $sonKayit -ge $KayitSn) {
                    $fsOut.Flush(); Kaydet-Harita -Yol $HARITA -D $durum -Uzunluk $UZUNLUK
                    $sonKayit = $gecen
                }
            }
        }
    }
    finally {
        if ($fsOut) { try { $fsOut.Flush(); $fsOut.Close() } catch {} }
        if ($fsIn)  { try { $fsIn.Dispose() } catch {} }
        if ($durum) { Kaydet-Harita -Yol $HARITA -D $durum -Uzunluk $UZUNLUK }
        $sayac.Stop()
    }

    $iyi = 0
    foreach ($b in $durum) { if ($b -eq 1) { $iyi++ } }
    $eksik = $BLOKADET - $iyi
    $yuzde = [math]::Round(100*$iyi/$BLOKADET, 2)
    $renk = 'Green'; if ($eksik -gt 0) { $renk = 'Red' }
    Yaz-Ekran ("  SONUC: {0}/{1} sektor (%{2}) | okunamayan {3} sektor ({4} MB) | sure {5}" -f `
        $iyi, $BLOKADET, $yuzde, $eksik, [math]::Round($eksik*$SEKTOR/1MB,2), $sayac.Elapsed.ToString('hh\:mm\:ss')) $renk -Loglama
    Yaz-Log "asilma=$asilmaSayisi okuma_hatasi=$hataSayisi"

    if ($eksik -gt 0) {
        $eks = Ozet-Eksikler $durum
        Yaz-Log ("eksik bolge sayisi=" + $eks.Count)
        $g = 0
        foreach ($e in $eks) { if ($g -ge 40) { break }; Yaz-Log ("  eksik sektor {0}-{1} ({2} adet)" -f $e[0], ($e[0]+$e[1]-1), $e[1]); $g++ }
    }
    return @{ Iyi = $iyi; Toplam = $BLOKADET; Yuzde = $yuzde }
}

# ================================================================ GIRIS

$script:LogYolu = Join-Path (Split-Path -Parent $PSCommandPath) ("kurtarma-log-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  CD-KURTAR  v2" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

$qe = Kapat-QuickEdit
$uy = Engelle-Uyku
Write-Host ("  QuickEdit  : " + $(if ($qe) { "kapatildi (yanlislikla tiklayinca durmaz)" } else { "kapatilamadi - pencereye TIKLAMA!" }))
Write-Host ("  Uyku engeli: " + $(if ($uy) { "aktif" } else { "kurulamadi - uyku ayarini elle kapat!" }))
Write-Host ("  Log        : $script:LogYolu")

Yaz-Log "=== CD-Kurtar v2 basladi ==="

if ($PSCmdlet.ParameterSetName -eq 'Klasor') {
    if (-not (Test-Path $Klasor)) { throw "Klasor bulunamadi: $Klasor" }
    $surucu = Split-Path -Qualifier (Resolve-Path $Klasor).Path
    Write-Host ("  Okuma hizi : " + (Set-OkumaHizi -Surucu $surucu -Kat $Hiz))
    Write-Host "  MOD        : KLASOR (tum dosyalar)"
    Write-Host "=======================================================" -ForegroundColor Cyan
    Yaz-Log "mod=klasor kaynak=$Klasor hedef=$Hedef"

    $kok = (Resolve-Path $Klasor).Path.TrimEnd('\')
    $dosyalar = @(Get-ChildItem -Path $Klasor -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object Length)
    Yaz-Ekran ("  Bulunan dosya: {0} adet" -f $dosyalar.Count) 'White' -Loglama

    $sira = 0; $ozet = @()
    foreach ($f in $dosyalar) {
        $sira++
        $rel = $f.FullName.Substring($kok.Length).TrimStart('\')
        $hed = Join-Path $Hedef $rel
        Write-Host ""
        Yaz-Ekran ("[{0}/{1}] {2}" -f $sira, $dosyalar.Count, $rel) 'Cyan' -Loglama
        $r = Kurtar-Dosya -Kaynak $f.FullName -Hedef $hed -Gecis $Gecis -Deneme $Deneme -KayitSn $KayitSn -ZamanAsimi $ZamanAsimi -Rapor:$Rapor
        if ($r) { $ozet += [pscustomobject]@{ Dosya = $rel; Yuzde = $r.Yuzde; Iyi = $r.Iyi; Toplam = $r.Toplam } }
    }

    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "  TUM DISK OZETI" -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    $ozet | Format-Table -AutoSize
    $tamam = @($ozet | Where-Object { $_.Yuzde -eq 100 }).Count
    Yaz-Ekran ("  Tam kurtarilan: {0}/{1} dosya" -f $tamam, $ozet.Count) 'Green' -Loglama
}
else {
    $surucu = Split-Path -Qualifier $Kaynak
    Write-Host ("  Okuma hizi : " + (Set-OkumaHizi -Surucu $surucu -Kat $Hiz))
    Write-Host "  MOD        : TEK DOSYA"
    Write-Host "=======================================================" -ForegroundColor Cyan
    Yaz-Log "mod=dosya kaynak=$Kaynak hedef=$Hedef"
    $null = Kurtar-Dosya -Kaynak $Kaynak -Hedef $Hedef -Gecis $Gecis -Deneme $Deneme -KayitSn $KayitSn -ZamanAsimi $ZamanAsimi -Rapor:$Rapor
}

Serbest-Birak-Uyku
Yaz-Log "=== bitti ==="
Write-Host ""
Write-Host "  Log dosyasi: $script:LogYolu" -ForegroundColor Cyan
Write-Host "  Eksik kaldiysa AYNI komutu tekrar calistir - kaldigi yerden devam eder." -ForegroundColor Yellow
Write-Host ""
