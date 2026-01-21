# Maintainer: Remilia Litjens
pkgname=ember
pkgver=1.0
pkgrel=1
pkgdesc="Ember — a minimal AUR helper written in Ruby"
arch=('x86_64')
license=('GPL')

depends=('ruby' 'curl' 'git')
makedepends=('base-devel')

source=()
sha256sums=()

package() {
    # Use $startdir to reference current folder
    install -Dm755 "$startdir/bin/emb" "$pkgdir/usr/bin/emb"
    install -Dm644 "$startdir/lib/ember.rb" "$pkgdir/usr/lib/ember/ember.rb"
    install -Dm644 "$startdir/README.md" "$pkgdir/usr/share/doc/ember/README.md"
}
