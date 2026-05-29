module SeedHelper
  module_function

  COLOR = $stdout.tty?               # don't emit ANSI in CI logs
  def green(s) = COLOR ? "\e[32m#{s}\e[0m" : s
  def dim(s)   = COLOR ? "\e[2m#{s}\e[0m" : s

  def banner(text) = puts("\n#{text}\n#{'=' * text.length}")
  def track(name)  = puts("\n#{name}")

  # Wraps one idempotent seed step. Block should be find_or_create_by-style.
  def step(label)
    print "  #{label} ... "
    yield.tap { puts green("✓") }
  rescue => e
    puts "#{COLOR ? "\e[31m" : ''}✗ #{e.class}: #{e.message}#{COLOR ? "\e[0m" : ''}"
    raise
  end

  def summary = puts("\n#{green('✓')} seed complete\n")
end
