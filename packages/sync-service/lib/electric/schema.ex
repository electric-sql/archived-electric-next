defmodule Electric.Schema do
  def from_column_info(column_info) do
    Map.new(column_info, fn col -> {col.name, type(col)} end)
  end

  defp type(%{formatted_type: formatted_type}), do: String.upcase(formatted_type)
end
