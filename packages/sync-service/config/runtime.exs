import Config
import Dotenvy

config :elixir, :time_zone_database, Tz.TimeZoneDatabase
config :logger, level: :debug

if config_env() == :test, do: config(:logger, level: :info)

if config_env() in [:dev, :test] do
  source!([".env.#{config_env()}", ".env.#{config_env()}.local", System.get_env()])
end

config :telemetry_poller, :default, period: 500

config :opentelemetry,
  resource_detectors: [:otel_resource_app_env],
  resource: %{service: %{name: "electric", version: Mix.Project.config()[:version]}}

otel_export = env!("OTEL_EXPORT", :string, nil)

case otel_export do
  "honeycomb" ->
    # Exporting directly to Honeycomb.io is left here mostly for debugging purposes. Prefer
    # using the generic "otlp" export to a locally running OpenTelemetry Collector.
    # Remove this in the future.
    honeycomb_api_key = env!("HONEYCOMB_API_KEY", :string, "")

    config :opentelemetry_exporter,
      otlp_endpoint: "https://api.honeycomb.io",
      otlp_headers: [{"x-honeycomb-team", honeycomb_api_key}],
      otlp_compression: :gzip

  "otlp" ->
    if endpoint = env!("OTLP_ENDPOINT", :string, nil) do
      config :opentelemetry_exporter,
        otlp_protocol: :http_protobuf,
        otlp_endpoint: endpoint,
        otlp_compression: :gzip
    end

  "debug" ->
    # In this mode, each span is printed to stdout as soon as it ends, without batching.
    config :opentelemetry, :processors,
      otel_simple_processor: %{exporter: {:otel_exporter_stdout, []}}

  _ ->
    config :opentelemetry,
      processors: [],
      traces_exporter: :none
end

if Config.config_env() == :test do
  config :electric,
    database_config:
      PostgresqlUri.parse("postgresql://postgres:password@localhost:54321/postgres")
else
  config :electric,
    database_config: PostgresqlUri.parse(env!("DATABASE_URL"))
end

enable_integration_testing = env!("ENABLE_INTEGRATION_TESTING", :boolean, false)
cache_max_age = env!("CACHE_MAX_AGE", :integer, 60)
cache_stale_age = env!("CACHE_STALE_AGE", :integer, 60 * 5)
statsd_host = env!("STATSD_HOST", :string?, nil)

cubdb_file_path = env!("CUBDB_FILE_PATH", :string, "./shapes")

storage =
  env!(
    "STORAGE",
    fn storage ->
      case String.downcase(storage) do
        "memory" ->
          {Electric.ShapeCache.InMemoryStorage, []}

        "cubdb" ->
          {Electric.ShapeCache.CubDbStorage, file_path: cubdb_file_path}

        _ ->
          raise Dotenvy.Error, message: "storage must be one of: MEMORY, CUBDB"
      end
    end,
    {Electric.ShapeCache.CubDbStorage, file_path: cubdb_file_path}
  )

config :electric,
  allow_shape_deletion: enable_integration_testing,
  cache_max_age: cache_max_age,
  cache_stale_age: cache_stale_age,
  # Used in telemetry
  environment: config_env(),
  instance_id: env!("ELECTRIC_INSTANCE_ID", :string, Electric.Utils.uuid4()),
  telemetry_statsd_host: statsd_host,
  storage: storage
