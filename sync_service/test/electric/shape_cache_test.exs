defmodule Electric.ShapeCacheTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  import Support.ComponentSetup
  import Support.DbSetup
  import Support.DbStructureSetup

  alias Electric.ShapeCache.Storage
  alias Electric.ShapeCache
  alias Electric.Shapes.Shape
  alias Electric.Replication.Changes
  alias Electric.Replication.LogOffset

  @basic_query_meta %Postgrex.Query{columns: ["id"], result_types: [:text], name: "key_prefix"}
  @change_offset LogOffset.new(13, 2)
  @changes [
    %Changes.NewRecord{
      relation: {"public", "test_table"},
      record: %{"id" => "123", "name" => "Test"},
      log_offset: @change_offset
    }
  ]
  @xid 99

  @zero_offset LogOffset.first()

  @prepare_tables_noop {__MODULE__, :prepare_tables_noop, []}

  describe "get_or_create_shape_id/2" do
    setup :with_in_memory_storage

    setup(do: %{pool: :no_pool})

    setup(ctx,
      do:
        with_shape_cache(ctx,
          create_snapshot_fn: fn _, _, _, _, _ -> nil end,
          prepare_tables_fn: @prepare_tables_noop
        )
    )

    test "creates a new shape_id", %{shape_cache_opts: opts} do
      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, @zero_offset} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert is_binary(shape_id)
    end

    test "returns existing shape_id", %{shape_cache_opts: opts} do
      shape = %Shape{root_table: {"public", "items"}}
      {shape_id1, @zero_offset} = ShapeCache.get_or_create_shape_id(shape, opts)
      {shape_id2, @zero_offset} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert shape_id1 == shape_id2
    end
  end

  describe "get_or_create_shape_id/2 shape initialization" do
    setup :with_in_memory_storage

    test "creates initial snapshot if one doesn't exist", %{storage: storage} = ctx do
      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          prepare_tables_fn: @prepare_tables_noop,
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}

      {shape_id, offset} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert offset == @zero_offset
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)
      assert Storage.snapshot_exists?(shape_id, storage)
    end

    test "triggers table prep and snapshot creation only once", ctx do
      test_pid = self()

      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          prepare_tables_fn: fn nil, [{"public", "items"}] ->
            send(test_pid, {:called, :prepare_tables_fn})
          end,
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            send(test_pid, {:called, :create_snapshot_fn})
            Process.sleep(10)
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)

      # subsequent calls return the same shape_id
      for _ <- 1..10, do: assert({^shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts))

      # direct calls to genserver should still return the existing shape_id
      # before the snapshot has been created
      assert {^shape_id, _} =
               GenServer.call(Access.get(opts, :link_pid), {:create_or_wait_shape_id, shape})

      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)

      # direct calls to genserver should still return the existing shape_id
      # after the snapshot has been created
      assert {^shape_id, _} =
               GenServer.call(Access.get(opts, :link_pid), {:create_or_wait_shape_id, shape})

      assert_received {:called, :prepare_tables_fn}
      assert_received {:called, :create_snapshot_fn}
      refute_received {:called, _}
    end

    test "no-ops and warns if snapshot xmin is assigned to unknown shape_id", ctx do
      shape_id = "foo"

      %{shape_cache_opts: opts} = with_shape_cache(Map.put(ctx, :pool, nil))

      shape_meta_table = Access.get(opts, :shape_meta_table)

      log =
        capture_log(fn ->
          GenServer.cast(Access.get(opts, :link_pid), {:snapshot_xmin_known, shape_id, 10})
          Process.sleep(10)
        end)

      assert log =~
               "Got snapshot information for a #{shape_id}, that shape id is no longer valid. Ignoring."

      # should have nothing in the meta table
      assert :ets.next_lookup(shape_meta_table, :_) == :"$end_of_table"
    end
  end

  describe "get_or_create_shape_id/2 against real db" do
    setup :with_in_memory_storage
    setup :with_unique_db
    setup :with_publication
    setup :with_basic_tables
    setup :with_shape_cache

    setup %{pool: pool} do
      Postgrex.query!(pool, "INSERT INTO items (id, value) VALUES ($1, $2), ($3, $4)", [
        Ecto.UUID.dump!("721ae036-e620-43ee-a3ed-1aa3bb98e661"),
        "test1",
        Ecto.UUID.dump!("721ae036-e620-43ee-a3ed-1aa3bb98e662"),
        "test2"
      ])

      :ok
    end

    test "creates initial snapshot from DB data",
         %{storage: storage, shape_cache_opts: opts} do
      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)
      assert Storage.snapshot_exists?(shape_id, storage)
      assert {@zero_offset, stream} = Storage.get_snapshot(shape_id, storage)

      assert [%{value: %{"value" => "test1"}}, %{value: %{"value" => "test2"}}] =
               Enum.to_list(stream)
    end

    test "updates latest offset correctly",
         %{storage: storage, shape_cache_opts: opts} do
      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, initial_offset} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)
      assert Storage.snapshot_exists?(shape_id, storage)
      assert {^shape_id, offset_after_snapshot} = ShapeCache.get_or_create_shape_id(shape, opts)

      expected_offset_after_log_entry =
        LogOffset.new(Electric.Postgres.Lsn.from_integer(1000), 0)

      :ok =
        ShapeCache.append_to_log!(
          shape_id,
          expected_offset_after_log_entry,
          @xid,
          @changes,
          opts
        )

      assert {^shape_id, offset_after_log_entry} = ShapeCache.get_or_create_shape_id(shape, opts)

      assert initial_offset == @zero_offset
      assert initial_offset == offset_after_snapshot
      assert offset_after_log_entry > offset_after_snapshot
      assert offset_after_log_entry == expected_offset_after_log_entry
    end

    test "errors if appending to untracked shape_id", %{shape_cache_opts: opts} do
      shape_id = "foo"
      log_offset = LogOffset.new(1000, 0)

      {:error, log} =
        with_log(fn -> ShapeCache.append_to_log!(shape_id, log_offset, @xid, @changes, opts) end)

      assert log =~ "Tried to update latest offset for shape #{shape_id} which doesn't exist"
    end

    test "correctly propagates the error", %{shape_cache_opts: opts} do
      shape = %Shape{root_table: {"public", "nonexistent"}}

      {shape_id, log} =
        with_log(fn ->
          {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)

          assert {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} =
                   ShapeCache.wait_for_snapshot(opts[:server], shape_id)

          shape_id
        end)

      log =~ "Snapshot creation failed for #{shape_id}"

      log =~
        ~S|** (Postgrex.Error) ERROR 42P01 (undefined_table) relation "public.nonexistent" does not exist|
    end
  end

  describe "list_active_shapes/1" do
    setup :with_in_memory_storage

    test "returns empty list initially", ctx do
      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil), prepare_tables_fn: @prepare_tables_noop)

      assert ShapeCache.list_active_shapes(opts) == []
    end

    test "lists the shape as active once there is a snapshot", ctx do
      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          prepare_tables_fn: @prepare_tables_noop,
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)
      assert [{^shape_id, ^shape, 10}] = ShapeCache.list_active_shapes(opts)
    end

    test "doesn't list the shape as active until we know xmin", ctx do
      test_pid = self()

      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          prepare_tables_fn: @prepare_tables_noop,
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            ref = make_ref()
            send(test_pid, {:waiting_point, ref, self()})
            receive(do: ({:continue, ^ref} -> :ok))
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)

      # Wait until we get to the waiting point in the snapshot
      assert_receive {:waiting_point, ref, pid}

      assert ShapeCache.list_active_shapes(opts) == []

      send(pid, {:continue, ref})

      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)
      assert [{^shape_id, ^shape, 10}] = ShapeCache.list_active_shapes(opts)
    end
  end

  describe "wait_for_snapshot/4" do
    setup :with_in_memory_storage

    test "returns :ready for existing snapshot", %{storage: storage} = ctx do
      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          prepare_tables_fn: @prepare_tables_noop,
          create_snapshot_fn: fn _, _, _, _, _ -> :ok end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)

      # Manually create a snapshot
      Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)

      assert ShapeCache.wait_for_snapshot(opts[:server], shape_id) == :ready
    end

    test "returns an error if waiting is for an unknown shape id",
         %{storage: storage} = ctx do
      shape_id = "orphaned_id"

      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          prepare_tables_fn: @prepare_tables_noop,
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      assert {:error, :unknown} = ShapeCache.wait_for_snapshot(opts[:server], shape_id)

      refute Storage.snapshot_exists?(shape_id, storage)
    end

    test "handles buffering multiple callers correctly", ctx do
      test_pid = self()

      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          prepare_tables_fn: @prepare_tables_noop,
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            ref = make_ref()
            send(test_pid, {:waiting_point, ref, self()})
            receive(do: ({:continue, ^ref} -> :ok))
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})

            # Sometimes only some tasks subscribe before reaching this point, and then hang
            # if we don't actually have a snapshot. This is kind of part of the test, because
            # `wait_for_snapshot/3` should always resolve to `:ready` in concurrent situations
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)

      tasks =
        for _ <- 1..10, do: Task.async(ShapeCache, :wait_for_snapshot, [opts[:server], shape_id])

      assert_receive {:waiting_point, ref, pid}
      send(pid, {:continue, ref})

      assert Enum.all?(Task.await_many(tasks), &(&1 == :ready))
    end

    test "propagates error in snapshot creation to listeners", ctx do
      test_pid = self()

      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          prepare_tables_fn: @prepare_tables_noop,
          create_snapshot_fn: fn parent, shape_id, _, _, _storage ->
            ref = make_ref()
            send(test_pid, {:waiting_point, ref, self()})
            receive(do: ({:continue, ^ref} -> :ok))
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})

            GenServer.cast(
              parent,
              {:snapshot_failed, shape_id, %RuntimeError{message: "expected error"}, []}
            )
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      task = Task.async(fn -> ShapeCache.wait_for_snapshot(opts[:server], shape_id) end)

      log =
        capture_log(fn ->
          assert_receive {:waiting_point, ref, pid}
          send(pid, {:continue, ref})

          assert {:error, %RuntimeError{message: "expected error"}} =
                   Task.await(task)
        end)

      assert log =~ "Snapshot creation failed for #{shape_id}"
    end
  end

  describe "handle_truncate/2" do
    setup :with_in_memory_storage

    test "cleans up shape data and rotates the shape id",
         %{storage: storage} = ctx do
      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          prepare_tables_fn: @prepare_tables_noop,
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      Process.sleep(50)
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)

      Storage.append_to_log!(
        shape_id,
        1,
        [
          %Electric.Replication.Changes.NewRecord{
            relation: {"public", "items"},
            record: %{"id" => "1", "name" => "Alice"},
            log_offset: LogOffset.new(Electric.Postgres.Lsn.from_integer(1000), 0)
          }
        ],
        storage
      )

      assert Storage.snapshot_exists?(shape_id, storage)
      assert Enum.count(Storage.get_log_stream(shape_id, @zero_offset, storage)) == 1

      log = capture_log(fn -> ShapeCache.handle_truncate(opts[:server], shape_id) end)
      assert log =~ "Truncating and rotating shape id"

      # Wait a bit for the async cleanup to complete
      Process.sleep(100)

      refute Storage.snapshot_exists?(shape_id, storage)
      assert Enum.count(Storage.get_log_stream(shape_id, @zero_offset, storage)) == 0
      {shape_id2, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert shape_id != shape_id2
    end
  end

  describe "clean_shape/2" do
    setup :with_in_memory_storage

    test "cleans up shape data and rotates the shape id",
         %{storage: storage} = ctx do
      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          prepare_tables_fn: @prepare_tables_noop,
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      shape = %Shape{root_table: {"public", "items"}}
      {shape_id, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      Process.sleep(50)
      assert :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)

      Storage.append_to_log!(
        shape_id,
        1,
        [
          %Electric.Replication.Changes.NewRecord{
            relation: {"public", "items"},
            record: %{"id" => "1", "name" => "Alice"},
            log_offset: LogOffset.new(Electric.Postgres.Lsn.from_integer(1000), 0)
          }
        ],
        storage
      )

      assert Storage.snapshot_exists?(shape_id, storage)
      assert Enum.count(Storage.get_log_stream(shape_id, @zero_offset, storage)) == 1

      log = capture_log(fn -> ShapeCache.clean_shape(opts[:server], shape_id) end)
      assert log =~ "Cleaning up shape"

      # Wait a bit for the async cleanup to complete
      Process.sleep(100)

      refute Storage.snapshot_exists?(shape_id, storage)
      assert Enum.count(Storage.get_log_stream(shape_id, @zero_offset, storage)) == 0
      {shape_id2, _} = ShapeCache.get_or_create_shape_id(shape, opts)
      assert shape_id != shape_id2
    end

    test "cleans up shape swallows error if no shape to clean up", ctx do
      shape_id = "foo"

      %{shape_cache_opts: opts} =
        with_shape_cache(Map.put(ctx, :pool, nil),
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, 10})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )

      {:ok, _} = with_log(fn -> ShapeCache.clean_shape(opts[:server], shape_id) end)
    end
  end

  describe "after restart" do
    # Capture the log to hide the GenServer exit messages
    @describetag capture_log: true

    @describetag :tmp_dir

    @shape %Shape{root_table: {"public", "items"}}
    @snapshot_xmin 10

    setup :with_cub_db_storage
    setup(do: %{pool: :no_pool})

    setup(ctx,
      do:
        with_shape_cache(ctx,
          prepare_tables_fn: @prepare_tables_noop,
          create_snapshot_fn: fn parent, shape_id, _, _, storage ->
            GenServer.cast(parent, {:snapshot_xmin_known, shape_id, @snapshot_xmin})
            Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
            GenServer.cast(parent, {:snapshot_ready, shape_id})
          end
        )
    )

    test "restores shape_ids", %{shape_cache_opts: opts} = context do
      {shape_id1, _} = ShapeCache.get_or_create_shape_id(@shape, opts)
      :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id1)
      restart_shape_cache(context)
      {shape_id2, _} = ShapeCache.get_or_create_shape_id(@shape, opts)
      assert shape_id1 == shape_id2
    end

    test "restores snapshot xmins", %{shape_cache_opts: opts} = context do
      {shape_id, _} = ShapeCache.get_or_create_shape_id(@shape, opts)
      :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)
      [{^shape_id, @shape, @snapshot_xmin}] = ShapeCache.list_active_shapes(opts)

      restart_shape_cache(context)
      :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)

      assert [{^shape_id, @shape, @snapshot_xmin}] = ShapeCache.list_active_shapes(opts)
    end

    test "restores latest offset", %{shape_cache_opts: opts} = context do
      offset = @change_offset
      {shape_id, _} = ShapeCache.get_or_create_shape_id(@shape, opts)
      :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)

      :ok = ShapeCache.append_to_log!(shape_id, offset, @xid, @changes, opts)

      {^shape_id, ^offset} = ShapeCache.get_or_create_shape_id(@shape, opts)
      restart_shape_cache(context)
      :ready = ShapeCache.wait_for_snapshot(opts[:server], shape_id)
      assert {^shape_id, ^offset} = ShapeCache.get_or_create_shape_id(@shape, opts)
    end

    defp restart_shape_cache(context) do
      stop_shape_cache(context)
      # Wait 1 millisecond to ensure shape IDs are not generated the same
      Process.sleep(1)
      with_cub_db_storage(context)

      with_shape_cache(context,
        prepare_tables_fn: @prepare_tables_noop,
        create_snapshot_fn: fn parent, shape_id, _, _, storage ->
          GenServer.cast(parent, {:snapshot_xmin_known, shape_id, @snapshot_xmin})
          Storage.make_new_snapshot!(shape_id, @basic_query_meta, [["test"]], storage)
          GenServer.cast(parent, {:snapshot_ready, shape_id})
        end
      )
    end

    defp stop_shape_cache(%{storage: {_, %{db: shape_db}}, shape_cache_opts: shape_cache_opts}) do
      stop_processes([shape_cache_opts[:server], shape_db])
    end

    defp stop_processes(process_names) do
      processes =
        for name <- process_names do
          pid = Process.whereis(name)
          Process.unlink(pid)
          Process.monitor(pid)
          Process.exit(pid, :kill)
          {pid, name}
        end

      for {pid, name} <- processes do
        receive do
          {:DOWN, _, :process, ^pid, :killed} -> :process_killed
        after
          500 -> raise "#{name} process not killed"
        end
      end
    end
  end

  def prepare_tables_noop(_, _), do: :ok
end
