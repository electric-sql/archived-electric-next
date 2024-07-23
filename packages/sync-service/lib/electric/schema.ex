defmodule Electric.Schema do
  def from_column_info(column_info) do
    column_info
    |> Map.new(fn col -> {col.name, col.type} end)
  end
end
