defmodule Electric.Shapes.Shape do
  @moduledoc """
  Struct describing the requested shape
  """
  alias Electric.Replication.Eval.Parser
  alias Electric.Replication.Eval.Runner
  alias Electric.Postgres.Inspector
  alias Electric.Replication.Changes

  @enforce_keys [:root_table]
  defstruct [:root_table, :where]

  @type t() :: %__MODULE__{root_table: Electric.relation()}

  def hash(%__MODULE__{} = shape), do: :erlang.phash2(shape)

  def new!(table, shape_opts, parsing_opts) do
    case build(%{root_table: table, where: Keyword.get(shape_opts, :where)}, parsing_opts) do
      {:ok, shape} -> shape
      {:error, [message | _]} -> raise message
      {:error, message} when is_binary(message) -> raise message
    end
  end

  def build(%{root_table: root_table, where: where}, opts) do
    with {:ok, table} <- validate_table(root_table),
         {:ok, table_info} <- load_table_info(table, opts),
         {:ok, where} <- maybe_parse_where_clause(where, table_info) do
      {:ok, %__MODULE__{root_table: table, where: where}}
    end
  end

  defp maybe_parse_where_clause(nil, _), do: {:ok, nil}

  defp maybe_parse_where_clause(where, info),
    do: Parser.parse_and_validate_expression(where, info)

  defp load_table_info(table, opts) do
    case Inspector.load_table_info(opts[:conn], table) do
      [] ->
        {:error, ["table not found"]}

      table_info ->
        # %{["column_name"] => :type}
        {:ok,
         Map.new(table_info, fn row ->
           {[row["attname"]], String.to_atom(row["typname"])}
         end)}
    end
  end

  defp validate_table(definition) when is_binary(definition) do
    case String.split(definition, ".") do
      [table_name] when table_name != "" ->
        {:ok, {"public", table_name}}

      [schema_name, table_name] when schema_name != "" and table_name != "" ->
        {:ok, {schema_name, table_name}}

      _ ->
        {:error, ["table name does not match expected format"]}
    end
  end

  def record_in_shape?(where, record) do
    with {:ok, refs} <- Runner.record_to_ref_values(where.used_refs, record),
         {:ok, evaluated} <- Runner.execute(where, refs) do
      if is_nil(evaluated), do: false, else: evaluated
    else
      _ -> false
    end
  end

  def convert_change(%__MODULE__{root_table: table}, %{relation: relation})
      when table != relation,
      do: []

  def convert_change(%__MODULE__{where: nil}, change), do: [change]

  def convert_change(%__MODULE__{where: where}, change)
      when is_struct(change, Changes.NewRecord)
      when is_struct(change, Changes.DeletedRecord) do
    record = if is_struct(change, Changes.NewRecord), do: change.record, else: change.old_record
    if record_in_shape?(where, record), do: [change], else: []
  end

  def convert_change(
        %__MODULE__{where: where},
        %Changes.UpdatedRecord{old_record: old_record, record: record} = change
      ) do
    old_record_in_shape = record_in_shape?(where, old_record)
    new_record_in_shape = record_in_shape?(where, record)

    case {old_record_in_shape, new_record_in_shape} do
      {true, true} -> [change]
      {true, false} -> [Changes.convert_update(change, to: :deleted_record)]
      {false, true} -> [Changes.convert_update(change, to: :new_record)]
      {false, false} -> []
    end
  end
end

defimpl Inspect, for: Electric.Shapes.Shape do
  import Inspect.Algebra

  def inspect(%Electric.Shapes.Shape{} = shape, _opts) do
    {schema, table} = shape.root_table

    where = if shape.where, do: concat(["[where: \"", shape.where.query, "\"], "]), else: ""

    concat(["Shape.new!(\"", schema, ".", table, "\", ", where, "opts)"])
  end
end
