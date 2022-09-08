require_relative "test_helper"

module Crawler
  module Refresher
    class EntryFilterTest < Minitest::Test
      def test_should_get_new_entries
        entries = sample_entries
        results = EntryFilter.filter!(entries)
        assert_equal entries.length, results.length
        results.each do |entry|
          assert_nil entry[:update]
        end
      end

      def test_should_get_updated_entries
        entries = sample_entries
        $redis.with do |connection|
          entries.each do |entry|
            connection.set(entry.public_id, 1000)
          end
        end

        filter = EntryFilter.new(entries)
        filter.fingerprint_entries
        results = filter.filter
        assert_equal entries.length, results.length

        results.each do |entry|
          assert entry[:update]
        end
      end

      def test_should_ignore_updated_entries
        entries = sample_entries
        $redis.with do |connection|
          entries.each do |entry|
            connection.set(entry.public_id, 1000)
          end
        end

        results = EntryFilter.filter!(entries, check_for_updates: false)
        assert_equal 0, results.length
      end

      def test_should_ignore_existing_entries
        entries = sample_entries
        $redis.with do |connection|
          entries.each do |entry|
            connection.set(entry.public_id, entry.content.length)
          end
        end

        filter = EntryFilter.new(entries)
        filter.fingerprint_entries
        results = filter.filter
        assert_equal 0, results.length
      end

      def test_should_ignore_old_entries
        entries = [
          sample_entries,
          sample_entries(published: (Date.today - 3).to_time),
          sample_entries(published: nil),
        ].flatten
        results = EntryFilter.filter!(entries, date_filter: (Date.today - 2).to_time, check_for_updates: false)
        assert_equal 2, results.length
      end

      def test_should_ignore_content_length_one
        entries = sample_entries
        $redis.with do |connection|
          entries.each do |entry|
            connection.set(entry.public_id, 1)
          end
        end

        results = EntryFilter.filter!(entries)
        assert_equal 0, results.length
      end

      private

      def sample_entries(published: Time.now)
        entry = OpenStruct.new(
          public_id: random_string,
          content: random_string,
          published: published,
          fingerprint: SecureRandom.hex,
          to_entry: {data: random_string}
        )
        [entry]
      end
    end
  end
end