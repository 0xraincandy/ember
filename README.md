[![License](https://img.shields.io/badge/license-GPLv3-brightgreen)]()
[![Language](https://img.shields.io/badge/language-Ruby-red)]()

# Ember

**Ember** is a minimal AUR helper written in Ruby. It allows you to easily install, update, search, and remove AUR packages with a simple command-line interface.

## Installation

To install **Ember** locally via the PKGBUILD:




```bash
git clone https://github.com/0xraincandy/ember.git
cd ember/
makepkg -si
```

This will build and install the emb command system-wide.


## Usage

Once installed, you can use emb to manage AUR packages.

Update system packages
```bash
emb
```




Install an AUR package
```bash
emb ins <package_name>
```


Remove an installed package
```bash
emb rm <package_name>
```

Search for AUR packages
```bash
emb search <package>
```

Ember uses a temporary folder to clone and build AUR packages:
```bash
~/.ember/tmp/
```
This folder is automatically cleaned after installation

