# encoding: UTF-8

def kramdown_convert_mermaid_to_div(node, meta_data)
  if node.type == :codeblock && node.options[:lang] == 'mermaid'
    node.type = :raw
    node.value = %(<div class="mermaid">#{node.value}</div>\n)
    meta_data[:mermaid] = true
  else
    node.children.each {|child| kramdown_convert_mermaid_to_div(child, meta_data) }
  end
end

def kramdown_reveal_solution(node)
  children = node.children.dup
  index = children.length-1
  while index >= 1
    unless previous_child = children[index-1]
      index -= 1
      next
    end
    if children[index].type == :comment && (previous_child.attr['class'] || '') =~ /\bsolution\b/
      children[index-1] = Kramdown::Element.new(:codeblock, children[index].value, previous_child.attr)
      children.delete_at(index)
      index -= 2
    else
      kramdown_reveal_solution(children[index])
      index -= 1
    end
  end
  node.children = children
end

def kramdown_erase_comments(node)
  node.value = "" if node.type == :comment
  node.children.each {|child| kramdown_erase_comments(child) }
end

def kramdown_set_no_toc_for_numbering_none(children, none_level = 10)
  children.each do |node|
    if node.type == :header
      if (node.attr['class'] || '') =~ /\b(toc-title|title)\b/
        # Handle standalone cases
        node.attr['class'] += ' no_toc'
      elsif (node.attr['class'] || '') =~ /\b(numbering-none)\b/
        # Found the numbering-none, store the level and tag the node itself with no_toc
        node.attr['class'] += ' no_toc'
        none_level = node.options[:level]
      elsif node.options[:level] > none_level
        # This header is below so tag it with no_toc
        node.attr['class'] = "#{node.attr['class']} no_toc"
      elsif node.options[:level] <= none_level
        # Found a header at the same level or above, so reset the level
        none_level = 10
      end
    end

    kramdown_set_no_toc_for_numbering_none(node.children, none_level)
  end
end

def escape_js_string(string)
  string.gsub("\\", "\\\\\\").gsub('"', '\"')
end

def find_file_for_template(filename)
  template_paths = [
    filename,
    File.join(File.join(File.dirname(__FILE__), "templates"), filename),
    File.join(File.join(File.dirname(__FILE__), "kramdown"), filename),
  ]
  template_paths.map {|pathname| File.expand_path(pathname) }.find {|pathname| File.exists?(pathname) }
end

def find_standard_template(prefix, format, variants)
  variants.sort!

  prefixes = ["#{prefix}2[0-9][0-9][0-9]", "#{prefix}2[0-9][0-9][0-9]-[0-9]"]
  globfilenames = []
  globfilenames.concat(prefixes.product(variants.size.times.map {|size| variants[0..size].join('_') }).map {|prefix, variant| "#{prefix}_#{variant}.#{format}" }) unless variants.empty?
  globfilenames.concat(prefixes.map {|prefix| "#{prefix}.#{format}" })

  template_dirs = ['.', File.join(File.dirname(__FILE__), "templates"), File.join(File.dirname(__FILE__), "kramdown")]
  candidates = Dir.glob(template_dirs.product(globfilenames).map {|dir, globfilename| File.expand_path(File.join(dir, globfilename)) })
  candidates.sort_by! {|pathname| File.basename(pathname) }
  candidates.reverse!

  year_threshold = (Time.now.year+1).to_s
  candidates.bsearch {|pathname| File.basename(pathname)[/2\d\d\d.*?(?:[^._])/] < year_threshold }
end

def find_template(format)
  ENV['template'] ? find_file_for_template(ENV['template']) : find_standard_template((ENV['template_prefix'] || 'corporate'), format, (ENV['template_variants'] || '').split(','))
end

namespace :document do
  namespace :convert do
    desc "Convert a document from HTML to PDF using puppeteer and puppeteer-report (requires nodejs), pass the input file path in `input`, optionnaly `output` as the output filename."
    task :puppeteer do
      fail("You must pass an `input`!") unless ENV['input']
      input_path = File.expand_path(ENV['input'])
      output_path = File.expand_path(ENV['output'] || "#{File.basename(input_path, '.*')}.pdf")
      
      page_width, page_height = ENV['page_width'], ENV['page_height']
      report_options_in_js = if page_width && page_height
        %Q{width: "#{escape_js_string(page_width)}", height: "#{escape_js_string(page_height)}", }
      else
        page_size = ENV['page_size'] || 'A4'
        is_landscape = !!((ENV['page_orientation'] || '') =~ /landscape/i)
        %Q{format: "#{escape_js_string(page_size)}", landscape: #{is_landscape}, }
      end
      
      puppeteer_runner = <<-EOC
        // node >= 12 needed
        // NODE_PATH has to be set like: `export NODE_PATH=$(npm root -g)`
        'use strict';
        const puppeteer = require('puppeteer');
        const report = require("puppeteer-report");
        const createPdf = async() => {
          const browser = await puppeteer.launch({
            args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"],
          });
          try {
            await report.pdf(browser, "#{escape_js_string(input_path)}", {
              path: "#{escape_js_string(output_path)}",
              printBackground: true,
              destinationsHandler: function(destinations) {
                if (typeof window.handleDestinations === "function") {
                  window.handleDestinations(destinations);
                }
              },
              #{report_options_in_js}
            });
          } finally {
            await browser.close();
          }
        }
        createPdf();
      EOC

      require 'tempfile'
      file = Tempfile.new(['puppeteer-runner', '.js'])
      begin
        file.write(puppeteer_runner)
        file.close
        
        output = `node #{file.path} 2>&1`
        puts output unless output.empty?
        puts "Run this and retry (it may work): `export NODE_PATH=$(npm root -g)`" unless $?.success?
      ensure
        file.unlink
      end

      #require 'open3'
      #output, _ = Open3.capture2("node -", :stdin_data => puppeteer_runner, :binmode => true)
      #puts output
    end
  end

  namespace :generate do
    desc <<~EOD
    Generate a document using kramdown, pass source files path in `sources` with comma separated values, pass the output format in `format` (defaults to html), you may pass your own template in `template`, optionnaly `output` as the output filename.
    Templates:
      You can pass an explicit path for the `template` argument.
      If you pass a simple filename, the lookup scheme is to check for the template in the current directory,
      then in any of the subdirectories `templates` or `kramdown` found in the directory hosting this rake task.
    Examples:
      rake document:generate:kramdown sources=RubyTextbook.yml,01-Introduction.md,02-Basics.md
      rake document:generate:kramdown sources=PythonCookBook.md template=book.html
    MetaData:
      Meta data are gathered from several sources listed below by reverse order of precedence:
      - YAML file found in the same directory as the template with the same basename but ending with .yml
      - YAML prefix of the source files (processed one after another)
      - Extra command line arguments
    EOD
    task :kramdown do
      fail("You must pass some `sources`!") unless ENV['sources']
      sources_path = ENV['sources'].split(',').inject([]) {|memo, path| memo.concat(Dir.glob(path).sort) }
      format = ENV['format'] || 'html'
      output_filename = ENV['output'] || "#{File.basename(sources_path.first, '.*')}.#{format}"
      reveal_solution = ENV['reveal_solution']

      require 'kramdown'
      require 'yaml'
      begin; require 'kramdown-parser-gfm'; rescue LoadError; end
      begin; require 'kramdown_graphviz'; rescue LoadError; end

      template_filename = find_template(format)

      # Setup base meta_data that may be updated by the following stages
      meta_data = {template: template_filename, input: 'GFM', hard_wrap: false, transliterated_header_ids: true, auto_id_prefix: '_chap_', auto_id_stripping: true}
      # Get user meta_data targeting the chosen template
      template_metadata_filename = "#{File.dirname(template_filename)}/#{File.basename(template_filename,'.*')}.yml"
      meta_data.update(YAML.load(File.read(template_metadata_filename))) if File.exists?(template_metadata_filename)
      # Read all the sources, strip the optional YAML metablock and use it to update meta_data, store the remaining source
      source_content = sources_path.inject('') do |memo, source|
        content = File.read(source)
        if content =~ /\A---/
          preamble = content.slice!(/\A---.*?^---/m)
          meta_data.update(YAML.load(preamble)) rescue STDERR.puts "Ignoring invalid meta data for #{source}"
        end
        memo << content
      end
      # Add all command line arguments to meta_data, so that the template may use them
      meta_data.update(:reveal_solution => reveal_solution)
      # Post-process some options
      meta_data[:logo_filename] = find_file_for_template(meta_data[:logo_filename]) if meta_data[:logo_filename]
      
      File.open(output_filename, 'w') do |file|
        document = Kramdown::Document.new(source_content, meta_data)
        kramdown_reveal_solution(document.root) if reveal_solution
        kramdown_convert_mermaid_to_div(document.root, meta_data)
        kramdown_erase_comments(document.root)
        kramdown_set_no_toc_for_numbering_none(document.root.children)
        file.write(document.send("to_#{format}"))
      end
      
      #TODO: We may add a step to minify the result. Maybe using `html-minifier --collapse-whitespace --conservative-collapse --remove-comments --remove-redundant-attributes --remove-empty-attributes --remove-script-type-attributes --use-short-doctype --minify-css true --minify-js true`
      
      # Hack to transfer info to next rake task
      ENV['page_width'] = meta_data['page_width']
      ENV['page_height'] = meta_data['page_height']
      ENV['page_size'] = meta_data['page_size']
      ENV['page_orientation'] = meta_data['page_orientation']
    end

    desc "Generate a document using kramdown targeting HTML (file preserved) and convert it to PDF using puppeteer and puppeteer-report (requires nodejs), see document:generate:kramdown for options."
    task :puppeteer do
      # The intermediate html file can't be generated in temp because referenced assets will break.
      fail("You must pass some `sources`!") unless ENV['sources']
      sources_path = ENV['sources'].split(',').inject([]) {|memo, path| memo.concat(Dir.glob(path).sort) }
      output_filename = ENV['output'] || "#{File.basename(sources_path.first, '.*')}.pdf"
      intermediate_filename = "#{File.dirname(output_filename)}/#{File.basename(output_filename,'.*')}.html"
      
      ENV['output'] = intermediate_filename
      ENV['format'] = 'html'
      ENV['template_variants'] = 'print' unless ENV['template_variants']
      Rake::Task["document:generate:kramdown"].invoke
      
      ENV['input'] = intermediate_filename
      ENV['output'] = output_filename
      Rake::Task["document:convert:puppeteer"].invoke
    end

    desc "Generate a document using pandoc, pass source files path in `sources` with comma separated values, pass the output format in `format`, you may pass your own template in `template`, optionnaly `output` as the output filename."
    task :pandoc do
      fail("You must pass some `sources`!") unless ENV['sources']
      sources_path = ENV['sources'].split(',').inject([]) {|memo, path| memo.concat(Dir.glob(path).sort) }
      format = ENV['format'] || 'html'
      output_filename = ENV['output'] || "#{File.basename(sources_path.first, '.*')}.#{format}"
      
      format = 'latex' if format == 'pdf'
      template_option = "--template=#{ENV['template']}" if ENV['template']
      
      pandoc_options = ENV['pandoc_options']
      `pandoc -s -o #{output_filename} -t #{format} #{template_option} #{pandoc_options} #{sources_path.join(' ')}`
    end
  end

  namespace :template do
    desc "Show the help (if supplied) for a specific template, pass the template in `template`."
    task :help do
      format = ENV['format'] || '*'
      if template_filename = find_template(format)
        template_help_filename = "#{File.dirname(template_filename)}/#{File.basename(template_filename,'.*')}.help"
        if File.exists?(template_help_filename)
          puts File.read(template_help_filename)
        else
          puts "No template help (put one at #{template_help_filename})"
        end
      else
        puts "No template found!"
      end
    end

    desc "Show the absolute pathname of the candidate for a specific template, pass the template in `template`."
    task :candidate do
      format = ENV['format'] || '*'
      if template_filename = find_template(format)
        puts template_filename
      else
        puts "No template found!"
      end
    end
  end
end
