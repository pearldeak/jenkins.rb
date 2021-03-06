require 'spec_helper'

describe Jenkins::Plugin::Proxies do
  Proxies = Jenkins::Plugin::Proxies
  before  do
    Proxies.clear
    @plugin = double(Jenkins::Plugin, :name => 'mock-plugin')
    allow(@plugin).to receive(:linkout) {|*args| @proxies.linkout(*args)}
    @proxies = Jenkins::Plugin::Proxies.new(@plugin)
    allow(Jenkins).to receive(:plugin) {@plugin}
  end

  describe "exporting a native ruby object" do

    before do
      @class = Class.new
      @object = @class.new
    end

    describe "when no wrapper exists for it" do

      describe "and there is a matching proxy class registered" do
        before do
          @proxy_class = Class.new
          @proxy_class.class_eval do
            attr_reader :plugin, :object
            def initialize(plugin, object)
              @plugin, @object = plugin, object
            end
          end
          Jenkins::Plugin::Proxies.register @class, @proxy_class
          @export = @proxies.export(@object)
        end

        it "instantiates the proxy" do
          expect(@export).to be_kind_of(@proxy_class)
        end

        it "passes in the plugin and the wrapped object" do
          expect(@export.plugin).to be(@plugin)
          expect(@export.object).to be(@object)
        end
      end

      describe "and there is not an appropriate proxy class registered for it" do
        it "raises an exception on export" do
          expect {@proxies.export(@object)}.to raise_error
        end
      end
    end

    describe "when a wrapper has already existed" do
      before do
        @proxy = Object.new
        @proxies.linkin @object, @proxy
      end

      it "finds the same proxy on export" do
        expect(@proxies.export(@object)).to be(@proxy)
      end

      it "finds associated Ruby object on import" do
        expect(@proxies.import(@proxy)).to be(@object)
      end
    end

    describe "proxy matching" do
      describe "when there are two related classes" do
        before do
          @A = Class.new
          @B = Class.new(@A)
          @A.class_eval do
            attr_reader :native
            def initialize(native = nil)
              @native = native
            end
          end
        end

        describe "and there is a proxy registered for the subclass but not the superclass" do
          before do
            @p = proxy_class
            Proxies.register @B, @p
          end

          it "will create a proxy for the subclass" do
            expect(@proxies.export(@B.new)).to be_kind_of(@p)
          end

          it "will create a native for the external class" do
            internal = @proxies.import(@p.new)
            expect(internal).to be_kind_of(@B)
          end

          it "will fail to create a proxy for the superclass" do
            expect {@proxies.export @A.new}.to raise_error(Jenkins::Plugin::ExportError)
          end
        end

        describe "and there is a proxy registered for the superclass but not the superclass" do
          before do
            @p = proxy_class
            Proxies.register @A, @p
          end
          it "will create a proxy for the superclass" do
            expect(@proxies.export(@A.new)).to be_kind_of(@p)
            expect(@proxies.import(@p.new)).to be_kind_of(@A)
          end

          it "will create a proxy for the subclass" do
            expect(@proxies.export(@B.new)).to be_kind_of(@p)
          end
        end

        describe "and there is proxy registered for both classes" do

          before do
            @pA = proxy_class
            @pB = proxy_class
            Proxies.register @A, @pA
            Proxies.register @B, @pB
          end
          it "will create a proxy for the subclass with its registered proxy class" do
            expect(@proxies.export(@A.new)).to be_kind_of(@pA)
            expect(@proxies.import(@pA.new)).to be_kind_of(@A)
          end

          it "will create a proxy for the superclass with its registered proxy class" do
            expect(@proxies.export(@B.new)).to be_kind_of(@pB)
            expect(@proxies.import(@pB.new)).to be_kind_of(@B)
          end
        end
      end
    end

  end

  describe "importing an unmapped native java object" do
    before do
      @umappable = java.lang.Object.new
      @import = @proxies.import(@umappable)
    end
    it "maps it to an opaque native java object structure" do
      expect(@import.native).to be @umappable
    end
    it "reuses the same opaque proxy on subsequent imports" do
      expect(@proxies.import(@umappable)).to be @import
    end
    it "exports the object as the original java value" do
      expect(@proxies.export(@import)).to be @umappable
    end
  end

  describe "exporting an alreay external java object" do
    before do
      @java_object = java.lang.Object.new
      @export = @proxies.export(@java_object)
    end

    it "just passes the java object through" do
      expect(@export).to be @java_object
    end
    it "is idempotent" do
      expect(@proxies.export(@export)).to be @export
    end
  end

  describe 'importing a java proxy object which was manually created' do
    before do
      @impl = Object.new
      @proxy = proxy_class.new(@plugin, @impl)
    end

    it 'returns the proxied ruby object' do
      expect(@proxies.import(@proxy)).to be @impl
    end

    it 'exports the proxy in lieu of the ruby implementation' do
      expect(@proxies.export(@impl)).to be @proxy
    end
  end

  private

  def proxy_class
    cls = Class.new(java.lang.Object)
    cls.class_eval do
      include Jenkins::Plugin::Proxy
      attr_reader :plugin, :object

      def initialize(plugin = nil, object = nil)
        super(plugin || Jenkins.plugin, object)
      end

    end
    return cls
  end
end
