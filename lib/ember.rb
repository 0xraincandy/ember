# frozen_string_literal: true

require 'io/console'
require 'fileutils'
require 'json'

module Ember
    HOME_DIR = ENV['HOME']
    TMPDIR = "#{HOME_DIR}/.ember/tmp"

    # ----------------- UI -----------------
    # Simple Y/N prompt
    def self.prompt_yn(msg, default: true)
        default_char = default ? 'Y' : 'N'
        other_char   = default ? 'n' : 'y'
        loop do
            print "#{msg} [#{default_char}/#{other_char}] "
            STDOUT.flush
            ans = STDIN.gets.chomp
            if ans.empty?
                return default
            elsif ans =~ /^[Yy]$/
                    return true
            elsif ans =~ /^[Nn]$/
                    return false
            elsif ans == "\u0003" # Ctrl-C
                puts "\n==> Aborted by user."
                exit 130
            else
                puts "Please enter Y or N."
            end
        end
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
    def self.update
        update_system
        update_aur
    end

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

    def self.install(pkg)
        aur_ver = aur_version(pkg)
        if installed_version(pkg) == aur_ver
            puts "[ember] #{pkg} is already up to date. Skipping."
            return
        end

        if prompt_yn("Read PKGBUILD for #{pkg}?", default: false)
            run("curl -fsL https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=#{pkg} | less")
        end

        return unless prompt_yn("Proceed with installing #{pkg}?", default: true)

        FileUtils.mkdir_p(TMPDIR)
        Dir.chdir(TMPDIR) do
            begin
                puts "[ember] Installing #{pkg} from AUR..."
                run("git clone https://aur.archlinux.org/#{pkg}.git")
                Dir.chdir(pkg) { run("makepkg -si") }
            rescue SystemExit, Interrupt
                puts "[ember] Installation canceled by user."
                FileUtils.rm_rf("#{TMPDIR}/#{pkg}")
                exit 130
            ensure
                FileUtils.rm_rf("#{TMPDIR}/#{pkg}") if Dir.exist?("#{TMPDIR}/#{pkg}")
            end
        end

        if prompt_yn("Remove make dependencies?", default: true)
            puts "[ember] Removing unused make dependencies..."
            run("sudo pacman -Rns --asdeps $(pacman -Qtdq) 2>/dev/null || true")
        end
    end

    def self.remove(pkg)
        puts "Removing #{pkg}..."
        run("sudo pacman -R #{pkg}")
    rescue
        puts "[ember] Failed to remove #{pkg}"
    end

    def self.search(query)
        puts "Searching AUR for '#{query}'..."
        results = JSON.parse(`curl -fsL "https://aur.archlinux.org/rpc/?v=5&type=search&arg=#{query}"`)['results']
        if results.empty?
            puts "No results found."
        else
            results.each do |r|
                puts "#{r['Name']} (#{r['Version']}) - #{r['Description']}"
            end
        end
    end
end
