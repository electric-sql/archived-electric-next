defmodule Electric.Postgres.Inspector do
  alias Electric.Postgres.PgType
  @type relation :: {String.t(), String.t()}

  @type column_info :: %{
          name: String.t(),
          type: String.t(),
          formatted_type: String.t(),
          pk_position: non_neg_integer() | nil,
          type_id: {typid :: non_neg_integer(), typmod :: integer()}
        }

  @callback load_table_info(relation(), opts :: term()) ::
              {:ok, [column_info()]} | :table_not_found
  @callback list_types!(opts :: term()) :: [PgType.t()]

  @type inspector :: {module(), opts :: term()}

  @doc """
  Load information about a given table using a provided inspector.
  """
  @spec load_table_info(relation(), inspector()) :: {:ok, [column_info()]} | :table_not_found
  def load_table_info(relation, {module, opts}), do: module.load_table_info(relation, opts)

  @doc """
  List all known PostgreSQL types using a provided inspector.
  """
  @spec list_types!(inspector()) :: [PgType.t()]
  def list_types!({module, opts}), do: module.list_types!(opts)

  def get_pk_cols(table_info) do
    table_info
    |> Enum.reject(&is_nil(&1.pk_position))
    |> Enum.sort_by(& &1.pk_position)
    |> Enum.map(& &1.name)
  end
end
