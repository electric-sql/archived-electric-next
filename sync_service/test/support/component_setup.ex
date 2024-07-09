defmodule Support.ComponentSetup do
  import ExUnit.Callbacks
  alias Electric.Postgres.ReplicationClient
  alias Electric.Replication.ShapeLogStorage
  alias Electric.ShapeCache
  alias Electric.ShapeCache.InMemoryStorage

  def with_in_memory_storage(ctx) do
    {:ok, storage_opts} =
      InMemoryStorage.shared_opts(
        snapshot_ets_table: :"snapshot_ets_#{ctx.test}",
        log_ets_table: :"log_ets_#{ctx.test}"
      )

    {:ok, _} = InMemoryStorage.start_link(storage_opts)

    %{storage: {InMemoryStorage, storage_opts}}
  end

  def with_shape_cache(ctx, additional_opts \\ []) do
    shape_xmins_table = :"shape_xmins_#{ctx.test}"
    shape_meta_table = :"shape_meta_#{ctx.test}"

    start_opts =
      [
        name: :"shape_cache_#{ctx.test}",
        shape_xmins_table: shape_xmins_table,
        shape_meta_table: shape_meta_table,
        storage: ctx.storage,
        db_pool: ctx.pool
      ] ++ additional_opts

    {:ok, _pid} = ShapeCache.start_link(start_opts)

    opts = [
      server: :"shape_cache_#{ctx.test}",
      shape_xmins_table: shape_xmins_table,
      shape_meta_table: shape_meta_table
    ]

    %{
      shape_cache_opts: opts,
      shape_cache: {ShapeCache, opts}
    }
  end

  def with_shape_log_storage(ctx) do
    name = :"shape_log_storage #{ctx.test}"

    start_opts =
      [
        name: name,
        storage: ctx.storage,
        registry: ctx.registry,
        shape_cache: ctx.shape_cache
      ]

    {:ok, _pid} = ShapeLogStorage.start_link(start_opts)

    %{shape_log_storage: name}
  end

  def with_replication_client(ctx) do
    {:ok, _pid} =
      ReplicationClient.start_link(
        ctx.db_config ++
          [
            init_opts: [
              publication_name: Map.get(ctx, :publication_name, "electric_publication"),
              transaction_received:
                Map.get(
                  ctx,
                  :transaction_received,
                  {ShapeLogStorage, :store_transaction, [ctx.shape_log_storage]}
                )
            ]
          ]
      )

    %{}
  end

  def with_router_config(ctx) do
    %{
      router:
        {Electric.Plug.Router,
         storage: ctx.storage,
         registry: ctx.registry,
         shape_cache: ctx.shape_cache,
         inspector: {Electric.Postgres.Inspector, ctx.pool},
         long_poll_timeout: 4_000,
         max_age: 10,
         stale_age: 60}
    }
  end

  def with_complete_stack(ctx) do
    _ = Map.fetch!(ctx, :pool)

    registry = Module.concat(Registry, ctx.test)
    start_link_supervised!({Registry, keys: :duplicate, name: registry})

    ctx = Map.put(ctx, :registry, registry)

    [
      &with_in_memory_storage/1,
      &with_shape_cache/1,
      &with_shape_log_storage/1,
      &with_replication_client/1,
      &with_router_config/1
    ]
    |> Enum.reduce(ctx, fn func, ctx -> Map.merge(ctx, func.(ctx)) end)
  end
end
