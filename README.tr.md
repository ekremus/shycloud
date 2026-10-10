# ShyCloud — Mac'te iCloud Drive senkronunu zamanlayarak duraklatın

[English](README.md)

**ShyCloud**, çalışırken **iCloud Drive senkronunu duraklatan** ve yalnızca seçtiğiniz saatlerde — varsayılan **02:00–09:00** — çalıştıran ücretsiz, açık kaynaklı bir menü çubuğu uygulamasıdır. Gün içinde `bird`'ün işlemciyi ve diski yemesine, Finder takılmalarına, git ve Xcode'un iCloud'la kavga etmesine son.

- ☁️ **Zamanlı senkron** — iCloud Drive yalnızca belirlediğiniz saatlerde senkronlanır
- ⏸ **Senkron Kapalı** — tatil / seyahat / mobil internet modu
- ▶️ **Senkron Açık** — normal iCloud, tek tık
- 🛟 **Önce güvenlik** — çıkışta, uykuda, oturum kapatınca ve çökmede iCloud her zaman geri açılır
- 🌙 **Telafi** — gece Mac uykudaysa uyanınca 30 dakika senkronlar
- 🫥 **Gizlenebilir** — menü ikonunu kaldırın, arka planda çalışmaya devam eder
- 🍎 Apple Silicon · macOS 26+ · Türkçe & English · takip yok, hesap yok

## Kurulum

- **İndir:** [Releases](https://github.com/ekremus/shycloud/releases/latest) sayfasından Apple onaylı DMG
- **Homebrew:** `brew install --cask ekremus/tap/shycloud`

## Nasıl çalışır

macOS'ta iCloud Drive'ı duraklatmak için resmi bir düğme yok. ShyCloud, iCloud Drive işlemi `bird`'ü `kill -STOP` / `kill -CONT` ile dondurur ve çözer — güvenli ve otomatik biçimde:

- Yalnızca **sizin** işlemlerinize, **tam sistem yoluyla** eşleşerek dokunur (asla isimle değil — iOS Simülatörü kopyalarına dokunmaz).
- Her işlemi sinyal göndermeden hemen önce yeniden doğrular.
- Küçük bir **güvenlik yardımcısı**, ShyCloud beklenmedik şekilde kapanırsa ~3 dakika içinde iCloud'u açar.
- Hiçbir işlem öldürülmez, hiçbir şey silinmez. Yeniden başlatınca iCloud normale döner.

## Bilmeniz gerekenler

- **Yalnızca iCloud'da duran dosyalar** (Finder'da bulut simgeli) duraklatılmışken açılamaz. **Senkron Açık**'ı seçin veya *Mac Depolamasını Optimize Et*'i kapatın.
- **Neden App Store'da yok?** App Store uygulamaları başka işlemleri duraklatamayan bir korumalı alanda çalışır.
- **Her şeyi nasıl geri alırım?** *Senkron Açık*'ı seçin, ShyCloud'dan çıkın ya da Mac'i yeniden başlatın.

## Lisans

GPL-3.0-or-later — sonsuza kadar ücretsiz; dağıtılan her sürüm açık kaynak kalmak zorundadır. Katkılar MIT lisansıyla kabul edilir ([CONTRIBUTING.md](CONTRIBUTING.md)).

Apple ile bağlantılı değildir. iCloud, Apple Inc.'in ticari markasıdır.
