# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Frai::Agent instructions rendering" do
  after { Frai.reset! }

  let(:project_root) { Dir.mktmpdir }
  after { FileUtils.rm_rf(project_root) }

  let(:agent_class) do
    Class.new(Frai::Agent) do
      def self.name = "ComposeAgent"
    end
  end

  before do
    stub_const("ComposeAgent", agent_class)
    Frai.configure do |c|
      c.project_root = project_root
    end
  end

  def write_directive(name, content)
    dir = File.join(project_root, "agents", "compose", "directives")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{name}.md.erb"), content)
  end

  describe "file mode" do
    before do
      write_directive(:instructions, "You are a helpful agent.")
      agent_class.instructions
    end

    it "renders instructions.md.erb via DirectiveRenderer" do
      text = agent_class.render_prompt("instructions", chat: nil, inputs: {}, locals: {})
      expect(text).to eq("You are a helpful agent.")
    end
  end

  describe "composite mode" do
    before do
      write_directive(:instructions, "Intro\n\n<%= use(\"table\") %>\n\nOutro")
      write_directive(:table, "| col |\n| --- |")
      agent_class.instructions do
        use :instructions do
          use :table
        end
      end
    end

    it "composes nested directives in ERB order" do
      text = agent_class.render_prompt("instructions", chat: nil, inputs: {}, locals: {})
      expect(text).to eq("Intro\n\n| col |\n| --- |\n\nOutro")
    end

    it "rejects scripts in agent directives" do
      write_directive(:bad, '<%= run("noop") %>')
      agent_class.instructions do
        use :bad do
          run :noop
        end
      end

      expect do
        agent_class.render_prompt("bad", chat: nil, inputs: {}, locals: {})
      end.to raise_error(Frai::Error, /Scripts are not supported in agent instructions/)
    end
  end
end
