# ShyCloud — Mac'te iCloud Drive senkronunu zamanlayarak duraklatın

[English](README.md)

**ShyCloud**, çalışırken **iCloud Drive senkronunu duraklatan** ve yalnızca seçtiğiniz saatlerde — varsayılan **02:00–09:00** — çalıştıran ücretsiz, açık kaynaklı bir menü çubuğu uygulamasıdır. Gün içinde `bird`'ün işlemciyi ve diski yemesine, Finder takılmalarına, git ve Xcode'un iCloud'la kavga etmesine son.

- ☁️ **Zamanlı senkron** — iCloud Drive yalnızca belirlediğiniz saatlerde senkronlanır
- ⏸ **Senkron Kapalı** — tatil / seyahat / mobil internet modu
- ▶️ **Senkron Açık** — normal iCloud, tek tık
- 🛟 **Önce güvenlik** — çıkışta, uykuda, oturum kapatınca ve çökmede iCloud geri açılır; uygulamalar iCloud'u beklerken en fazla birkaç saniye bekler, asla kilitlenmez
- 🫥 **Gizlenebilir** — menü ikonunu kaldırın, arka planda çalışmaya devam eder
- 🍎 Apple Silicon · macOS 26+ · uygulama arayüzü İngilizce (README Türkçe de mevcut) · takip yok, hesap yok

## Kurulum

- **İndir:** [Releases](https://github.com/ekremus/shycloud/releases/latest) sayfasından Apple onaylı DMG
- **Homebrew:** `brew install --cask ekremus/tap/shycloud`

## Nasıl çalışır

macOS'ta iCloud Drive'ı duraklatmak için resmi bir düğme yok. ShyCloud, iCloud Drive işlemi `bird`'ü `kill -STOP` / `kill -CONT` ile dondurur ve çözer — güvenli ve otomatik biçimde.

Tamamen dondurulmuş `bird`'ün bir sorunu var: açılışta iCloud'a bir şey soran uygulamalar (Steam, GeForce NOW ve diğer Chromium tabanlı uygulamalar) sonsuza kadar cevap bekler. Bu yüzden ShyCloud **derin duraklatma** kullanır:

- iCloud dondurulur ve **her 2 saniyede bir kısa bir an (0,2 sn) serbest bırakılır**; böylece iCloud'a bir şey soran uygulamalar takılmak yerine en geç 2 saniye civarında cevap alır. Bu yüzden duraklatılmışken iCloud yok denecek kadar az da olsa iş yapar.
- Bir **uygulama açtığınızda** iCloud 10 saniye normal çalışır.
- ShyCloud her 30 saniyede iCloud'un 3 saniye içinde cevap verdiğini kontrol eder. Vermezse 10 dakika normal çalışmasına izin verir, sonra tekrar dener.

Ve her zaman:

- Yalnızca **sizin** işlemlerinize, **tam sistem yoluyla** eşleşerek dokunur (asla isimle değil — iOS Simülatörü kopyalarına dokunmaz).
- Her işlemi sinyal göndermeden hemen önce yeniden doğrular.
- Küçük bir **güvenlik yardımcısı**, ShyCloud beklenmedik şekilde kapanırsa ~3 dakika içinde iCloud'u açar.
- Hiçbir işlem öldürülmez, hiçbir şey silinmez. Yeniden başlatınca iCloud normale döner.

## Bilmeniz gerekenler

- **Yalnızca iCloud'da duran dosyalar** (Finder'da bulut simgeli) duraklatılmışken açılamaz. **Senkron Açık**'ı seçin veya *Mac Depolamasını Optimize Et*'i kapatın.
- **Neden App Store'da yok?** App Store uygulamaları başka işlemleri duraklatamayan bir korumalı alanda çalışır.
- **Her şeyi nasıl geri alırım?** *Senkron Açık*'ı seçin, ShyCloud'dan çıkın ya da Mac'i yeniden başlatın.

## Kaldırma

1. Menüden ShyCloud'dan çıkın (iCloud hemen devam eder).
2. ShyCloud'u Uygulamalar klasöründen silin.

Ya da Homebrew ile: `brew uninstall --cask --zap shycloud`.

Arka plandaki güvenlik yardımcısı uygulamanın parçasıdır ve onunla birlikte kaldırılır. Sistem Ayarları › Genel › Giriş Öğeleri ve Uzantılar'dan da kapatabilirsiniz.

## Gizlilik

Hiçbir veri toplanmaz. Tek ağ erişimi Sparkle güncelleme denetimidir.

## Lisans

GPL-3.0-or-later — sonsuza kadar ücretsiz; dağıtılan her sürüm açık kaynak kalmak zorundadır. Katkılar MIT lisansıyla kabul edilir ([CONTRIBUTING.md](CONTRIBUTING.md)).

Apple ile bağlantılı değildir. iCloud, Apple Inc.'in ticari markasıdır.
