# frozen_string_literal: true

require 'fileutils'
require 'json'

module Ember
    HOME_TMPDIR = File.expand_path("~/.ember/tmp")
    FileUtils.mkdir_p(HOME_TMPDIR)

    # ----------------- UI -----------------
    # Simple Y/N prompt without live updates
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

    # ----------------- Package Info -----------------
    def self.installed_version(pkg)
        out = `pacman -Qi #{pkg} 2>/dev/null`
        out[/^Version\s*:\s*(.+)$/, 1]
    end

    def self.aur_version(pkg)
        url = "https://aur.archlinux.org/rpc/?v=5&type=info&arg=#{pkg}"
        json = JSON.parse(`curl -fsL "#{url}" 2>/dev/null`)
        return nil if json['resultcount'] == 0
        json['results'][0]['Version']
    rescue
        nil
    end

    def self.aur_update_available?(pkg)
        aur = aur_version(pkg)
        inst = installed_version(pkg)
        return false unless aur && inst
        `vercmp #{aur} #{inst} >/dev/null`
        $?.exitstatus != 0
    end

    # ----------------- Actions -----------------
    def self.update_system
        puts "Updating system packages..."
        run("sudo pacman -Syu")
    end

    def self.update_aur
        puts "Checking AUR updates..."
        foreign = `pacman -Qm`.lines.map { |l| l.split.first }
        updates = foreign.select { |pkg| aur_update_available?(pkg) }

        if updates.empty?
            puts "All AUR packages are up to date."
            return
        end

        updates.each do |pkg|
            next unless prompt_yn("Update #{pkg}?", default: true)
            install(pkg)
        end
    end

    # ----------------- Install -----------------
    def self.install(pkg)
        if `pacman -Q #{pkg} 2>/dev/null`.empty?
            # Not installed
            if aur_version(pkg)
                install_aur(pkg)
            else
                puts "[ember] Installing #{pkg} from repositories..."
                run("sudo pacman -S --noconfirm #{pkg}")
            end
        else
            puts "[ember] #{pkg} is already up to date. Skipping."
        end
    end

    def self.install_aur(pkg)
        aur_ver = aur_version(pkg)
        if installed_version(pkg) == aur_ver
            puts "[ember] #{pkg} is already up to date. Skipping."
            return
        end

        if prompt_yn("Read PKGBUILD for #{pkg}?", default: false)
            run("curl -fsL https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=#{pkg} | less")
        end

        return unless prompt_yn("Proceed with installing #{pkg}?", default: true)

        tmp_pkg_dir = File.join(HOME_TMPDIR, pkg)
        FileUtils.rm_rf(tmp_pkg_dir) # cleanup if exists
        FileUtils.mkdir_p(tmp_pkg_dir)

        Dir.chdir(tmp_pkg_dir) do
            puts "[ember] Installing #{pkg} from AUR..."
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

        # Remove unused make dependencies
        if prompt_yn("Remove make dependencies?", default: true)
            puts "Removing unused make dependencies..."
            system("sudo pacman -Rns --asdeps $(pacman -Qtdq) 2>/dev/null || true")
        end
    end

    # ----------------- Remove -----------------
    def self.remove(pkg)
        puts "[ember] Removing #{pkg}..."
        system("sudo pacman -R #{pkg}") || puts("Failed to remove #{pkg}")
    end

    # ----------------- Search -----------------
    def self.search(query)
        puts "[ember] Searching AUR for '#{query}'..."
        results = JSON.parse(`curl -fsL "https://aur.archlinux.org/rpc/?v=5&type=search&arg=#{query}"`)['results']
        if results.empty?
            puts "[ember] No results found."
        else
            results.each { |r| puts "#{r['Name']} (#{r['Version']}) - #{r['Description']}" }
        end
    end
end
