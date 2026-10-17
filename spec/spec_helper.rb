# frozen_string_literal: true

# The app skips its boot-time content validation under RACK_ENV=test so that
# the suite can construct deliberately broken content and assert on it. Set
# before the app is required, because the check runs in `configure`.
ENV["RACK_ENV"] = "test"

require "json"
require "rack/test"
require "rspec"

require_relative "../app"

module AppHelper
  def app = ShoutsidFyi::App
end

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include AppHelper

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    # A stub for a method that does not exist is a typo, not a fixture.
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # A suite that ran nothing is not a pass. RSpec exits 0 printing "0 examples,
  # 0 failures", which is also what an empty working tree produces — and since
  # the dev image carries no source (see bin/site), an unmounted run is exactly
  # an empty working tree. Without this flag that run reports success while
  # having tested nothing, which is the failure mode worth a whole line to make
  # impossible. bin/site checks the mount too, a step earlier and by name.
  config.fail_if_no_examples = true
end
