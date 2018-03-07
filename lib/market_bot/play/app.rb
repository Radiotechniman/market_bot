module MarketBot
  module Play
    class App
      attr_reader *ATTRIBUTES
      attr_reader :package
      attr_reader :lang
      attr_reader :result

      def self.parse(html, opts={})
        result = {}

        doc = Nokogiri::HTML(html)
        meta_info = doc.css('.meta-info')
        meta_info.each do |info|
          field_name = info.css('.title').text.strip

          case field_name
          when 'Updated'
            result[:updated] = info.at_css('.content').text.strip
          when 'Installs'
            result[:installs] = info.at_css('.content').text.strip
          when 'Size'
            result[:size] = info.at_css('.content').text.strip
          when 'Current Version'
            result[:current_version] = info.at_css('.content').text.strip
          when 'Requires Android'
            result[:requires_android] = info.at_css('.content').text.strip
          when 'In-app Products'
            result[:in_app_products_price] = info.at_css('.content').text.strip
          when 'Contact Developer', 'Developer'
            dev_links = info.css('.dev-link')

            if website = dev_links.css(':contains("Visit")').first
              href = website.attr('href')
              q_param = URI(href).query.split('&').select{ |p| p =~ /q=/ }.first
              result[:website_url] = q_param.gsub('q=', '')
            end

            if email = dev_links.css(':contains("Email")').first
              email = email.attr('href')
              result[:email] = email.gsub(/^mailto:/,'')
            end

            if privacy = dev_links.css(':contains("Privacy")').first
              href = privacy.attr('href')
              q_param = URI(href).query.split('&').select{ |p| p =~ /q=/ }.first
              result[:privacy_url] = q_param.gsub('q=', '')
            end

            result[:physical_address] = info.at_css('.physical-address').text.strip if info.at_css('.physical-address')
          end
        end

        result[:content_rating] = doc.at_css("div.content[itemprop='contentRating']").text if doc.at_css("div.content[itemprop='contentRating']")

        result[:price] = doc.at_css('meta[itemprop="price"]')[:content] if doc.at_css('meta[itemprop="price"]')

        result[:contains_ads] = !!doc.at_css('.ads-supported-label-msg')

        category_divs = doc.css('.category')

        result[:categories] = category_divs.map { |d| d.text.strip }
        result[:categories_urls] = category_divs.map { |d| File.split(d["href"])[1] }

        result[:category] = result[:categories].first
        result[:category_url] = result[:categories_urls].first

        result[:description] = doc.at_css('div[itemprop="description"]').inner_html.strip
        result[:title] = doc.at_css('div.id-app-title').text

        score = doc.at_css('.score-container')
        unless score.nil?
          node  = score.at_css('.score')
          result[:rating] = node.text.strip
          node = score.at_css('meta[itemprop="ratingCount"]')
          result[:votes] = node[:content].strip.to_i
        end

        node = doc.at_css('div[itemprop="author"]')
        result[:developer] = node.at_css('.primary').text.strip
        result[:developer_id] = node.at_css('.primary').attr('href').split('?id=').last.strip

        result[:more_from_developer] = []
        result[:similar] = []

        node = doc.css('.recommendation')
        node.css('.rec-cluster').each do |recommended|
          assoc_app_type = recommended.at_css('.heading').text.strip.eql?('Similar' ) ? :similar : :more_from_developer
          recommended.css('.card').each do |card|
            assoc_app = {}
            assoc_app[:package] = card['data-docid'].strip

            result[assoc_app_type] << assoc_app
          end
        end

        node = doc.at_css('.cover-image')
        unless node.nil?
          url = MarketBot::Util.fix_content_url(node[:src])
          result[:cover_image_url] = url
        end

        result[:screenshot_urls] = []
        doc.css('.screenshot').each do |node|
          result[:screenshot_urls] << MarketBot::Util.fix_content_url(node[:src])
        end

        result[:full_screenshot_urls] = []
        doc.css('.full-screenshot').each do |node|
          result[:full_screenshot_urls] << MarketBot::Util.fix_content_url(node[:src])
        end

        if (node = doc.at_css('.recent-change'))
          result[:whats_new] = node.inner_html
        end

        result[:reviews] = []
        unless opts[:skip_reviews] # Review parsing is CPU intensive.
          doc.css('.single-review').each do |node|
            review = {}
            review[:author] = node.at_css('.author-name').text.strip if node.at_css('.author-name')
            raw_tag = node.at_css('.current-rating').to_s
            if raw_tag.match(/100%;/i)
              review[:score] = 5
            elsif raw_tag.match(/80%;/i)
              review[:score] = 4
            elsif raw_tag.match(/60%;/i)
              review[:score] = 3
            elsif raw_tag.match(/40%;/i)
              review[:score] = 2
            elsif raw_tag.match(/20%;/i)
              review[:score] = 1
            end
            if node.at_css('.review-title')
              review[:title] = node.at_css('.review-title').text.strip
            end
            if node.at_css('.review-body')
              review[:text] = node.at_css('.review-body').text
                .sub!(review[:title],'')
                .sub!(node.at_css('.review-link').text, '')
                .strip
            end
            if node.at_css('.review-date')
              review[:created_at] = node.at_css('.review-date').text.strip
            end
            if node.at_css('.reviews-permalink')
              review[:review_id] = node.at_css('.reviews-permalink').attr('href').split('&reviewId=').last.strip
            end
            if review
              result[:reviews] << review
            end
          end
        end

        result[:rating_distribution] = { 5 => nil, 4 => nil, 3 => nil, 2 => nil, 1 => nil }

        if (histogram = doc.at_css('div.rating-histogram'))
          cur_index = 5
          %w(five four three two one).each do |slot|
            node = histogram.at_css(".#{slot.to_s}")
            result[:rating_distribution][cur_index] = node.css('.bar-number').text.gsub(/,/,'').to_i
            cur_index -= 1
          end
        else
          result[:rating_distribution] = nil
        end

        result[:html] = html

        result
      end

      def initialize(package, opts={})
        @package = package
        @lang = opts[:lang] || MarketBot::Play::DEFAULT_LANG
        @country = opts[:country] || MarketBot::Play::DEFAULT_COUNTRY
        @request_opts = MarketBot::Util.build_request_opts(opts[:request_opts])
      end

      def store_url
        "https://play.google.com/store/apps/details?id=#{@package}&hl=#{@lang}&gl=#{@country}"
      end

      def update
        req = Typhoeus::Request.new(store_url, @request_opts)
        req.run
        response_handler(req.response)

        self
      end

      private

      def response_handler(response)
        if response.success?
          @result = self.class.parse(response.body)

          ATTRIBUTES.each do |a|
            attr_name = "@#{a}"
            attr_value = @result[a]
            instance_variable_set(attr_name, attr_value)
          end
        else
          codes = "code=#{response.code}, return_code=#{response.return_code}"
          case response.code
          when 404
            raise MarketBot::NotFoundError.new("Unable to find app in store: #{codes}")
          when 403
            raise MarketBot::UnavailableError.new("Unavailable app (country restriction?): #{codes}")
          else
            raise MarketBot::ResponseError.new("Unhandled response: #{codes}")
          end
        end
      end
    end
  end
end
