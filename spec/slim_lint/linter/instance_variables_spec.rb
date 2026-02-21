# frozen_string_literal: true

require "spec_helper"

describe SlimLint::Linter::InstanceVariables do
  include_context "linter"

  context "when the template has no instance variables" do
    let(:slim) { "= user.name" }

    it { should_not report_lint }
  end

  context "when the template uses an instance variable" do
    let(:slim) { "= @user.name" }

    it { should report_lint line: 1 }
  end

  context "when the template uses multiple instance variables" do
    let(:slim) { <<~SLIM }
      = @user.name
      = @post.title
    SLIM

    it { should report_lint line: 1 }
    it { should report_lint line: 2 }
  end

  context "when an instance variable appears in a control statement" do
    let(:slim) { "- if @user.admin?" }

    it { should report_lint line: 1 }
  end

  context "when instance variables appear inside a tag attribute" do
    let(:slim) { "a href=@user.profile_path Click" }

    it { should report_lint line: 1 }
  end

  context "when the template only contains static text" do
    let(:slim) { "p Hello world" }

    it { should_not report_lint }
  end
end
