require_relative "test_helper"

class FeedTest < Minitest::Test

  def setup
    flush
  end

  def test_should_be_ok
    feed_id = 1
    feed = Feed.new(feed_id)
    feed.download_error(Exception.new)

    feed = Feed.new(feed_id)
    feed.download_success

    feed = Feed.new(feed_id)
    assert feed.ok?
  end

  def test_should_not_be_ok
    feed_id = 1
    feed = Feed.new(feed_id)
    feed.download_error(Feedkit::NotFeed.new)

    feed = Feed.new(feed_id)
    feed.download_success

    feed = Feed.new(feed_id)
    assert_equal("Feedkit::NotFeed", feed.last_error["class"])
    refute feed.ok?
  end
end
