defmodule Electric.Shapes.ShapeTest do
  use ExUnit.Case, async: true

  alias Electric.Shapes.Shape

  @opts []

  describe "from_string/2" do
    test "should parse basic shape without a schema" do
      assert {:ok, %Shape{root_table: {"public", "table"}}} = Shape.from_string("table", @opts)
    end

    test "should parse shape with a schema" do
      assert {:ok, %Shape{root_table: {"test", "table"}}} = Shape.from_string("test.table", @opts)
    end

    test "should fail to parse malformed strings" do
      assert {:error, [_]} = Shape.from_string("", @opts)
      assert {:error, [_]} = Shape.from_string(".table", @opts)
      assert {:error, [_]} = Shape.from_string("schema.", @opts)
    end
  end
end
