require 'json'
require 'net/http'
require 'nokogiri'
require 'rss'
require 'time'
require 'uri'

module MangaNovelFeeds
  class Redirect < Exception
    attr_reader :target

    def initialize(target)
      @target = target
    end
  end

  module Providers
    class << self
      def providers
        @providers ||= {}
      end

      def find(provider_id)
        providers.fetch(provider_id)
      end
    end

    class Base
      class << self
        private

        def provider_id(provider_id)
          Providers::providers[provider_id] = self
        end
      end

      private

      def u(s)
        URI.encode_www_form_component(s)
      end

      def http_get(uri)
        header = {
          'User-Agent' => 'manga-novels-feed (+https://github.com/hanazuki/manga-novels-feed)',
        }
        Net::HTTP.get(uri, header)
      end
    end

    class Storia < Base
      provider_id 'storia.takeshobo.co.jp'

      def rss(id)
        index_uri = URI("https://storia.takeshobo.co.jp/manga/#{u id}/")
        index = Nokogiri::HTML(http_get(index_uri))

        RSS::Maker.make('2.0') do |maker|
          maker.channel.title = index.title
          maker.channel.link = index_uri
          maker.channel.description = index.xpath('//h2[text() = "ストーリー"]/following-sibling::p').text

          maker.items.do_sort = true

          index.css('.episode').each do |ep|
            next unless a = ep.ancestors('a').first
            next unless date = extract_date(ep.xpath('./following-sibling::li[text() = "公開日"]/following-sibling::li[1]').text)

            maker.items.new_item do |item|
              uri = item.link = index_uri + a.attr('href')
              item.title = ep.text.strip
              item.date = date
              item.guid.content = uri
              item.guid.isPermaLink = true
            end
          end
        end
      end

      private

      def extract_date(s)
        if /(?<year>\d+)年\s*(?<month>\d+)月\s*(?<day>\d+)日/ =~ s
          Time.new(year.to_i, month.to_i, day.to_i, 0, 0, 0, '+09:00')
        end
      end
    end

    class GanganOnline < Base
      provider_id 'ganganonline.com'

      def rss(id)
        index_uri = URI("https://www.ganganonline.com/title/#{u id}")
        index = Nokogiri::HTML(http_get(index_uri))

        data = JSON.parse(index.at_css('#__NEXT_DATA__').text)
        props = data.dig('props', 'pageProps', 'data', 'default')

        RSS::Maker.make('2.0') do |maker|
          maker.channel.title = index.title
          maker.channel.link = index_uri
          maker.channel.description = props['description']

          maker.items.do_sort = true

          props['chapters'].each do |entry|
            next unless /(?<year>\d+)\.(?<month>\d+)\.(?<mday>\d+)/ =~ entry['publishingPeriod']
            date = Time.new(year.to_i, month.to_i, mday.to_i)
            title = entry.values_at('mainText', 'subText').compact.join(?\s)
            uri = "https://www.ganganonline.com/title/#{u id}/chapter/#{u entry['id']}"

            maker.items.new_item do |item|
              item.link = uri
              item.title = title
              item.date = date
              item.guid.content = uri
              item.guid.isPermaLink = true
            end
          end
        end
      end
    end

    class UraSunday < Base
      provider_id 'urasunday.com'

      def rss(id)
        index_uri = URI("https://urasunday.com/title/#{u id}")
        index = Nokogiri::HTML(http_get(index_uri))

        RSS::Maker.make('2.0') do |maker|
          maker.channel.title = index.title
          maker.channel.link = index_uri
          maker.channel.description = index.at_css('meta[name="description"]').attr('content')

          maker.items.do_sort = true

          index.css('.chapter li:not(.charge)').each do |entry|
            link = entry.at_css('a')
            divs = link.css('div > div:not(.new)').to_a
            fail 'Unexptected HTML structure' unless divs.size == 3
            time = Time.strptime(divs[2].text + ' +0900', '%Y/%m/%d %z')
            title = divs[...2].map(&:text).join(?\s)

            maker.items.new_item do |item|
              uri = item.link = index_uri + link.attr('href')
              item.title = title
              item.date = time
              item.guid.content = uri
              item.guid.isPermaLink = true
            end
          end
        end
      end
    end

    class WebAce < Base
      provider_id 'web-ace.jp'

      def rss(id)
        sub, id = id.split(':', 2)
        raise Redirect, "https://web-ace.jp/#{u sub}/feed/rss/#{u id}/"
      end
    end

    class ComicWalker < Base
      provider_id 'comic-walker.com'

      def rss(id)
        json_uri = URI("https://comic-walker.com/api/contents/details/work?workCode=#{u id}")
        json = JSON.parse(http_get(json_uri))

        RSS::Maker.make('2.0') do |maker|
          work = json.fetch('work')

          maker.channel.title = work.fetch('title')
          maker.channel.link = "https://comic-walker.com/detail/#{u id}"
          maker.channel.description = work.fetch('summary')

          maker.items.do_sort = true

          episodes = json.dig('latestEpisodes').fetch('result')

          episodes.each do |ep|
            next unless ep.fetch('isActive')

            maker.items.new_item do |item|
              url = item.link = "https://comic-walker.com/detail/#{u id}/episodes/#{u ep.fetch('code')}?episodeType=first"
              item.title = ep.fetch('title')
              item.date = Time.parse(ep.fetch('updateDate'))
              item.guid.content = url
              item.guid.isPermaLink = true
            end
          end
        end
      end
    end
  end
end
