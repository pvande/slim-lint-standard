# frozen_string_literal: true

require "spec_helper"

describe SlimLint::Linter::Zwsp do
  include_context "linter"

  context "when the template contains no zero-width spaces" do
    let(:slim) { "p Hello world" }

    it { should_not report_lint }
  end

  context "when a line contains a zero-width space" do
    let(:slim) { "p Hello\u200bworld" }

    it { should report_lint line: 1 }
  end

  context "when the zero-width space is at a known column" do
    # "p Hello" is 7 characters, so the ZWSP is at column 7 (0-indexed)
    let(:slim) { "p Hello\u200bworld" }

    it { should report_lint line: 1, columns: 7..8 }
  end

  context "when the zero-width space is at the start of the line" do
    let(:slim) { "\u200bp Hello" }

    it { should report_lint line: 1, columns: 0..1 }
  end

  context "when a zero-width space appears on a later line" do
    let(:slim) { "p Hello\ndiv \u200b world" }

    it { should_not report_lint line: 1 }
    it { should report_lint line: 2 }
  end
end
