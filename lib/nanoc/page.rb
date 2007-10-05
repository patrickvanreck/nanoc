module Nanoc

  class Page

    attr_accessor :stage, :is_filtered, :content_filename

    def initialize(hash, compiler)
      @attributes = hash
      @compiler   = compiler
      @stage      = nil
    end

    def attributes
      @attributes
    end

    def content
      filter!
      @attributes[:content]
    end

    # Proxy/Liquid support

    def to_proxy(params={})
      PageProxy.new(self, :filter => params[:filter])
    end

    def to_liquid
      nanoc_require 'liquid'
      PageDrop.new(self)
    end

    # Helper methods

    def path
      if @attributes[:custom_path].nil?
        @compiler.config[:output_dir] + @attributes[:path] +
          @attributes[:filename] + '.' + @attributes[:extension]
      else
        @compiler.config[:output_dir] + @attributes[:custom_path]
      end
    end

    def file
      File.new(@content_filename)
    end

    def find_layout
      if @attributes[:layout].nil?
        { :type => :eruby, :content => "<%= @page.content %>" }
      else
        # Find all layouts
        filenames = Dir["layouts/#{@attributes[:layout]}.*"]

        # Reject backups
        filenames.reject! { |f| f =~ /~$/ }

        # Make sure there is only one content file
        filenames.ensure_single('layout files', @attributes[:layout])

        # Get the first (and only one)
        filename = filenames[0]

        { :type => Nanoc::Compiler::FILE_TYPES[File.extname(filename)], :content => File.read(filename) }
      end
    end

    # Filtering

    def filter!
      # Get stack and list of other pages
      stack       = @compiler.stack
      other_pages = @compiler.pages

      # Check for recursive call
      if stack.include?(self)
        # Print stack
        unless $quiet
          $stderr.puts 'ERROR: Recursive call to page content.'
          print_stack
        end

        exit
      end

      # Get filters
      if @stage == :pre
        filters = @attributes[:filters_pre] || @attributes[:filters] || []
      elsif @stage == :post
        filters = @attributes[:filters_post] || []
      end

      # Filter if not yet filtered
      unless @is_filtered
        stack.pushing(self) do
          # Read page
          content = @attributes[:content] || File.read(@content_filename)

          begin
            # Get params
            page   = self.to_proxy(:filter => false)
            pages  = other_pages.map { |p| p.to_proxy }
            config = $nanoc_compiler.config

            # Filter page
            @attributes[:content] = content
            filters.each do |filter_name|
              filter = $nanoc_compiler.filter_named(filter_name)
              if filter.nil?
                $stderr.puts 'WARNING: Unknown filter: ' + filter_name unless $quiet
              else
                @attributes[:content] = filter.call(page, pages, config)
                @is_filtered = true
              end
            end
          rescue Exception => exception
            handle_exception(exception, "filter page '#{@content_filename}'")
          end
        end
      end
    end

    def layout!
      # Get list of other pages
      other_pages = @compiler.pages

      # Find layout
      layout = self.find_layout

      # Build params
      if layout[:type] == :liquid
        public_page   = self.to_liquid
        public_pages  = other_pages.map { |p| p.to_liquid }
      else
        public_page   = self.to_proxy
        public_pages  = other_pages.map { |p| p.to_proxy }
      end
      params = { :assigns => { :page => public_page, :pages => public_pages } }
      params[:haml_options] = (@attributes[:haml_options] || {}).symbolize_keys

      # Layout
      case layout[:type]
      when :eruby
        @attributes[:content] = layout[:content].eruby(params)
      when :haml
        @attributes[:content] = layout[:content].haml(params)
      when :markaby
        @attributes[:content] = layout[:content].markaby(params)
      when :liquid
        @attributes[:content] = layout[:content].liquid(params)
      else
        @attributes[:content] = nil
      end
    end

    def print_stack
      # Determine relevant part of stack
      stack_begin = @compiler.stack.index(self)
      stack_end   = @compiler.stack.size
      relevant_stack_part = @compiler.stack.last(stack_end - stack_begin)

      # Print relevant part of stack
      $stderr.puts 'Page filter stack:'
      relevant_stack_part.each_with_index do |page, i|
        $stderr.puts "#{i}  #{page.content_filename}"
      end
    end

  end

end
