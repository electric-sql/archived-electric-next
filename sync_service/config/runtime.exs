import Config
import Dotenvy

if config_env() in [:dev, :test] do
  source!([".env.#{config_env()}", ".env.#{config_env()}.local", System.get_env()])
end

config :logger, level: :debug

if Config.config_env() == :test do
  config :electric,
    database_config:
      PostgresqlUri.parse("postgresql://postgres:password@localhost:54321/postgres")
else
  config :electric,
    database_config: PostgresqlUri.parse(env!("DATABASE_URL"))
end

statsd_host = env!("STATSD_HOST", :string?, nil)

config :electric,
  # Used in telemetry
  instance_id: env!("ELECTRIC_INSTANCE_ID", :string, Electric.Utils.uuid4()),
  telemetry_statsd_host: statsd_host
