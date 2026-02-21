# frozen_string_literal: true

require "spec_helper"

describe SlimLint::Linter::TagAttribute do
  include_context "linter"

  context "when no forbidden attributes are configured" do
    let(:slim) { "a onclick='evil()' href='#'" }

    it { should_not report_lint }
  end

  context "when a forbidden attribute is configured" do
    let(:config) { {"forbidden_attributes" => %w[onclick]} }

    context "and the template does not use that attribute" do
      let(:slim) { "a href='http://example.com' Click here" }

      it { should_not report_lint }
    end

    context "and the template uses the forbidden attribute" do
      let(:slim) { "a onclick='evil()' href='#'" }

      it { should report_lint line: 1 }
    end

    context "and the attribute name differs in case" do
      let(:slim) { "a ONCLICK='evil()' href='#'" }

      it { should report_lint line: 1 }
    end

    context "and there are multiple forbidden attributes" do
      let(:config) { {"forbidden_attributes" => %w[onclick onload]} }

      let(:slim) { <<~SLIM }
        a onclick='evil()' href='#'
        body onload='bad()'
      SLIM

      it { should report_lint line: 1 }
      it { should report_lint line: 2 }
    end
  end
end
