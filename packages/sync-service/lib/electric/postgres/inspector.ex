defmodule Electric.Postgres.InspectorBehaviour do
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
  @callback list_types(opts :: term()) :: [PgType.t()]
end

defmodule Electric.Postgres.EtsInspector do
  alias Electric.Postgres
  use GenServer

  @default_pg_info_table :pg_info_table

  def start_link(opts),
    do:
      GenServer.start_link(
        __MODULE__,
        Map.new(opts) |> Map.put_new(:pg_info_table, @default_pg_info_table),
        name: Access.get(opts, :name, __MODULE__)
      )

  def init(opts) do
    pg_info_table = :ets.new(opts.pg_info_table, [:named_table, :public, :set])

    state = %{
      pg_info_table: pg_info_table,
      pg_pool: opts.pool
    }

    {:ok, state}
  end

  def load_table_info({namespace, tbl}, opts) do
    ets_table = Access.get(opts, :pg_info_table, @default_pg_info_table)

    case :ets.lookup_element(ets_table, {{namespace, tbl}, :columns}, 2, :not_found) do
      :not_found ->
        case GenServer.call(opts[:server], {:load_table_info, {namespace, tbl}}) do
          {:error, err, stacktrace} -> reraise err, stacktrace
          result -> result
        end

      found ->
        {:ok, found}
    end
  end

  def handle_call({:load_table_info, {namespace, tbl}}, _from, state) do
    case :ets.lookup(state.pg_info_table, {{namespace, tbl}, :columns}) do
      [found] ->
        {:reply, {:ok, found}, state}

      [] ->
        case Electric.Postgres.Inspector.load_table_info({namespace, tbl}, state.pg_pool) do
          :table_not_found ->
            {:reply, :table_not_found, state}

          {:ok, info} ->
            # store
            :ets.insert(state.pg_info_table, {{{namespace, tbl}, :columns}, info})
            {:reply, {:ok, info}, state}
        end
    end
  rescue
    e -> {:reply, {:error, e, __STACKTRACE__}, state}
  end
end

defmodule Electric.Postgres.Inspector do
  alias Electric.Postgres.PgType
  @behaviour Electric.Postgres.InspectorBehaviour

  @doc """
  Load table information (refs) from the database
  """
  def load_table_info({namespace, tbl}, conn) do
    query = """
    SELECT
      attname as name,
      (atttypid, atttypmod) as type_id,
      typname as type,
      format_type(pg_attribute.atttypid, pg_attribute.atttypmod) AS formatted_type,
      array_position(indkey, attnum) as pk_position
    FROM pg_class
    JOIN pg_namespace ON relnamespace = pg_namespace.oid
    JOIN pg_attribute ON attrelid = pg_class.oid AND attnum >= 0
    JOIN pg_type ON atttypid = pg_type.oid
    JOIN pg_index ON indrelid = pg_class.oid AND indisprimary
    WHERE relname = $1 AND nspname = $2
    ORDER BY pg_class.oid, attnum
    """

    result = Postgrex.query!(conn, query, [tbl, namespace])

    if Enum.empty?(result.rows) do
      :table_not_found
    else
      columns = Enum.map(result.columns, &String.to_atom/1)
      rows = Enum.map(result.rows, fn row -> Enum.zip(columns, row) |> Map.new() end)
      {:ok, rows}
    end
  end

  @doc """
  List all types in the database
  """
  def list_types!(conn) do
    query = """
    SELECT
      nspname,
      t.typname,
      t.oid,
      t.typarray,
      t.typelem,
      t.typlen,
      t.typtype,
      a.oid IS NOT NULL as is_array
    FROM pg_type t
    JOIN pg_namespace ON pg_namespace.oid = t.typnamespace
    LEFT JOIN pg_type a ON t.oid = a.typarray
    WHERE
      t.typtype = ANY($1::char[])
    ORDER BY t.oid
    """

    types = Enum.map([:BASE, :DOMAIN, :ENUM], &PgType.encode_kind/1)

    %{rows: rows} = Postgrex.query!(conn, query, [types])

    Enum.map(rows, &PgType.from_list/1)
  end
end
