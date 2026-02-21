# frozen_string_literal: true

require "spec_helper"

describe SlimLint::Linter::QuoteConsistency do
  include_context "linter"

  context "with default configuration (enforces single quotes)" do
    context "when attributes use single quotes" do
      let(:slim) { "a href='http://example.com' Click" }

      it { should_not report_lint }
    end

    context "when attributes use double quotes" do
      let(:slim) { 'a href="http://example.com" Click' }

      it { should report_lint line: 1 }
    end

    context "when there are no quoted attributes" do
      let(:slim) { "a href=url Click" }

      it { should_not report_lint }
    end
  end

  context "when enforced_style is double_quotes" do
    let(:config) { {"enforced_style" => "double_quotes"} }

    context "when attributes use double quotes" do
      let(:slim) { 'a href="http://example.com" Click' }

      it { should_not report_lint }
    end

    context "when attributes use single quotes" do
      let(:slim) { "a href='http://example.com' Click" }

      it { should report_lint line: 1 }
    end
  end

  context "when enforced_style is single_quotes" do
    let(:config) { {"enforced_style" => "single_quotes"} }

    context "when attributes use single quotes" do
      let(:slim) { "a href='http://example.com' Click" }

      it { should_not report_lint }
    end

    context "when attributes use double quotes" do
      let(:slim) { 'a href="http://example.com" Click' }

      it { should report_lint line: 1 }
    end
  end

  context "when the violation is on a specific line" do
    let(:slim) { <<~SLIM }
      p Hello
      a href="http://example.com" Click
    SLIM

    it { should report_lint line: 2 }
    it { should_not report_lint line: 1 }
  end
end
