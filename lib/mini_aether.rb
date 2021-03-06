require 'java'
require 'logger'
require 'mini_aether/spec'

module MiniAether
  MAVEN_CENTRAL_REPO = 'http://repo1.maven.org/maven2'.freeze

  M2_SETTINGS = File.join(ENV['HOME'], '.m2', 'settings.xml').freeze

  class LoggerConfig
    attr_reader :level

    def initialize
      @level = 'INFO'
    end

    def level=(level)
      @level = case level
               when Symbol, String
                 level.to_s.upcase
               when Logger::FATAL, Logger::ERROR
                 'ERROR'
               when Logger::WARN
                 'WARN'
               when Logger::INFO
                 'INFO'
               when Logger::DEBUG
                 'DEBUG'
               else
                 'INFO'
               end
    end

    def info?
      case @level
      when 'INFO', 'DEBUG'
        true
      else
        false
      end
    end
  end

  class << self
    def logger
      @logger ||= LoggerConfig.new
    end

    # Create a new ScriptingContainer (Java object interface to a
    # JRuby runtime) in SINGLETHREAD mode, and yield it to the block.
    # Ensure the runtime is terminated after the block returns.
    def with_ruby_container
      scope = Java::OrgJrubyEmbed::LocalContextScope::SINGLETHREAD
      c = Java::OrgJrubyEmbed::ScriptingContainer.new(scope)
      begin
        # short-lived container of mostly java calls may be a bit
        # faster without spending time to JIT
        c.setCompileMode Java::OrgJruby::RubyInstanceConfig::CompileMode::OFF
        yield c
      ensure
        c.terminate
      end
    end

    # Resolve +dependencies+, downloading from +sources+.
    #
    # Uses a separate JRuby runtime to avoid polluting the classpath
    # with Aether and SLF4J classes.
    #
    # @param [Array<Hash>] dependencies
    #
    # @option dependency [String] :group_id the groupId of the artifact
    # @option dependency [String] :artifact_id the artifactId of the artifact
    # @option dependency [String] :version the version (or range of versions) of the artifact
    # @option dependency [String] :extension default to 'jar'
    #
    # @param [Array<String>] repos urls to maven2 repositories
    #
    # @return [Array<String>] an array of paths to artifact files
    # (likely jar files) satisfying the dependencies
    def resolve(dependencies, sources)
      with_ruby_container do |c|
        c.put 'path', File.dirname(__FILE__).to_java
        c.put 'deps', Marshal.dump(dependencies).to_java
        c.put 'repos', Marshal.dump(sources).to_java
        files = c.runScriptlet <<-EOF
          $LOAD_PATH.push path
          require 'mini_aether/resolver'
          MiniAether::Resolver.new.resolve_foreign(deps, repos)
        EOF
        files.map { |f| f.to_s }
      end
    end

    def setup(&block)
      MiniAether::Spec.new(&block).require
    end
  end
end
