require 'pathname'

module Hike
  class Index
    attr_reader :paths, :extensions

    def initialize(root, paths, extensions)
      @root       = root
      @paths      = paths.dup.freeze
      @extensions = extensions.dup.freeze
      @pathnames  = paths.map { |path| Pathname.new(path) }

      @stats    = {}
      @entries  = {}
      @patterns = {}
    end

    def root
      @root.to_s
    end

    def index
      self
    end

    def find(*logical_paths, &block)
      if block_given?
        options = extract_options!(logical_paths)
        base_path = Pathname.new(options[:base_path] || @root)

        logical_paths.each do |logical_path|
          logical_path = Pathname.new(logical_path.sub(/^\//, ''))

          if relative?(logical_path)
            find_in_base_path(logical_path, base_path, &block)
          else
            find_in_paths(logical_path, &block)
          end
        end

        nil
      else
        find(*logical_paths) do |path|
          return path
        end
      end
    end

    protected
      def extract_options!(arguments)
        arguments.last.is_a?(Hash) ? arguments.pop.dup : {}
      end

      def relative?(logical_path)
        logical_path.to_s =~ /^\.\.?\//
      end

      def find_in_paths(logical_path, &block)
        dirname, basename = logical_path.split
        @pathnames.each do |base_path|
          match(base_path.join(dirname), basename, &block)
        end
      end

      def find_in_base_path(logical_path, base_path, &block)
        candidate = base_path.join(logical_path)
        dirname, basename = candidate.split
        match(dirname, basename, &block) if paths_contain?(dirname)
      end

      def match(dirname, basename)
        matches = entries(dirname)

        pattern = pattern_for(basename)
        matches = matches.select { |m| m.to_s =~ pattern }

        sort_matches(matches, basename).each do |path|
          pathname = dirname.join(path)
          stat     = stat(pathname)

          if stat && stat.file?
            yield pathname.to_s
          end
        end
      end

      def stat(pathname)
        if @stats.key?(pathname)
          @stats[pathname]
        else
          begin
            @stats[pathname] = pathname.stat
          rescue Errno::ENOENT
            @stats[pathname] = nil
          end
        end
      end

      def entries(pathname)
        @entries[pathname] ||= pathname.entries.reject { |entry| entry.to_s =~ /^\.\.?$/ }
      rescue Errno::ENOENT
        @entries[pathname] = []
      end

      def paths_contain?(dirname)
        paths.any? { |path| dirname.to_s[0, path.length] == path }
      end

      def pattern_for(basename)
        @patterns[basename] ||= begin
          extension_pattern = extensions.map { |e| Regexp.escape(e) }.join("|")
          /^#{Regexp.escape(basename.to_s)}(?:#{extension_pattern}|)+$/
        end
      end

      def sort_matches(matches, basename)
        matches.sort_by do |match|
          extnames = match.to_s[basename.to_s.length..-1].scan(/.[^.]+/)
          extnames.inject(0) { |sum, ext| sum + extensions.index(ext) + 1 }
        end
      end
  end
end