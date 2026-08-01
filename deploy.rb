#!/usr/bin/env ruby
# Usage (from any Flutter app directory):
#   ruby /path/to/phone_deploy/deploy.rb <macos|ios> [--force|-f]
# Or from a sibling app: ruby ../phone_deploy/deploy.rb ios


require 'digest'
require 'fileutils'
require 'find'
require 'yaml'

class Deployer
  def initialize(force:)
    @force = force
  end

  def run
    unless @force
      phase 'checking'
      unless source_changed?
        phase 'skipped'
        puts "No changes (use --force to redeploy anyway)"
        return
      end
    end
    phase 'resolving'
    resolve_dependencies
    deploy
  end

  private

  def phase(id)
    puts "PHONE_DEPLOY_PHASE:#{id}"
    $stdout.flush
  end

  # Only `flutter pub get` when dependency manifests change. Keeps build/
  # warm — never `flutter clean` on the happy path.
  def resolve_dependencies
    unless dependency_manifest_changed?
      puts "Dependencies unchanged, skipping flutter pub get"
      return
    end
    shell! "flutter pub get"
    save_dependency_manifest_hash
  end

  def dependency_manifest_changed?
    dependency_manifest_hash != last_dependency_manifest_hash
  end

  def last_dependency_manifest_hash
    File.read(dependency_hash_file).strip if File.exist?(dependency_hash_file)
  end

  def save_dependency_manifest_hash
    File.write(dependency_hash_file, dependency_manifest_hash)
  end

  def dependency_manifest_hash
    @dependency_manifest_hash ||= Digest::MD5.hexdigest(
      dependency_manifest_files.filter_map { |file_path| File.read(file_path) rescue nil }.join
    )
  end

  # pubspec.yaml inputs only (not pubspec.lock — lock is an output of pub get).
  def dependency_manifest_files
    (
      ["pubspec.yaml"] +
      monorepo_package_pubspecs +
      path_dependency_pubspecs
    ).uniq.select { |file_path| File.file?(file_path) }.sort
  end

  def monorepo_package_pubspecs
    return [] unless Dir.exist?("../../packages")
    Dir["../../packages/*/pubspec.yaml"]
  end

  def path_dependency_pubspecs
    spec = YAML.load_file("pubspec.yaml")
    return [] unless spec.is_a?(Hash)
    declared = (spec["dependencies"] || {}).merge(spec["dev_dependencies"] || {})
    declared.filter_map do |_name, constraint|
      next unless constraint.is_a?(Hash) && constraint["path"]
      File.join(constraint["path"], "pubspec.yaml")
    end
  end

  def dependency_hash_file
    ".deploy_pub_deps_hash"
  end

  def source_changed?
    source_hash != last_deployed_hash
  end

  def last_deployed_hash
    File.read(hash_file).strip if File.exist?(hash_file)
  end

  def save_hash
    @source_hash = nil
    File.write(hash_file, source_hash)
  end

  def source_hash
    @source_hash ||= Digest::MD5.hexdigest(source_files.filter_map { |f| File.read(f) rescue nil }.join)
  end

  def source_files
    source_search_paths.flat_map { |path| files_under(path) }.sort
  end

  VOLATILE_PATH_SEGMENTS = %w[
    .dart_tool
    .git
    .idea
    .vscode
    build
    Pods
    node_modules
  ].freeze

  def files_under(path)
    return []     unless File.exist?(path)
    return [path] unless File.directory?(path)
    Find.find(path).select do |file_path|
      next false unless File.file?(file_path)
      next false if File.basename(file_path) == ".DS_Store"
      next false if VOLATILE_PATH_SEGMENTS.any? { |segment| file_path.split(File::SEPARATOR).include?(segment) }
      true
    end
  end

  def source_search_paths
    package_dirs = Dir.exist?("../../packages") ? [ "../../packages" ] : []
    [ "lib", platform_dir, "pubspec.yaml", "pubspec.lock" ] + package_dirs
  end

  def hash_file
    ".deploy_#{platform_name}_hash"
  end

  def shell!(cmd)
    system(cmd) or raise "Command failed: #{cmd}"
  end
end

class MacosDeployer < Deployer
  private

  def deploy
    phase 'building'
    build_macos
    phase 'installing'
    copy_to_applications
    phase 'recording'
    save_hash
    phase 'done'
    puts "✓ Installed to /Applications/#{app_name}.app"
  end

  def build_macos
    shell! "flutter build macos --profile"
  end

  def copy_to_applications
    built_app = Dir["build/macos/Build/Products/Profile/*.app"].first or raise "No .app bundle found"
    FileUtils.rm_rf "/Applications/#{app_name}.app"
    FileUtils.cp_r   built_app, "/Applications/#{app_name}.app"
  end

  def app_name      = File.basename(Dir.pwd)
  def platform_dir  = "macos"
  def platform_name = "macos"
end

class IosDeployer < Deployer
  private

  def deploy
    phase 'building'
    build_ios
    phase 'installing'
    install_to_device
    phase 'recording'
    save_hash
    phase 'done'
    puts "✓ Deployed to iPhone"
  end

  def find_ios_device
    line = `flutter devices`.lines.grep(/ios/i).reject { |l| l.include?("simulator") }.first
    raise "No physical iPhone connected" unless line
    device_id = line.split("•")[1]&.strip or raise "Could not parse device ID"
    puts "Found device: #{device_id}"
    device_id
  end

  def build_ios
    # tree shaking: Release builds may otherwise fail because the health_notes app uses
    # dynamically selected icons (or at least it did at one point).
    shell! "flutter build ios --release --no-tree-shake-icons"
  end

  def install_to_device
    device_id = find_ios_device
    puts "Installing on iPhone..."
    install_with_retry(device_id) || install_after_clean_rebuild(device_id)
  end

  def install_after_clean_rebuild(device_id)
    puts "Install failed, retrying after clean rebuild..."
    clean_and_rebuild_ios
    install_with_retry(device_id) or raise "Install failed after clean rebuild"
  end

  def clean_and_rebuild_ios
    phase 'building'
    shell! "flutter clean"
    shell! "flutter pub get"
    save_dependency_manifest_hash
    build_ios
    phase 'installing'
  end

  def install_with_retry(device_id)
    install(device_id) || retry_install(device_id)
  end

  def retry_install(device_id)
    puts "Retrying in 3s..."
    sleep 3
    install(device_id)
  end

  def install(device_id)
    system "flutter install -d #{device_id}"
  end

  def platform_dir  = "ios/Runner"
  def platform_name = "ios"
end

force    = ARGV.delete("--force") || ARGV.delete("-f")
platform = ARGV.first

abort "Usage: #{$0} <macos|ios> [--force|-f]" unless %w[macos ios].include?(platform)

deployer = platform == "ios" ? IosDeployer.new(force: force) : MacosDeployer.new(force: force)

begin
  deployer.run
rescue => error
  abort error.message
end
