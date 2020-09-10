# frozen_string_literal: true

class FeedDownloader
  attr_accessor :retry_count
  include Sidekiq::Worker

  sidekiq_options queue: :feed_downloader, dead: false, backtrace: false

  sidekiq_retry_in do |count, exception|
    ([count, 8].max ** 4) + 15 + (rand(30) * (count + 1))
  end

  sidekiq_retries_exhausted do |message, exception|
    feed_id, url = message["args"]
    Retry.clear!(feed_id)
    Sidekiq.logger.info "sidekiq_retries_exhausted: url: #{url}"
  end

  def perform(feed_id, feed_url, subscribers, critical = false)
    @feed_id     = feed_id
    @feed_url    = feed_url
    @subscribers = subscribers
    @critical    = critical
    @redirects   = []

    @retry       = Retry.new(feed_id)
    @cached      = HTTPCache.new(feed_id)

    download unless retrying?
  end

  def download
    @response = request
    @retry.clear!
    if @response.not_modified?(@cached.checksum)
      Sidekiq.logger.info "Download success, not modified url: #{@feed_url}"
    else
      Sidekiq.logger.info "Download success, parsing url: #{@feed_url}"
      parse
    end
    RedirectCache.save(@redirects, feed_url: @feed_url)
  rescue Feedkit::Error => exception
    @retry.retry!
    Sidekiq.logger.info "Feedkit::Error: count: #{retry_count.inspect} url: #{@feed_url} message: #{exception.message}"
    raise
  rescue => exception
    Sidekiq.logger.error <<-EOD
      Exception: #{exception.inspect}: #{@feed_url}
      Message: #{exception.message.inspect}
      Backtrace: #{exception.backtrace.inspect}
    EOD
  end

  def request
    etag          = @critical ? nil : @cached.etag
    last_modified = @critical ? nil : @cached.last_modified
    Feedkit::Request.download(@feed_url,
      on_redirect:   on_redirect,
      last_modified: last_modified,
      etag:          etag,
      user_agent:    "Feedbin feed-id:#{@feed_id} - #{@subscribers} subscribers"
    )
  end

  def on_redirect
    proc do |from, to|
      @redirects.push Redirect.new(@feed_id, status: from.status.code, from: from.uri.to_s, to: to.uri.to_s)
    end
  end

  def parse
    @response.persist!
    parser = @critical ? FeedParserCritical : FeedParser
    job_id = parser.perform_async(@feed_id, @feed_url, @response.path)
    Sidekiq.logger.info "Parse enqueued job_id: #{job_id}"
    @cached.save(@response)
  end

  def retrying?
    result = retry_count.nil? && @retry.retrying?
    Sidekiq.logger.info "Skip: count: #{@retry.count} url: #{@feed_url}" if result
    result
  end
end

class FeedDownloaderCritical
  include Sidekiq::Worker
  sidekiq_options queue: :feed_downloader_critical, retry: false
  def perform(*args)
    FeedDownloader.new.perform(*args, true)
  end
end
