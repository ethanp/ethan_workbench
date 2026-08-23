# frozen_string_literal: true

require 'tmpdir'

# Flutter's iOS/macOS diagnose path prints xcresult issues and then skips
# xcodebuild stderr whenever any issue was parsed. Early scheme failures
# (missing watchOS runtime, no destination) show up as Uncategorized
# "Failed to build workspace …" while the reason lives only on
# `xcodebuild: error:`. This captures that stderr from the same xcodebuild
# process — no extra build.
class XcodebuildErrorCapture
  def self.around
    Dir.mktmpdir('workbench-xcode-err-') do |directory|
      capture = new(directory)
      capture.install_xcrun_wrapper
      child_env = ENV.to_h.merge('PATH' => "#{directory}:#{ENV.fetch('PATH')}")
      yield capture, child_env
    end
  end

  def self.format_hidden_errors(raw)
    raw.each_line
       .map { |line| line.rstrip }
       .select { |line| line.include?('xcodebuild: error:') }
       .uniq
       .join("\n")
  end

  def initialize(directory, real_xcrun: '/usr/bin/xcrun')
    @directory = directory
    @real_xcrun = real_xcrun
    @stderr_path = File.join(directory, 'xcodebuild.stderr')
  end

  def install_xcrun_wrapper
    wrapper_path = File.join(@directory, 'xcrun')
    File.write(wrapper_path, xcrun_wrapper_script)
    File.chmod(0o755, wrapper_path)
  end

  def print_hidden_errors
    formatted = self.class.format_hidden_errors(captured_stderr)
    return if formatted.empty?

    puts
    puts 'Xcode reported:'
    puts formatted
    $stdout.flush
  end

  private

  def captured_stderr
    File.exist?(@stderr_path) ? File.read(@stderr_path) : ''
  end

  def xcrun_wrapper_script
    err_path = @stderr_path
    <<~BASH
      #!/bin/bash
      runs_xcodebuild=0
      for argument in "$@"; do
        if [ "$argument" = "xcodebuild" ]; then
          runs_xcodebuild=1
          break
        fi
      done
      if [ "$runs_xcodebuild" -eq 0 ]; then
        exec #{@real_xcrun.inspect} "$@"
      fi
      stderr_chunk=$(mktemp)
      #{@real_xcrun.inspect} "$@" 2>"$stderr_chunk"
      status=$?
      cat "$stderr_chunk" >> #{err_path.inspect}
      cat "$stderr_chunk" >&2
      rm -f "$stderr_chunk"
      exit "$status"
    BASH
  end
end

if $PROGRAM_NAME == __FILE__
  puts XcodebuildErrorCapture.format_hidden_errors(ARGF.read)
end
