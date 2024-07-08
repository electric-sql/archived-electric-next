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

  def new!(definition, opts) do
    case from_string(definition, opts) do
      {:ok, shape} -> shape
      {:error, [message | _]} -> raise message
    end
  end

  def from_string(definition, _opts) do
    case String.split(definition, ".") do
      [table_name] when table_name != "" ->
        {:ok, %__MODULE__{root_table: {"public", table_name}}}

      [schema_name, table_name] when schema_name != "" and table_name != "" ->
        {:ok, %__MODULE__{root_table: {schema_name, table_name}}}

      _ ->
        {:error, ["table name does not match expected format"]}
    end
  end

  def build(%{root_table: root_table, where: where}, opts) do
    with {:ok, table} <- validate_table(root_table),
         {:ok, table_info} <- load_table_info(table, opts),
         {:ok, where} <- Parser.parse_and_validate_expression(where, table_info) do
      {:ok, %__MODULE__{root_table: table, where: where}}
    end
  end

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
