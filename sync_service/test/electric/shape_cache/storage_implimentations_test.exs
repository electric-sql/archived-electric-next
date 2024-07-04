defmodule Electric.ShapeCache.StorageTest do
  alias Electric.ShapeCache.CubDbStorage
  alias Electric.ShapeCache.InMemoryStorage
  alias Electric.Utils
  use ExUnit.Case, async: true
  @shape_id "the-shape-id"
  @query_info %Postgrex.Query{
    name: "the-table",
    columns: ["id", "title"],
    result_types: [Postgrex.Extensions.UUID, Postgrex.Extensions.Raw]
  }
  @data_stream [
    [<<5, 94, 142, 207, 61, 175, 79, 159, 177, 27, 127, 191, 231, 56, 119, 172>>, "row1"],
    [<<184, 20, 148, 8, 113, 209, 74, 210, 131, 194, 218, 250, 115, 14, 49, 203>>, "row2"]
  ]

  for module <- [InMemoryStorage, CubDbStorage] do
    module_name = module |> Module.split() |> List.last()

    describe "#{module_name}.snapshot_exists?/2" do
      setup do
        {:ok, %{module: unquote(module)}}
      end

      setup :start_storage

      test "returns false when shape does not exist", %{module: storage, opts: opts} do
        assert storage.snapshot_exists?(@shape_id, opts) == false
      end

      test "returns true when shape does exist", %{module: storage, opts: opts} do
        storage.make_new_snapshot!(@shape_id, @query_info, @data_stream, opts)

        assert storage.snapshot_exists?(@shape_id, opts) == true
      end
    end

    describe "#{module_name}.get_snapshot/2" do
      setup do
        {:ok, %{module: unquote(module)}}
      end

      setup :start_storage

      test "returns empty list when shape does not exist", %{module: storage, opts: opts} do
        assert {_, []} = storage.get_snapshot(@shape_id, opts)
      end

      test "returns LSN of 0 when shape does not exist", %{module: storage, opts: opts} do
        assert {0, _} = storage.get_snapshot(@shape_id, opts)
      end

      test "returns snapshot when shape does exist", %{module: storage, opts: opts} do
        storage.make_new_snapshot!(@shape_id, @query_info, @data_stream, opts)

        assert {_,
                [
                  %{
                    offset: 0,
                    value: %{"id" => "055e8ecf-3daf-4f9f-b11b-7fbfe73877ac", "title" => "row1"},
                    key: "the-table/055e8ecf-3daf-4f9f-b11b-7fbfe73877ac",
                    headers: %{action: "insert"}
                  },
                  %{
                    offset: 0,
                    value: %{"id" => "b8149408-71d1-4ad2-83c2-dafa730e31cb", "title" => "row2"},
                    key: "the-table/b8149408-71d1-4ad2-83c2-dafa730e31cb",
                    headers: %{action: "insert"}
                  }
                ]} = storage.get_snapshot(@shape_id, opts)
      end

      # TODO Why is the LSN still 0 in this case?
      test "returns LSN of 0 when shape does exist", %{module: storage, opts: opts} do
        storage.make_new_snapshot!(@shape_id, @query_info, @data_stream, opts)

        {0, _} = storage.get_snapshot(@shape_id, opts)
      end
    end

    describe "#{module_name}.cleanup!/2" do
      setup do
        {:ok, %{module: unquote(module)}}
      end

      setup :start_storage

      test "causes snapshot_exists?/2 to return false", %{module: storage, opts: opts} do
        storage.make_new_snapshot!(@shape_id, @query_info, @data_stream, opts)

        storage.cleanup!(@shape_id, opts)

        assert storage.snapshot_exists?(@shape_id, opts) == false
      end

      test "causes get_snapshot/2 to return empty list", %{module: storage, opts: opts} do
        storage.make_new_snapshot!(@shape_id, @query_info, @data_stream, opts)

        storage.cleanup!(@shape_id, opts)

        assert {_, []} = storage.get_snapshot(@shape_id, opts)
      end

      test "causes get_snapshot/2 to return an LSN of 0", %{module: storage, opts: opts} do
        storage.make_new_snapshot!(@shape_id, @query_info, @data_stream, opts)

        storage.cleanup!(@shape_id, opts)

        assert {0, _} = storage.get_snapshot(@shape_id, opts)
      end
    end
  end

  defp start_storage(%{module: module}) do
    {:ok, opts} = module |> opts() |> module.shared_opts()
    {:ok, _} = module.start_link(opts)

    on_exit(fn ->
      teardown(module, opts)
    end)

    {:ok, %{module: module, opts: opts}}
  end

  defp opts(InMemoryStorage) do
    [
      snapshot_ets_table: String.to_atom("snapshot_ets_table_#{Utils.uuid4()}"),
      log_ets_table: String.to_atom("log_ets_table_#{Utils.uuid4()}")
    ]
  end

  defp opts(CubDbStorage) do
    file_path = "./test/db"
    File.mkdir(file_path)

    [
      db: String.to_atom("shape_cubdb_#{Utils.uuid4()}"),
      file_path: file_path
    ]
  end

  defp teardown(InMemoryStorage, _opts), do: :ok

  defp teardown(CubDbStorage, opts) do
    File.rm_rf!(opts.file_path)
  end
end
