# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add WorkerStat
  end
  config.redis = {id: "refresher-server-#{::Process.pid}"}
end

Sidekiq.configure_client do |config|
  config.redis = {id: "refresher-client-#{::Process.pid}"}
end

Sidekiq.strict_args!(false)