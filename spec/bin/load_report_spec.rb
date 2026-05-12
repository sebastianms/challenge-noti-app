# frozen_string_literal: true

require "spec_helper"
require "json"
require "tempfile"

LOAD_REPORT_PATH = File.expand_path("../../bin/load_report", __dir__)
FIXTURES_PATH    = File.expand_path("../fixtures/load_test", __dir__)

RSpec.describe "bin/load_report" do
  def run(fixture:, output: nil)
    input = File.join(FIXTURES_PATH, fixture)
    args  = output ? [input, output] : [input]
    stdout = `ruby #{LOAD_REPORT_PATH} #{args.map { |a| "'#{a}'" }.join(" ")} 2>&1`
    { stdout: stdout, exit_code: $?.exitstatus }
  end

  describe "PASS scenario (k6_pass.json)" do
    subject(:result) { run(fixture: "k6_pass.json") }

    it "exits 0" do
      expect(result[:exit_code]).to eq(0)
    end

    it "prints PASS in output" do
      expect(result[:stdout]).to include("PASS")
    end

    it "includes p95 value" do
      expect(result[:stdout]).to include("142.7")
    end

    it "includes iterations count" do
      expect(result[:stdout]).to include("42000")
    end

    it "includes SLO comparison table" do
      expect(result[:stdout]).to include("p95")
      expect(result[:stdout]).to include("200.0")
    end
  end

  describe "FAIL scenario (k6_fail.json)" do
    subject(:result) { run(fixture: "k6_fail.json") }

    it "exits 1" do
      expect(result[:exit_code]).to eq(1)
    end

    it "prints FAIL in output" do
      expect(result[:stdout]).to include("FAIL")
    end

    it "mentions the exceeded p95 value" do
      expect(result[:stdout]).to include("320.5")
    end
  end

  describe "interrupted scenario (k6_interrupted.json)" do
    subject(:result) { run(fixture: "k6_interrupted.json") }

    it "exits 0 (SLOs met despite interruption)" do
      expect(result[:exit_code]).to eq(0)
    end

    it "mentions INTERRUMPIDO" do
      expect(result[:stdout]).to include("INTERRUMPIDO")
    end
  end

  describe "file output mode" do
    it "writes report to output file" do
      Tempfile.create(["report", ".md"]) do |f|
        run(fixture: "k6_pass.json", output: f.path)
        content = File.read(f.path)
        expect(content).to include("PASS")
        expect(content).to include("# Load Test Report")
      end
    end
  end

  describe "missing input" do
    it "exits 1 and prints usage" do
      stdout = `ruby #{LOAD_REPORT_PATH} /nonexistent.json 2>&1`
      expect($?.exitstatus).to eq(1)
      expect(stdout).to include("Uso:")
    end
  end
end
