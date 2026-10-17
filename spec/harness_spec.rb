# frozen_string_literal: true

# The test harness.
#
# These are not tests of the site; they are tests of the arrangement that tests
# the site. That arrangement is: the dev image carries the gems and no source,
# every command that runs code mounts the working tree over /app, and a run
# that did not mount cannot report success.
#
# Each of those is load-bearing, and each of them failed *as a green run*
# before it was fixed — the source in the image meant every edit bought either
# a rebuild or a suite testing a tree that no longer existed, and an empty /app
# made rspec print "0 examples, 0 failures" and exit 0. A rule nothing checks is
# a preference, so they are asserted here rather than left to a comment.
RSpec.describe "the test harness" do
  def repo_file(*parts)
    File.read(File.join(ShoutsidFyi::Content::ROOT, *parts))
  end

  # One Dockerfile stage, from its `FROM` line to the next one. Matching on the
  # next FROM rather than on a trailing marker means adding a stage cannot
  # silently widen or narrow what is checked.
  def docker_stage(name)
    stage = repo_file("Dockerfile")[/^FROM .*\bAS #{name}\b$\n(.*?)(?=^FROM |\z)/m, 1]

    expect(stage).not_to be_nil, "expected a Dockerfile stage named #{name}"
    stage
  end

  def cli
    @cli ||= repo_file("bin", "site")
  end

  def cli_command(name)
    body = cli[/^#{name}\(\) \{.*?^\}/m]

    expect(body).not_to be_nil, "expected #{name} to be defined in bin/site"
    body
  end

  def dev_runner
    @dev_runner ||= cli_command("dev_run")
  end

  # The failure this prevents is the expensive direction of wrong. With the
  # source baked in, any edit invalidated a layer, so every edit bought a
  # rebuild — and the alternative, shipping the image anyway, meant the suite
  # passing against a tree that no longer existed. Removing the source removes
  # the choice. A `COPY . .` put back into this stage brings both failures back
  # at once, silently, with every other test still green.
  it "builds the dev image from the gems and no source" do
    copies = docker_stage("dev").scan(/^COPY (.+)$/).flatten

    expect(copies).to eq(["Gemfile Gemfile.lock ./"])
  end

  # The converse, and the reason the test above can be that strict: the
  # production image is the one that has to contain the site.
  it "keeps the runtime stage shipping the source" do
    expect(docker_stage("runtime")).to include("COPY --chown=app:app . .")
  end

  # One choke point for the mount, so a new subcommand cannot forget it and a
  # change to the policy cannot miss a subcommand. Read-only on purpose: the
  # suite renders content and has no business writing into the working tree.
  it "runs the suite against the mounted working tree, in one place" do
    expect(dev_runner).to include('-v "$DEV_TREE_MOUNT:ro"')
  end

  it "routes check, test and lint through that mount" do
    %w[cmd_check cmd_test cmd_lint].each do |name|
      expect(cli_command(name)).to include("dev_run"), "expected #{name} to use dev_run"
    end
  end

  # With no source in the image, a run whose mount did not take effect has an
  # empty /app — and an empty /app is not a loud failure, it is a green one.
  # So the runner refuses to start unless the tree is demonstrably there.
  it "refuses to run rather than run against an empty tree" do
    guard = cli[/^DEV_MOUNT_GUARD=(.*)$/, 1]

    expect(guard).not_to be_nil, "expected bin/site to define DEV_MOUNT_GUARD"
    expect(guard).to include("/app/app.rb")
    expect(dev_runner).to include("$DEV_MOUNT_GUARD")
  end

  # The other half of the same guard, and worth its own test because it holds
  # even when the mount is fine and the *pattern* is wrong — so a mistyped path
  # cannot report a green run that proved nothing. Asserted by running rspec
  # rather than by grepping spec_helper, because the assertion is about what
  # rspec does, not about what a file says.
  it "does not report success when the run collected no examples" do
    output = IO.popen(
      ["bundle", "exec", "rspec", "--pattern", "spec/no-such-directory/**/*_spec.rb"],
      err: [:child, :out],
      &:read
    )

    expect($?.exitstatus).not_to eq(0),
      "a run with no examples must not exit 0; it printed:\n#{output}"
  end

  # `verify` can only see this site and the suite has no network on purpose, so
  # a URL pointing at somebody else's service was the one class of claim nothing
  # checked — and one had already rotted to a 404 on a card whose status is
  # `live`. A subcommand that is not reachable, or not documented, is a
  # preference rather than a check, so all three parts are asserted: it probes
  # over the network, it is dispatched, and `help` names it.
  it "exposes the external link check as a documented subcommand" do
    expect(cli_command("cmd_links")).to include("curl")
    expect(cli_command("cmd_help")).to include("links")
    expect(cli).to match(/^\s+links\) cmd_links/)
  end

  # The version used to have three homes, and one of them was a lie: app.rb
  # hardcoded 0.1.0, `bin/site version` read APP_VERSION out of .env, and
  # .env.example said the value was "baked into the image at build time" and
  # reported by /healthz. Nothing read the file's copy, so bumping it changed
  # the number the CLI printed and nothing the site said. One default, named in
  # three places, asserted to be one string.
  it "keeps one version, agreed by the app, the CLI and .env.example" do
    app_default = repo_file("app.rb")[/VERSION = ENV\.fetch\("APP_VERSION", "([^"]+)"\)/, 1]

    expect(app_default).not_to be_nil, "expected app.rb to read APP_VERSION rather than carry a literal"
    expect(cli_command("cmd_version")[/version="([^"]+)"/, 1]).to eq(app_default)
    expect(repo_file(".env.example")[/^APP_VERSION=(.+)$/, 1]).to eq(app_default)
  end

  # The Dockerfile sets LANG=C.UTF-8 and the app depends on it: lib/content.rb
  # matches UTF-8 content with a regex, and under Ruby's US-ASCII default every
  # em dash in config/experience.yml raises "invalid byte sequence in US-ASCII".
  # Run the same suite on a host with no locale and 35 examples fail, none of
  # them saying why. bin/site sets the locale for the host path; this is the
  # canary that names the cause if that ever stops happening.
  it "reads content as UTF-8, which is what the container guarantees" do
    expect(Encoding.default_external).to eq(Encoding::UTF_8),
      "the suite is reading content as #{Encoding.default_external}; the container " \
      "sets LANG=C.UTF-8 and bin/site sets it for the host"
  end
end
