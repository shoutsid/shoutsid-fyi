# frozen_string_literal: true

require "kramdown"

module ShoutsidFyi
  # Markdown rendering for the blog.
  #
  # One renderer, one set of options: a second call site with its own
  # Kramdown options is how the same post ends up with two different heading
  # anchors depending on which page it was reached from.
  module Markdown
    module_function

    # Kramdown's `parse_block_html` and `parse_span_html` are what let a post
    # contain a figure or a details block without a plugin. Content under
    # `content/` is committed to this repository and reviewed like code, so it
    # is trusted input — the alternative (stripping HTML) would remove the one
    # useful escape hatch for diagrams. Nothing here renders user-submitted
    # text; there is no user-submitted text on the site.
    OPTIONS = {
      input: "GFM",
      hard_wrap: false,
      syntax_highlighter: nil,
      auto_ids: true
    }.freeze

    def render(source)
      Kramdown::Document.new(source.to_s, OPTIONS).to_html
    end
  end
end
