require 'ruby-debug'
require 'nokogiri'

module RSS
  module Filters

    def Filters.spawn(config)
      type = config[:type].capitalize
      klass = RSS::Filters::Basic
      
      begin
        klass = RSS::Filters.const_get(type)
      rescue Exception
        # 'S cool
      end

      klass.new(config)
    end

    class Basic
      def initialize(config)
        @config = config
      end

      def apply(raw_data)
        filter = @config[:filter]
        result = nil
        data = extract(raw_data)

        # Apply this filter

        r = data.match(filter)
        return if r.nil?

        result = {:raw => data, :captures => r.captures, :filter => filter}

        # Apply sub-filters
        return result if @config[:sub_filters].nil?

        sub_result = nil
        sub_result_data = []

        @config[:sub_filters].each do |sub_filter_config|
          sub_filter = RSS::Filters.spawn(sub_filter_config)
          this_result = sub_filter.apply(raw_data)
          sub_result_data << this_result

          if sub_result.nil?
            sub_result = !this_result.nil?
          else
            sub_result = (!sub_result.nil? || !this_result.nil?)
          end
        end
        
        

        unless sub_result.nil?
          puts "this result=#{result}"
          puts "sub result=#{sub_result}"
          return nil unless sub_result
          result[:sub_data] = sub_result_data
        end

        result
      end

      private

      def extract(data)
        new_data = ""
        puts "Searching: #{@config[:type]}"

        data.search(@config[:type]).each do |data|
          new_data << data
        end
        
        new_data
      end

      def preprocess(data)
        
        
      end

    end

    class Price < Basic

      def apply(raw_data)
        title = raw_data.at("title").inner_text
        title =~ /.*?\$(\d*)$/
        price = $1
        
        return nil unless price
        price = price.to_i

        puts "Price = #{price}"
        puts "Price below threshold: #{(price > @config[:threshold]) ? nil : true}"

        pass = (price <= @config[:threshold])

        return nil unless pass
        {:price => price, :threshold => @config[:threshold]}
      end

    end

    class Main < Basic
      def apply(raw_data)
        sub_result = nil
        sub_result_data = []

        @config[:filters].each do |sub_filter_config|
          sub_filter = RSS::Filters.spawn(sub_filter_config)
          this_result = sub_filter.apply(raw_data)
          sub_result_data << this_result

          if sub_result.nil?
            sub_result = !this_result.nil?
          else
            sub_result = (!sub_result.nil? || !this_result.nil?)
          end
        end

        sub_result_data.compact!
        return nil if sub_result_data.size == 0
        return nil unless sub_result # could be false

        sub_result_data
      end
    end 

  end
end
