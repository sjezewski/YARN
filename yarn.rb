require 'rubygems'
require 'uri'
require 'mechanize'
require 'nokogiri'
require 'yaml'
require 'pony'

require_relative 'filter'

module RSS
  class Feed
    def initialize(url)
      @host = get_host(url)
      @feed_id = get_id(url)
      @filters = load_filters
      @counts = load_count
      @url = url
    end


    def poll
      m = Mechanize.new
      data = m.get(@url)

      data = data.body

      result = parse(data)

      save_results(result)
      notify(result)

      # Output the current counts:
      File.open(get_counts_path,"w") {|f| f << @counts.to_yaml}
    end


    
    private
   
    def notify(results)
      home = %x`echo $HOME`
      home.gsub!("\n","")
      notify_config = YAML.load(File.open(File.join(home,".yarn")).read)
      # Eventually setup notify method here --- batch/not -- email/growl
      results.each do |filter, data|
        body = ""
        data.each do |item|
          body << "Item: #{item[:title]}"
          body << "Link: #{item[:link]}"
          body << "Data: #{item[:data]}"
        end

        Pony.mail(:to => notify_config[:email], :from => 'yarn@localhost', :subject => "New Match for #{filter}", :body => body)
      end
    end

    def save_results(results)
      puts results
      results_file = File.join(get_project_path, "results.yaml")

      begin
        old_results = File.open(results_file).read
        old_results = YAML.load(old_results)
      rescue Errno::ENOENT
        puts "New results"
        File.open(results_file, "w") {|f| f << results.to_yaml}
        return
      end

      results.keys.each do |filter_name|
        if old_results[filter_name].class == Array
          old_results[filter_name] += results[filter_name]
        else
          old_results[filter_name] = results[filter_name]
        end
      end

      File.open(results_file, "w") {|f| f << old_results.to_yaml}
    end

    def get_project_path 
      home = %x`echo $HOME`
      home.gsub!("\n","")
      File.join(home, "rss", @host)
    end

    def get_counts_path
      file_path = get_project_path
      File.join(file_path, "#{@feed_id}-counts.yaml")
    end

    def get_config_path
      file_path = get_project_path
      File.join(file_path, "#{@feed_id}.yaml")
    end

    def load_count    
      begin
        config_file = File.open(get_counts_path).read
      rescue Errno::ENOENT
        puts "Blank count!"
        return {}
      end
      YAML.load(config_file)
    end

    def get_host(url)
      u = URI.parse(url)
      u.host
    end

    def get_id(url)
      u = URI.parse(url)
      feed_id = u.path
      feed_id.gsub!(/^\//,"")
      feed_id.gsub!("/","-")
      feed_id.gsub!(/\.rss$/, "")
      feed_id
    end

    def load_filters
      file_path = get_config_path
      puts "File path: #{file_path}"
      config_file = File.open(file_path).read
      YAML.load(config_file)
    end


    def parse(data)
      doc = Nokogiri::XML(data)

      result = {}
      items = doc.search("item")

      @filters.each do |filter_config|
        filter = RSS::Filters::Main.new(filter_config)
        puts "="*140
        puts "Main filter = #{filter_config[:name]}"
        results = []

        items.each do |item|
          this_result = filter.apply(item)
          puts "Got result! Filter => #{filter}, Item: #{item.at('title').inner_text}"
          unless this_result.nil?
            link = item.at("link").inner_text
            # Update count
            # -- I'm getting mixed data here, not sure if its going to be useful
            # -- but the idea is not to re-search items I've seen before
            update_count(link)
            results << {:link => link, :data => this_result, :title => item.at("title").inner_text}
          end
        end


        result[filter_config[:name]] = results
      end
      
      
      result
    end

    def update_count(link)
      # For a given url:
      # http://sfbay.craigslist.org/sfc/fuo/2464031888.html
      # Once I've seen that listing, I don't need to worry about older ones
      key = link.gsub(/\/(\d*)\.html$/, "")
      count = $1

      puts "Updating count for category: #{key} -> #{count}"
      return unless count

      if @counts[key].nil?
        @counts[key] = count.to_i
      else
        puts "Increasing? #{(@counts[key] < count.to_i) ? true : false}"
        puts "Old max: #{@counts[key]}, New max: #{count}"
        @counts[key] = count.to_i
      end
    end


  end

end


if __FILE__ == $PROGRAM_NAME
  f = RSS::Feed.new(ARGV[0])
  f.poll  
end


