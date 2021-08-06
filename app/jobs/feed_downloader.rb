# frozen_string_literal: true

class FeedDownloader
  include Sidekiq::Worker

  sidekiq_options queue: :feed_downloader, retry: false, backtrace: false

  def perform(feed_id, feed_url, subscribers, critical = false)
    @feed_id     = feed_id
    @feed_url    = feed_url
    @subscribers = subscribers
    @critical    = critical
    @feed        = Feed.new(feed_id)

    throttle = Throttle.new(@feed_url, @feed.downloaded_at)
    if throttle.throttled?
      Sidekiq.logger.info "Throttled downloaded_at=#{Time.at(@feed.downloaded_at)} url=#{@feed_url}"
    elsif @critical || @feed.ok?
      download
    end
  end

  def download
    @feed.log_download!
    @response = begin
      request
    rescue Feedkit::ZlibError
      request(auto_inflate: false)
    end

    Sidekiq.logger.info "Downloaded status=#{@response.status} url=#{@feed_url}"
    parse unless @response.not_modified?(@feed.checksum)
    @feed.download_success
  rescue Feedkit::Error => exception
    @feed.download_error(exception)
    Sidekiq.logger.info "Feedkit::Error: attempts=#{@feed.attempt_count} exception=#{exception.inspect} id=#{@feed_id} url=#{@feed_url}"
  end

  def request(auto_inflate: true)
    parsed_url = Feedkit::BasicAuth.parse(@feed_url)
    url = @feed.redirect ? @feed.redirect : parsed_url.url
    Sidekiq.logger.info "Redirect: from=#{@feed_url} to=#{@feed.redirect} id=#{@feed_id}" if @feed.redirect
    Feedkit::Request.download(url,
      on_redirect:   on_redirect,
      username:      parsed_url.username,
      password:      parsed_url.password,
      last_modified: @feed.last_modified,
      etag:          @feed.etag,
      auto_inflate:  auto_inflate,
      user_agent:    "Feedbin feed-id:#{@feed_id} - #{@subscribers} subscribers"
    )
  end

  def on_redirect
    proc do |from, to|
      @feed.redirects.push Redirect.new(@feed_id, status: from.status.code, from: from.uri.to_s, to: to.uri.to_s)
    end
  end

  def parse
    @response.persist!
    parser = @critical ? FeedParserCritical : FeedParser
    job_id = parser.perform_async(@feed_id, @feed_url, @response.path, @response.encoding.to_s)
    Sidekiq.logger.info "Parse enqueued job_id: #{job_id}"
    @feed.save(@response)
  end

  def throttled?

  end
end

class FeedDownloaderCritical
  include Sidekiq::Worker
  sidekiq_options queue: :feed_downloader_critical, retry: false
  def perform(*args)
    FeedDownloader.new.perform(*args, true)
  end
end
