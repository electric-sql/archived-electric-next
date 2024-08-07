defmodule Electric.Client.ShapeStreamTest do
  use ExUnit.Case, async: true

  import Support.DbSetup

  alias Electric.Client.{
    ShapeDefinition,
    ShapeStream
  }

  doctest ShapeStream, import: true

  describe "ShapeStream" do
    setup :with_unique_table

    test "streams an empty shape", %{tablename: tablename} do
      opts = [
        base_url: Application.fetch_env!(:electric_client, :electric_url),
        shape_definition: %ShapeDefinition{table: tablename}
      ]

      {:ok, pid, stream} = ShapeStream.stream(opts)

      assert [%{"headers" => %{"control" => "up-to-date"}}] = Enum.take(stream, 1)

      ShapeStream.stop(pid)
    end

    test "streams a non empty shape", %{db_conn: db, tablename: tablename} do
      {:ok, id} = insert_item(db, tablename)

      opts = [
        base_url: Application.fetch_env!(:electric_client, :electric_url),
        shape_definition: %ShapeDefinition{table: tablename}
      ]

      {:ok, pid, stream} = ShapeStream.stream(opts)

      assert [
               %{"headers" => %{"action" => "insert"}, "value" => %{"id" => ^id}},
               %{"headers" => %{"control" => "up-to-date"}}
             ] = Enum.take(stream, 2)

      ShapeStream.stop(pid)
    end

    test "streams live data changes", %{db_conn: db, tablename: tablename} do
      {:ok, id} = insert_item(db, tablename)

      opts = [
        base_url: Application.fetch_env!(:electric_client, :electric_url),
        shape_definition: %ShapeDefinition{table: tablename}
      ]

      {:ok, pid, stream} = ShapeStream.stream(opts)

      test_pid = self()

      task =
        Task.async(fn ->
          stream
          |> Stream.each(&Process.send(test_pid, &1, []))
          |> Stream.run()
        end)

      assert_receive %{"value" => %{"id" => ^id}}, 50
      assert_receive %{"headers" => %{"control" => "up-to-date"}}, 50

      {:ok, id2} = insert_item(db, tablename)
      {:ok, id3} = insert_item(db, tablename)

      assert_receive %{"value" => %{"id" => ^id2}}, 50
      assert_receive %{"value" => %{"id" => ^id3}}, 50
      assert_receive %{"headers" => %{"control" => "up-to-date"}}, 50

      Task.shutdown(task)
      ShapeStream.stop(pid)
    end

    test "is resilient to fetch errors", %{db_conn: db, tablename: tablename} do
      opts = [
        backoff: %ShapeStream.Backoff{
          delay_ms: 20,
          initial_delay_ms: 20,
          multiplier: 1
        },
        base_url: Application.fetch_env!(:electric_client, :electric_url),
        shape_definition: %ShapeDefinition{table: tablename}
      ]

      {:ok, pid, stream} = ShapeStream.stream(opts)

      test_pid = self()

      task =
        Task.async(fn ->
          stream
          |> Stream.each(&Process.send(test_pid, &1, []))
          |> Stream.run()
        end)

      assert_receive %{"headers" => %{"control" => "up-to-date"}}, 50

      {:ok, id} = insert_item(db, tablename)

      assert_receive %{"value" => %{"id" => ^id}}, 50

      # Now we mess up the fetching. First we patch the state so the
      # *next* fetch will error. Then we trigger a fetch by inserting
      # an item to force the current long poll request to return,
      # thus triggering a re-fetch with the invalid base_url.

      base_url = ShapeStream.get_state(pid, :base_url)
      :ok = ShapeStream.patch_state(pid, :base_url, "#{base_url}/not-a-valid-path")
      {:ok, _} = insert_item(db, tablename)

      Process.sleep(50)

      # Then we insert a new item and verify it's not recieved.
      # Note that we set the backoff strategy multipler to 1
      # above, so we always re-fetch every 100 ms.

      {:ok, id3} = insert_item(db, tablename)

      refute_receive %{"value" => %{"id" => ^id3}}, 50

      # Then we fix the fetching and verify that the item is recieved.
      :ok = ShapeStream.patch_state(pid, :base_url, base_url)

      assert_receive %{"value" => %{"id" => ^id3}}, 50

      Task.shutdown(task)
      ShapeStream.stop(pid)
    end
  end
end
