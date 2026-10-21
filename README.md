<p align="center"><img src="docs/logo.png" width="150" alt="CDSaver logosu"></p>

# CDSaver

**Çizik, eski, okunmayan CD ve DVD'lerden dosya kurtaran küçük bir Windows aracı.**

Bilgisayarınız bir diski açmaya çalışırken donuyor, sürücü takılıyor, dosya kopyalama yarıda kalıyor mu? CDSaver bu diskleri sabırla, parça parça okur. Okuyabildiğini kaydeder, okuyamadığını not alır, sonra geri dönüp tekrar dener. Bilgisayar kapansa, kablo çekilse bile kaldığı yerden devam eder.

Bu araç, 1989 ile 1996 arasından görüntüler taşıyan, yaklaşık yirmi yıllık dört diski kurtarmak için yazıldı. Dördü de eksiksiz kurtarıldı.

[![Claude Code ile yapıldı](https://img.shields.io/badge/Claude%20Code%20ile%20yap%C4%B1ld%C4%B1-D97757?style=flat&logo=anthropic&logoColor=white)](https://claude.com/claude-code)
[![Lisans: MIT](https://img.shields.io/badge/Lisans-MIT-green.svg)](LICENSE)

---

## Ne işe yarar

- Hasarlı bir diskteki **tek bir dosyayı** ya da **bütün diski** kurtarır.
- Okuma takılırsa **bekleyip iptal eder**, sistemi dondurmaz. Eski araçların en büyük sorunu buydu.
- **Kaldığı yerden devam eder.** Yarıda kesilirse aynı komutu tekrar çalıştırmanız yeter.
- Bozuk bölgeye **hem baştan hem sondan** yaklaşır, her geçişte daha küçük parçalar dener.
- Sürücü USB'den düşerse **bekler, geri gelince devam eder.**
- Çalışırken bilgisayarın **uyumasını engeller.**
- Her şeyi **Türkçe ve sade** anlatır: yüzde kaçı kurtarıldı, nerede eksik var, ne yapmalısınız.

## Ne değildir

- Sihirli değnek değildir. Fiziksel olarak okunamayan bölgeyi hiçbir yazılım okuyamaz. Ama çoğu "bozuk" disk aslında sabırsız bir sürücü yüzünden okunamıyordur.
- Video onarma aracı değildir. Kurtarılan dosyayı izlenebilir hale getirmek ayrı bir adımdır (aşağıda).
- Kurulum gerektirmez, ek program istemez. Windows 10 ve 11'de gelen PowerShell yeterlidir.

## Nasıl kullanılır

1. **Hazırlık (bir kez):** Windows'un diski otomatik açmasını kapatın: Ayarlar > Bluetooth ve cihazlar > Otomatik Kullan > kapalı. Çünkü Windows diski önizlemeye çalışırken sürücüyü kilitler.
2. Diski takın. Açılan pencereyi kapatın, diske çift tıklamayın.
3. Başlat menüsüne **PowerShell** yazıp açın.
4. Diskte ne olduğunu görün:

```powershell
cmd /c dir /s /b E:\
```

5. Kurtarmayı başlatın. `E:` yerine kendi sürücü harfinizi yazın.

Bütün diski kurtarmak için:

```powershell
powershell -ExecutionPolicy Bypass -File ".\CDSaver.ps1" -Klasor E:\\ -Hedef "C:\Kurtarilan\disk1"
```

Tek bir dosyayı kurtarmak için (örneğin bir VCD videosu):

```powershell
powershell -ExecutionPolicy Bypass -File ".\CDSaver.ps1" -Kaynak "E:\MPEGAV\AVSEQ01.DAT" -Hedef "C:\Kurtarilan\video1.DAT"
```

6. Bekleyin. Ekranda sürekli yenilenen bir satır görürsünüz:

```
%12,4 | kurtarilan 63 MB | sektor 31000/262420 | gecen 00:14:22
```

7. Bitince **SONUC** satırına bakın. %100 ise iş bitti. Değilse aynı komutu tekrar çalıştırın, kaldığı yerden devam eder. Üç dört denemeden sonra diski yumuşak bir bezle **merkezden dışarıya doğru** silin ve tekrar deneyin.

Ayrıntılı kılavuz, ekrandaki her mesajın anlamı ve ileri ayarlar için: [KILAVUZ.md](KILAVUZ.md)

## Kurtarılan videoyu izlemek

VCD disklerindeki `.DAT` dosyaları modern oynatıcılarda açılmaz. Ücretsiz [ffmpeg](https://ffmpeg.org) ile MP4'e çevirin:

```powershell
ffmpeg -fflags +genpts -i video1.DAT -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k video1.mp4
```

DVD disklerindeki `VIDEO_TS\VTS_01_1.VOB`, `VTS_01_2.VOB` dosyaları için aynı komutu `concat:` ile birleştirerek kullanabilirsiniz, örneği kılavuzda.

## Nasıl çalışır (merak edenler için)

Disk 2048 baytlık sektörlerden oluşur. CDSaver dosyayı sektör sektör okur ve yanına bir **harita dosyası** yazar: hangi sektör okundu, hangisi okunmadı. Her 20 saniyede harita kaydedilir, bu yüzden hiçbir ilerleme kaybolmaz.

Asıl numara okuma biçiminde. Normal bir kopyalama işlemi, sürücü takılırsa sonsuza kadar bekler ve Windows'u da kendiyle birlikte dondurur. CDSaver her okumayı zaman sınırlı başlatır; süre dolunca işletim sisteminden okumayı iptal etmesini ister ve o parçayı "sonra" diye işaretler. Altı geçiş yapar: önce 32 sektörlük büyük parçalar, sonra giderek küçülen parçalar, bazı geçişlerde ters yönde. Son geçişte tek sektör tek sektör dener.

Bu yaklaşım, Linux dünyasının bilinen aracı ddrescue'nun mantığıdır. Burada aynı mantık, hiçbir kurulum gerektirmeden Windows'ta çalışacak biçimde PowerShell ile yazıldı.

## Bilinmesi gerekenler

- Araç gerçek hasarlı disklerde **dört kez** kullanıldı ve dördünde de %100 sonuç verdi. Ama bu disklerin hiçbiri yeni sürücüde okuma hatası vermedi. Yani "okunamayan sektör" yolu gerçek bir arızayla henüz sınanmadı. Beklenmedik bir davranış görürseniz lütfen bir sorun kaydı açın.
- Okuma hızını düşürme ayarı (`-Hiz`) her sürücüde çalışmaz. Çalışmazsa araç bunu söyler ve normal hızda devam eder.
- Aynı diski **başka marka bir sürücüde** denemek, kurtarma işinde en etkili tek numaradır.

## Bu araç nasıl yapıldı

CDSaver, [Claude Code](https://claude.com/claude-code) ile birlikte yazıldı. Sorunu ben anlattım, kodu Claude yazdı, test etti, hatalarını birlikte düzelttik. Kurtarma sırasında bilgisayarın donması, uyku modu, USB sürücünün düşmesi gibi her sorun bir sohbet turunda çözüldü. Bu depo, sıradan bir kullanıcının yapay zekâyla ne kadar işe yarar bir araç üretebileceğinin kaydıdır.

Deneyin hikâyesi: [Artcycle LABS, Deneyler](https://artcycle.co)

## Lisans

MIT. İstediğiniz gibi kullanın, değiştirin, paylaşın. Bkz. [LICENSE](LICENSE).
