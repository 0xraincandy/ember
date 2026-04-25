# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'set'

module Ember

    HOME_TMPDIR = File.expand_path("~/.ember/tmp")
    CACHE_DIR   = File.expand_path("~/.cache/ember")

    FileUtils.mkdir_p(HOME_TMPDIR)
    FileUtils.mkdir_p(CACHE_DIR)

    @building = Set.new

    # -----------------------------
    # UTILS
    # -----------------------------

    def self.prompt_yn(msg, default: true)
        default_char = default ? 'Y' : 'N'
        print "#{msg} [#{default_char}/#{default ? 'n' : 'y'}] "
        ans = STDIN.gets.chomp
        return default if ans.empty?
        ans.downcase.start_with?('y')
    end

    def self.run(cmd)
        system(cmd) || abort("Failed: #{cmd}")
    end

    def self.repo_package?(pkg)
        system("pacman -Si #{pkg} >/dev/null 2>&1")
    end

    def self.installed?(pkg)
        system("pacman -Qi #{pkg} >/dev/null 2>&1")
    end

    def self.foreign_packages
        `pacman -Qm`.lines.map { |l| l.split.first }
    end

    def self.installed_version(pkg)
        out = `pacman -Q #{pkg} 2>/dev/null`
        return nil if out.empty?
        out.split[1]
    end

    # -----------------------------
    # AUR RPC
    # -----------------------------

    def self.fetch_aur_versions(pkgs)
        return {} if pkgs.empty?

        args = pkgs.map { |p| "arg[]=#{p}" }.join("&")
        url = "https://aur.archlinux.org/rpc/?v=5&type=info&#{args}"

        json = JSON.parse(`curl -fsL "#{url}"`)
        json['results'].map { |r| [r['Name'], r['Version']] }.to_h
    rescue
        {}
    end

    def self.aur_exists?(pkg)
        url = "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=#{pkg}"
        json = JSON.parse(`curl -fsL "#{url}"`)
        json["resultcount"].to_i > 0
    rescue
        false
    end

    # -----------------------------
    # SYSTEM UPDATE
    # -----------------------------

    def self.update_system
        puts "[ember] Updating system..."
        run("sudo pacman -Syu")
    end

    def self.find_aur_updates(pkgs)

        installed = {}
        pkgs.each { |p| installed[p] = installed_version(p) }

        aur = {}
        pkgs.each_slice(50) { |slice| aur.merge!(fetch_aur_versions(slice)) }

        updates = []

        pkgs.each do |pkg|

            if pkg.end_with?('-git', '-svn', '-hg')
                updates << pkg
                next
            end

            next unless aur[pkg] && installed[pkg]

            cmp = `vercmp "#{aur[pkg]}" "#{installed[pkg]}"`.strip.to_i
            updates << pkg if cmp == 1
        end

        updates
    end

    def self.update_aur

        puts "[ember] Checking AUR updates..."

        updates = find_aur_updates(foreign_packages)

        if updates.empty?
            puts "All AUR packages up to date."
            return
        end

        puts "\nAUR Updates:"
        updates.each do |p|
            puts "  #{p} #{installed_version(p)} -> new"
        end

        install_aur_batch(updates, force: true)
    end

    # -----------------------------
    # SEARCH
    # -----------------------------

    def self.search(query)
        puts "[ember] Searching AUR for '#{query}'..."

        json = JSON.parse(`curl -fsL "https://aur.archlinux.org/rpc/?v=5&type=search&arg=#{query}"`)

        json['results'].each do |r|
            puts "#{r['Name']} (#{r['Version']}) - #{r['Description']}"
        end
    end

    # -----------------------------
    # DEPENDENCIES
    # -----------------------------

    def self.clean_dep(dep)
        dep.gsub(/['"]/, '').split(':').first.split(/[<>=]/).first.strip
    end

    def self.aur_dependencies(pkg)

        content = `curl -fsL "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=#{pkg}"`

        deps = []
        content.scan(/depends=\((.*?)\)/m) { |m| deps += m[0].split }
        content.scan(/makedepends=\((.*?)\)/m) { |m| deps += m[0].split }

        deps.map { |d| clean_dep(d) }.uniq
    rescue
        []
    end

    # -----------------------------
    # INSTALL
    # -----------------------------

    def self.install(pkg)

        if installed?(pkg)
            puts "[ember] #{pkg} already installed."
            return
        end

        if repo_package?(pkg)
            run("sudo pacman -S #{pkg} --needed")
        else
            install_aur_batch([pkg])
        end
    end

    # -----------------------------
    # BATCH INSTALL
    # -----------------------------

    def self.install_aur_batch(pkgs, force: false)

        return if pkgs.empty?

        puts "\nAUR packages:"
        pkgs.each { |p| puts "  #{p}" }
        puts

        return unless prompt_yn("Install all AUR packages?", default: true)

        pkgs.each do |pkg|
            install_aur(pkg, force: force)
        end

        if prompt_yn("Remove orphaned dependencies?", default: true)
            system("sudo pacman -Rns $(pacman -Qtdq) 2>/dev/null || true")
        end
    end

    # -----------------------------
    # AUR INSTALL
    # -----------------------------

    def self.install_aur(pkg, force: false)

        unless aur_exists?(pkg)
            puts "[ember] ERROR: #{pkg} not found in AUR."
            return
        end

        return if installed?(pkg) && !force
        return if @building.include?(pkg)

        @building << pkg

        puts "[ember] Resolving dependencies for #{pkg}..."

        aur_dependencies(pkg).each do |dep|
            next if installed?(dep)

            if repo_package?(dep)
                run("sudo pacman -S #{dep} --needed")
            else
                install_aur(dep)
            end
        end

        tmp = File.join(HOME_TMPDIR, pkg)
        FileUtils.rm_rf(tmp)
        FileUtils.mkdir_p(tmp)

        Dir.chdir(tmp) do
            puts "[ember] Building #{pkg}..."
            run("git clone https://aur.archlinux.org/#{pkg}.git .")
            run("makepkg -si --noconfirm")
        end

        FileUtils.rm_rf(tmp)
    end

end
