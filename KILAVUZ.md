# CDSaver Kılavuzu

## Her seferinde, sırayla

**0. Hazırlık (yalnız ilk sefer)**

- Otomatik Kullan kapalı olmalı: Ayarlar > Bluetooth ve cihazlar > Otomatik Kullan > kapat.
- Uykuyu araç kendisi engeller, ekstra bir şey yapmanıza gerek yok.
- Harici USB sürücü kullanıyorsanız ve kablosu iki uçluysa (Y kablo) ikisini de takın. Tek uçla güç yetmez, sürücü okuma sırasında düşer.

**1.** Diski takın. Açılan pencereyi kapatın. Diski Windows Gezgini'nde açmayın, üstüne çift tıklamayın, önizleme yaptırmayın. Donmaların çoğunun sebebi budur.

**2.** PowerShell açın: Başlat > "PowerShell" yazın > Enter. Aracı bu pencerede çalıştırın. Kilitlenirse yalnız bu pencereyi kapatırsınız, sistemin tamamı donmaz.

**3.** Diskte ne var görün:

```powershell
cmd /c dir /s /b E:\
```

**4.** Kurtarmayı başlatın. `E:` yerine kendi sürücü harfinizi yazın.

Bütün disk (fotoğraf, karışık dosya, her şey):

```powershell
powershell -ExecutionPolicy Bypass -File ".\CDSaver.ps1" -Klasor E:\\ -Hedef "C:\Kurtarilan\disk1"
```

Tek dosya (VCD videosu gibi):

```powershell
powershell -ExecutionPolicy Bypass -File ".\CDSaver.ps1" -Kaynak "E:\MPEGAV\AVSEQ01.DAT" -Hedef "C:\Kurtarilan\disk1.DAT"
```

Not: Sürücü kökü için `E:\\` yazın (iki ters bölü). Tek ters bölü ile tırnak içinde yazarsanız Windows tırnağı bozar.

**5.** Bekleyin. Ekranda ne görürseniz ne demek:

| Ekranda | Anlamı |
|---|---|
| `%12,4 \| kurtarilan 63 MB \| sektor 31000/262420 \| gecen 00:14:22` | Normal çalışıyor. Bu satır sürekli yenilenir. |
| `yavas okuma: sektor 48213 \| 12,4 sn \| OK` | Zor bir yer, ama okudu. İyi haber. |
| `yavas okuma: sektor 48213 \| 30,0 sn \| ASILDI` | Sürücü takıldı, araç iptal etti ve devam ediyor. Donmadı. Müdahale etmeyin. |
| `...surucu bekleniyor (25 sn)` | Sürücü USB'den düştü. Araç bekliyor. Kabloyu kontrol edin, gerekirse çıkarıp takın. Geri gelince kaldığı yerden devam eder. |
| `--- GECIS 3/6 \| blok 8 sektor \| yon geri` | Yeni geçişe başladı: daha küçük parçalarla, bu kez tersten. |

**6.** Bitince `SONUC` satırına bakın.

```
SONUC: 262421/262421 sektor (%100) | okunamayan 0 sektor (0 MB) | sure 00:03:20
```

%100 ise iş bitti. Değilse aynı komutu tekrar çalıştırın, kaldığı yerden devam eder. Üç dört kez tekrarlayın. Sonra diski çıkarın, yumuşak bezle merkezden dışarı doğru silin (dairesel değil), tekrar takın, tekrar çalıştırın.

## Faydalı komutlar

Okuma yapmadan sadece durumu öğrenmek (ne kadarı kurtarılmış, nerede eksik var):

```powershell
... -Kaynak "E:\MPEGAV\AVSEQ01.DAT" -Hedef "C:\Kurtarilan\disk1.DAT" -Rapor
```

Daha çok geçiş (inatçı disk için, uzun sürer):

```powershell
... -Gecis 10 -Deneme 5
```

Zaman aşımını uzatmak (sürücüye daha çok şans verir, çok yavaşlatır):

```powershell
... -ZamanAsimi 60
```

Okuma hızını değiştirmek (varsayılan 4x yavaş; 0 = dokunma):

```powershell
... -Hiz 2
```

## Kurtarılan videoyu izlemek

VCD (`.DAT`):

```powershell
ffmpeg -fflags +genpts -i disk1.DAT -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k disk1.mp4
```

DVD-Video (`VIDEO_TS` klasörü, iki parça VOB):

```powershell
ffmpeg -fflags +genpts -i "concat:VIDEO_TS\VTS_01_1.VOB|VIDEO_TS\VTS_01_2.VOB" -map 0:v:0 -map 0:a:0 -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k dugun.mp4
```

ffmpeg'i [ffmpeg.org](https://ffmpeg.org/download.html) adresinden ya da `winget install ffmpeg` ile kurabilirsiniz.

## Önemli notlar

- Yarıda kesilirse, bilgisayar çökerse, elektrik giderse hiçbir şey kaybolmaz. Hedef dosyanın yanındaki `.harita` dosyası nerede kalındığının kaydıdır. En fazla son 20 saniyelik ilerleme kaybolur.
- PowerShell penceresine yanlışlıkla tıklamayın. Tıklarsanız program durur (Windows'un seçim modu). Araç bunu kapatmaya çalışır ama her konsolda başaramaz. Yanlışlıkla tıkladıysanız Esc'e basın, devam eder.
- İşlem sırasında bilgisayarı başka iş için kullanmayın, diske dokunmayın, şarj kablosunu takılı tutun.
- Disk çok kötüyse aynı diski başka marka bir sürücüde denemek çok sık işe yarar. Kurtarma işinde en etkili tek numara budur.
- Önce sağlam diskleri bitirin, en sorunlu diski en sona bırakın.

## Parametreler

| Parametre | Varsayılan | Ne yapar |
|---|---|---|
| `-Kaynak` | | Kurtarılacak tek dosya |
| `-Klasor` | | Kurtarılacak klasör ya da sürücü kökü (bütün dosyalar) |
| `-Hedef` | | Çıktı dosyası ya da klasörü |
| `-Gecis` | 6 | Kaç geçiş yapılacağı |
| `-Deneme` | 3 | Son geçişlerde sektör başına kaç deneme |
| `-Hiz` | 4 | Sürücü okuma hızı çarpanı; 0 dokunmaz |
| `-KayitSn` | 20 | Haritanın kaç saniyede bir kaydedileceği |
| `-ZamanAsimi` | 0 | Tek okuma için saniye; 0 geçişe göre otomatik (10, 20, 30...) |
| `-Rapor` | | Okuma yapmadan mevcut durumu yazar |
