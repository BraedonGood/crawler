Refresher
=========

Refresher is a service meant to be run in combination with [Feedbin](https://github.com/feedbin/feedbin).

Refresher consists of a single Sidekiq job that

- Fetches and parses RSS feeds
- Checks for the existence of duplicates against a redis database
- Add new feed entries to redis to be imported back into Feedbin

Dependencies
------------

- Ruby 2.0
- Redis

Installation
------------

**Install Redis**

    brew install redis

**Clone the repository**

    git clone https://github.com/feedbin/refresher.git && cd refresher
		
**Bundle**

     bundle

**Run**

     bundle exec foreman start     