# Maintainer: Pocknix Team <pocknix@example.com>
# DeckStation x86_64 — versión para PC / Steam Deck (proyecto original, más completo).
# NO usar en ARM: existe el proyecto DeckStation ARM aparte (pocknix-deckstation).
pkgname=pocknix-deckstation-x86_64
pkgver=1.0.0
pkgrel=1
pkgdesc="Sistema de emulación portable para x86_64 (DeckStation PC) — integrado en Pocknix"
arch=('x86_64')
url="https://github.com/arcadematicas/pocknix-deckstation-x86_64"
license=('GPL2')
provides=('pocknix-deckstation')
conflicts=('pocknix-deckstation')
depends=(
    'python'
    'python-requests'
    'gamemode'
)
makedepends=()
optdepends=(
    'retroarch: emulador multi-sistema (o usar el portable en Apps/)'
    'vulkan-icd-loader: soporte Vulkan'
    'pipewire-pulse: audio moderno'
    'pulseaudio: audio del sistema'
)
source=()
sha256sums=()
install=pocknix-deckstation-x86_64.install

package() {
    # Directorio base
    install -dm755 "${pkgdir}/opt/deckstation"

    # Scripts del sistema
    install -dm755 "${pkgdir}/opt/deckstation/scripts"
    cp -r scripts/* "${pkgdir}/opt/deckstation/scripts/"
    chmod +x "${pkgdir}/opt/deckstation/scripts/"*.sh 2>/dev/null || true
    chmod +x "${pkgdir}/opt/deckstation/scripts/"*.py 2>/dev/null || true

    # Configs de emuladores (portables, rutas relativas)
    install -dm755 "${pkgdir}/opt/deckstation/configs"
    cp -r configs/* "${pkgdir}/opt/deckstation/configs/"

    # evmapy (mapeo de mandos)
    install -dm755 "${pkgdir}/opt/deckstation/evmapy"
    cp -r evmapy/* "${pkgdir}/opt/deckstation/evmapy/"

    # Overlay: comando del sistema
    install -Dm755 overlay/usr/bin/deckstation \
        "${pkgdir}/usr/bin/deckstation"

    # Estructura de directorios (se crearán en post-install)
    install -dm755 "${pkgdir}/opt/deckstation/Apps"
    install -dm755 "${pkgdir}/opt/deckstation/saves"
    install -dm755 "${pkgdir}/opt/deckstation/logs"
    install -dm755 "${pkgdir}/opt/deckstation/Media"
    install -dm755 "${pkgdir}/opt/deckstation/settings"
}
