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
  end
end
