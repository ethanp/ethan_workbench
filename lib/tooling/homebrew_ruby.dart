/// Homebrew Ruby 3 (`brew install ruby`), not macOS `/usr/bin/ruby` 2.6.
class HomebrewRuby() {
  static const binDirectory = '/opt/homebrew/opt/ruby/bin';
  static const executable = '$binDirectory/ruby';
}
