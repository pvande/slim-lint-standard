# frozen_string_literal: true

require "spec_helper"

describe SlimLint::Linter::StrictLocalsMissing do
  include_context "linter"

  context "when a strict locals magic comment is present" do
    let(:slim) { "/# locals: (name:, greeting: 'Hello')\np = greeting" }

    it { should_not report_lint }
  end

  context "when no strict locals magic comment is present" do
    let(:slim) { "p Hello world" }

    it { should report_lint line: 1 }
  end

  context "when the magic comment has extra whitespace" do
    let(:slim) { "/#  locals:  (name:)\np = name" }

    it { should_not report_lint }
  end

  context "when the magic comment uses empty parentheses" do
    let(:slim) { "/# locals: ()\np Hello" }

    it { should_not report_lint }
  end

  context "when there is a comment but not a locals comment" do
    let(:slim) { "/ just a comment\np Hello" }

    it { should report_lint line: 1 }
  end
end
