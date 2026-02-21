# frozen_string_literal: true

require "spec_helper"

describe SlimLint::Linter::Tag do
  include_context "linter"

  context "when no forbidden tags are configured" do
    let(:slim) { "script\n  alert('xss')" }

    it { should_not report_lint }
  end

  context "when a forbidden tag is configured" do
    let(:config) { {"forbidden_tags" => %w[script]} }

    context "and the template does not use that tag" do
      let(:slim) { "div\n  p Hello" }

      it { should_not report_lint }
    end

    context "and the template uses the forbidden tag" do
      let(:slim) { "script\n  alert('xss')" }

      it { should report_lint line: 1 }
    end

    context "and the tag name differs in case" do
      let(:slim) { "SCRIPT\n  alert('xss')" }

      it { should report_lint line: 1 }
    end

    context "and there are multiple forbidden tags" do
      let(:config) { {"forbidden_tags" => %w[script iframe]} }

      let(:slim) { "div\n  script .\n  iframe src='x'" }

      it { should report_lint line: 2 }
      it { should report_lint line: 3 }
    end
  end
end
