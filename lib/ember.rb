# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'thread'

module Ember

    HOME_TMPDIR = File.expand_path("~/.ember/tmp")
    CACHE_DIR   = File.expand_path("~/.cache/ember")
    CACHE_FILE  = File.join(CACHE_DIR, "aur_versions.json")

    FileUtils.mkdir_p(HOME_TMPDIR)
    FileUtils.mkdir_p(CACHE_DIR)

    THREADS = 8

    def self.prompt_yn(msg, default: true)
        default_char = default ? 'Y' : 'N'
        print "#{msg} [#{default_char}/#{default ? 'n' : 'y'}] "
        ans = STDIN.gets.chomp
        return default if ans.empty?
        ans.strip.downcase.start_with?('y')
    end

    def self.run(cmd)
        system(cmd) || abort("Failed: #{cmd}")
    end

    def self.repo_package?(pkg)
        system("pacman -Si #{pkg} >/dev/null 2>&1")
    end

    def self.installed_version(pkg)
        out = `pacman -Qi #{pkg} 2>/dev/null`
        out[/^Version\s*:\s*(.+)$/, 1]
    end

    def self.foreign_packages
        `pacman -Qm`.lines.map { |l| l.split.first }
    end

    def self.load_cache
        return {} unless File.exist?(CACHE_FILE)
        JSON.parse(File.read(CACHE_FILE))
    rescue
        {}
    end

    def self.save_cache(cache)
        File.write(CACHE_FILE, JSON.pretty_generate(cache))
    end

    def self.fetch_aur_versions(pkgs)
        args = pkgs.map { |p| "arg[]=#{p}" }.join("&")
        url = "https://aur.archlinux.org/rpc/?v=5&type=info&#{args}"

        json = JSON.parse(`curl -fsL "#{url}"`)
        json['results'].map { |r| [r['Name'], r['Version']] }.to_h
    rescue
        {}
    end

    def self.find_aur_updates(pkgs)
        installed = {}

        pkgs.each do |pkg|
            installed[pkg] = installed_version(pkg)
        end

        aur_versions = fetch_aur_versions(pkgs)

        updates = []

        pkgs.each do |pkg|
            aur = aur_versions[pkg]
            inst = installed[pkg]
            next unless aur && inst

            cmp = `vercmp #{aur} #{inst}`.strip.to_i
            updates << pkg if cmp == 1
        end

        updates
    end

    def self.update_system
        puts "Updating system packages..."
        run("sudo pacman -Syu")
    end

    def self.update_aur
        puts "Checking AUR updates..."

        foreign = foreign_packages
        updates = find_aur_updates(foreign)

        if updates.empty?
            puts "All AUR packages are up to date."
            return
        end

        puts "\nAUR Updates:"
        updates.each do |pkg|
            puts "  #{pkg} #{installed_version(pkg)} -> newer"
        end
        puts

        updates.each do |pkg|
            next unless prompt_yn("Update #{pkg}?", default: true)
            install(pkg)
        end
    end

    def self.aur_version(pkg)
        fetch_aur_versions([pkg])[pkg]
    end

    def self.aur_dependencies(pkg)
        url = "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=#{pkg}"
        content = `curl -fsL "#{url}"`

        deps = []

        content.scan(/depends=\((.*?)\)/m) do |m|
            deps += m[0].split
        end

        content.scan(/makedepends=\((.*?)\)/m) do |m|
            deps += m[0].split
        end

        deps.map { |d| d.split(/[<>=]/).first }
    rescue
        []
    end

    def self.install(pkg)

        unless `pacman -Q #{pkg} 2>/dev/null`.empty?
            puts "[ember] #{pkg} already installed."
            return
        end

        if repo_package?(pkg)
            puts "[ember] Installing #{pkg} from repos..."
            run("sudo pacman -S #{pkg}")
            return
        end

        install_aur(pkg)
    end

    def self.install_aur(pkg)

        puts "[ember] Resolving dependencies for #{pkg}..."

        deps = aur_dependencies(pkg)

        deps.each do |dep|
            next if system("pacman -Qi #{dep} >/dev/null 2>&1")
            install(dep)
        end

        if prompt_yn("Read PKGBUILD for #{pkg}?", default: false)
            run("curl -fsL https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=#{pkg} | less")
        end

        return unless prompt_yn("Proceed with installing #{pkg}?", default: true)

        tmp_pkg_dir = File.join(HOME_TMPDIR, pkg)

        FileUtils.rm_rf(tmp_pkg_dir)
        FileUtils.mkdir_p(tmp_pkg_dir)

        Dir.chdir(tmp_pkg_dir) do
            puts "[ember] Building #{pkg}..."

            begin
                run("git clone https://aur.archlinux.org/#{pkg}.git .")
                run("makepkg -si")
            rescue SystemExit, Interrupt
                puts "==> Aborted by user! Cleaning up..."
                FileUtils.rm_rf(tmp_pkg_dir)
                exit 130
            end
        end

        FileUtils.rm_rf(tmp_pkg_dir)

        if prompt_yn("Remove orphaned dependencies?", default: true)
            system("sudo pacman -Rns $(pacman -Qtdq) 2>/dev/null || true")
        end
    end

    def self.remove(pkg)
        puts "[ember] Removing #{pkg}..."
        run("sudo pacman -R #{pkg}")
    end

    def self.search(query)

        puts "[ember] Searching AUR for '#{query}'..."

        json = JSON.parse(`curl -fsL "https://aur.archlinux.org/rpc/?v=5&type=search&arg=#{query}"`)

        results = json['results']

        if results.empty?
            puts "[ember] No results found."
            return
        end

        results.each do |r|
            puts "#{r['Name']} (#{r['Version']}) - #{r['Description']}"
        end
    end

end
