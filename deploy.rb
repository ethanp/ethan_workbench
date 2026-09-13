#!/usr/bin/env ruby
# Usage (from any Flutter app directory):
#   ruby /path/to/ethan_workbench/deploy.rb <macos|ios> [--force|-f]
# Or from a sibling app: ruby ../ethan_workbench/deploy.rb ios


require 'digest'
require 'fileutils'
require 'find'
require 'yaml'

require_relative 'xcodebuild_error_capture'

class LocalPathDependencyClosure
  def initialize(root_package_path)
    @root_package_path = File.expand_path(root_package_path)
  end

  def resolve
    root_pubspec = read_pubspec(@root_package_path)
    return [] unless root_pubspec

    @root_dependency_overrides = dependency_constraints(
      root_pubspec,
      "dependency_overrides"
    )
    visited_package_roots = { @root_package_path => true }
    local_package_roots = []
    visit_dependencies_declared_by(
      @root_package_path,
      visited_package_roots,
      local_package_roots
    )
    local_package_roots.sort
  end

  private

  def visit_dependencies_declared_by(
    declaring_package_root,
    visited_package_roots,
    local_package_roots
  )
    pubspec = read_pubspec(declaring_package_root)
    return unless pubspec

    local_dependency_roots(pubspec, declaring_package_root).each do |dependency_root|
      next if visited_package_roots[dependency_root]

      visited_package_roots[dependency_root] = true
      local_package_roots << dependency_root
      visit_dependencies_declared_by(
        dependency_root,
        visited_package_roots,
        local_package_roots
      )
    end
  end

  def local_dependency_roots(pubspec, declaring_package_root)
    dependency_constraints(pubspec, "dependencies").filter_map do |dependency_name, declared_constraint|
      overridden = @root_dependency_overrides.key?(dependency_name)
      effective_constraint = overridden ? @root_dependency_overrides[dependency_name] : declared_constraint
      next unless effective_constraint.is_a?(Hash)

      dependency_path = effective_constraint["path"]
      next unless dependency_path.is_a?(String)

      base_root = overridden ? @root_package_path : declaring_package_root
      File.expand_path(dependency_path, base_root)
    end.sort
  end

  def dependency_constraints(pubspec, section_name)
    section = pubspec[section_name]
    section.is_a?(Hash) ? section : {}
  end

  def read_pubspec(package_root)
    pubspec_path = File.join(package_root, "pubspec.yaml")
    return unless File.file?(pubspec_path)

    pubspec = YAML.safe_load(File.read(pubspec_path), aliases: true)
    if pubspec.is_a?(Hash)
      pubspec
    else
      nil
    end
  end
end

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

  def source_hash
    @source_hash ||= Digest::MD5.hexdigest(
      source_files.filter_map { |file_path| File.read(file_path) rescue nil }.join
    )
  end

  private

  def phase(id)
    puts "DEPLOY_PHASE:#{id}"
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
    ([File.expand_path("pubspec.yaml")] + local_dependency_roots.map do |package_root|
      File.join(package_root, "pubspec.yaml")
    end).select { |file_path| File.file?(file_path) }.sort
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

  def source_files
    app_source_files = source_search_paths.flat_map do |source_path|
      files_under(File.expand_path(source_path), package_root: File.expand_path("."))
    end
    dependency_source_files = local_dependency_roots.flat_map do |package_root|
      files_under(package_root, package_root: package_root)
    end
    (app_source_files + dependency_source_files).uniq.sort
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

  def files_under(path, package_root:)
    return [] unless File.exist?(path)
    return [path] unless File.directory?(path)
    Find.find(path).select do |file_path|
      next false unless File.file?(file_path)
      relative_path = file_path.delete_prefix("#{package_root}#{File::SEPARATOR}")
      next false if File.basename(relative_path) == ".DS_Store"
      next false if VOLATILE_PATH_SEGMENTS.any? { |segment| relative_path.split(File::SEPARATOR).include?(segment) }
      true
    end
  end

  def source_search_paths
    [ "lib", platform_dir, "pubspec.yaml", "pubspec.lock" ]
  end

  def local_dependency_roots
    @local_dependency_roots ||= LocalPathDependencyClosure.new(".").resolve
  end

  def hash_file
    ".deploy_#{platform_name}_hash"
  end

  def shell!(cmd)
    system(cmd) or raise "Command failed: #{cmd}"
  end

  def flutter_build!(cmd)
    XcodebuildErrorCapture.around do |capture, child_env|
      ok = system(child_env, cmd)
      capture.print_hidden_errors unless ok
      raise "Command failed: #{cmd}" unless ok
    end
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
    flutter_build! "flutter build macos --profile"
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
    flutter_build! "flutter build ios --release --no-tree-shake-icons"
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
print_source_hash = ARGV.delete("--print-source-hash")
platform = ARGV.first

abort "Usage: #{$0} <macos|ios> [--force|-f]" unless %w[macos ios].include?(platform)

deployer = platform == "ios" ? IosDeployer.new(force: force) : MacosDeployer.new(force: force)

begin
  if print_source_hash
    puts deployer.source_hash
  else
    deployer.run
  end
rescue => error
  abort error.message
end
