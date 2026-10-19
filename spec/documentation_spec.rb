# frozen_string_literal: true

# Documentation integrity.
#
# `site_integrity_spec` checks every page the app serves. This checks the
# Markdown that describes it. Two failures are easy to ship and invisible to
# every other test: a relative link to a file that was renamed, and a command
# example the CLI does not actually accept. The rollback runbook carried
# `bin/site up --no-build` — an option `up` has never had — until a review read
# it, so the command check below reads the argument parsing out of `bin/site`
# rather than keeping a second list of flags. `test` and `lint` are the
# exception: they pass their arguments through to RSpec and StandardRB, so only
# their command names are checked.
RSpec.describe "documentation" do
  def root = ShoutsidFyi::Content::ROOT

  def markdown_files
    @markdown_files ||= %w[README.md AGENTS.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md CHANGELOG.md]
      .map { |name| File.join(root, name) } +
      Dir.glob(File.join(root, "docs", "*.md")) +
      Dir.glob(File.join(root, ".github", "**", "*.md"))
  end

  def relative(path)
    path.delete_prefix("#{root}/")
  end

  # Markdown allows a fence to be indented by up to three spaces. CONTRIBUTING
  # indents its diagnostic block to sit inside a numbered list, so a check that
  # only looked at column zero would miss a real example.
  def fence?(line)
    line.match?(/^ {0,3}(?:```|~~~)/)
  end

  # Fenced blocks are examples, not prose: a link inside one is not a claim
  # that the target exists, and a command inside one is exactly the thing we do
  # want to check.
  def prose_lines(path)
    fenced = false
    File.readlines(path).each_with_object([]) do |line, lines|
      if fence?(line)
        fenced = !fenced
        next
      end
      lines << line unless fenced
    end
  end

  def code_blocks(path)
    blocks = []
    current = nil
    File.readlines(path).each do |line|
      if fence?(line)
        if current
          blocks << current.join
          current = nil
        else
          current = []
        end
      elsif current
        current << line
      end
    end
    blocks
  end

  # GitHub's heading slug rules, near enough for the links this repository
  # uses: lowercase, punctuation removed, whitespace to hyphens. Duplicate
  # headings get a numeric suffix, which is also what GitHub does.
  def anchors(path)
    counts = Hash.new(0)
    prose_lines(path).filter_map do |line|
      match = line.match(/^\#{1,6}\s+(.+?)\s*#*\s*$/)
      next unless match

      text = match[1]
        .gsub(/`([^`]*)`/, '\1')
        .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
      slug = text.downcase.gsub(/[^\p{Alnum}\s_-]/, "").strip.gsub(/\s/, "-")
      count = counts[slug]
      counts[slug] += 1
      count.zero? ? slug : "#{slug}-#{count}"
    end
  end

  def cli = @cli ||= File.read(File.join(root, "bin", "site"))

  def dispatch
    @dispatch ||= cli.scan(/^\s{4}([^)]+)\)\s+cmd_(\w+)/)
      .flat_map { |commands, name| commands.split("|").map { |command| [command, "cmd_#{name}"] } }
      .to_h
  end

  def function_body(name)
    cli[/^#{Regexp.escape(name)}\(\) \{.*?^\}/m].to_s
  end

  def case_flags(name)
    body = function_body(name)
    body[/case "\$[a-z0-9_]+" in(.*?)esac/m, 1].to_s.scan(/^\s*(--[a-z-]+)/).flatten.uniq
  end

  def shared_dev_flags
    @shared_dev_flags ||= case_flags("split_dev_flags")
  end

  def allowed_flags(command)
    flags = case_flags(dispatch.fetch(command))
    flags |= shared_dev_flags if %w[check shell].include?(command)
    flags |= %w[--volumes] if command == "down"
    flags |= %w[--dry-run] if command == "cf-setup"
    flags
  end

  def documented_commands
    commands = []
    markdown_files.each do |path|
      code_blocks(path).each do |block|
        block.each_line do |line|
          clean = line.sub(/#.*/, "")
          clean.scan(%r{bin/site\s+(\S+)([^&;\n]*)}) do |command, rest|
            commands << [path, line, command, rest.scan(/--[a-z][a-z-]*/)]
          end
        end
      end
    end
    commands
  end

  it "resolves every relative link and anchor" do
    broken = []

    markdown_files.each do |path|
      prose_lines(path).each_with_index do |line, index|
        line.gsub(/`[^`]*`/, "").scan(/\]\(([^)\s]+)(?:\s+"[^"]*")?\)/) do |(target)|
          next if target.match?(%r{\A(?:https?://|mailto:|ftp://)})
          next if target.start_with?("/")

          file, anchor = target.split("#", 2)
          target_path = file.empty? ? path : File.expand_path(file, File.dirname(path))

          unless target_path.start_with?("#{root}/")
            broken << "#{relative(path)}:#{index + 1} links to #{target}, which does not exist"
            next
          end

          unless File.file?(target_path) || File.directory?(target_path)
            broken << "#{relative(path)}:#{index + 1} links to #{target}, which does not exist"
            next
          end

          next if anchor.nil? || anchor.empty?
          next if File.file?(target_path) && anchors(target_path).include?(anchor)

          broken << "#{relative(path)}:#{index + 1} links to #{target}, but #{relative(target_path)} has no ##{anchor} heading"
        end
      end
    end

    expect(broken).to be_empty, "broken documentation links:\n#{broken.join("\n")}"
  end

  it "documents only commands and flags the CLI accepts" do
    problems = []

    documented_commands.each do |path, line, command, flags|
      unless dispatch.key?(command)
        problems << "#{relative(path)}: unknown command `bin/site #{command}` in #{line.strip}"
        next
      end

      next if %w[test lint].include?(command)

      unknown = flags - allowed_flags(command)
      next if unknown.empty?

      problems << "#{relative(path)}: `bin/site #{command}` does not accept #{unknown.join(", ")}"
    end

    expect(problems).to be_empty, "invalid command examples:\n#{problems.join("\n")}"
  end
end
