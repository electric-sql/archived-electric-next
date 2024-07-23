defmodule Electric.Replication.Changes do
  @moduledoc """
  This module contains structs that are intermediate representation of Postgres and Satellite transactions.

  Some of the core assumptions in this module:
  - We require PK always to be present for all tables
  - For now PK modification is not supported
  - PG replication protocol is expected to always send the *whole* row
  when dealing with UPDATE changes, and optionally old row if REPLICA
  identity is set to FULL.
  """

  alias Electric.Replication.Changes
  alias Electric.Replication.LogOffset

  require Logger

  @type db_identifier() :: String.t()
  @type xid() :: non_neg_integer()
  @type relation() :: {schema :: db_identifier(), table :: db_identifier()}
  @type record() :: %{(column_name :: db_identifier()) => column_data :: binary()}
  @type relation_id() :: non_neg_integer

  @typedoc """
  Tag has the form of `origin@timestamp`, where origin is a unique source id
  (UUID for Satellite clients) and timestamp is millisecond-precision UTC unix timestamp
  """
  @type tag() :: String.t()
  @type pk() :: [String.t(), ...]

  @type data_change() ::
          Changes.NewRecord.t()
          | Changes.UpdatedRecord.t()
          | Changes.DeletedRecord.t()

  @type change() :: data_change() | Changes.TruncatedRelation.t()

  defmodule Transaction do
    alias Electric.Replication.Changes

    @type t() :: %__MODULE__{
            xid: Changes.xid() | nil,
            changes: [Changes.change()],
            affected_relations: MapSet.t(Changes.relation()),
            commit_timestamp: DateTime.t(),
            lsn: Electric.Postgres.Lsn.t(),
            last_log_offset: LogOffset.t()
          }

    defstruct [
      :xid,
      :commit_timestamp,
      :lsn,
      :last_log_offset,
      changes: [],
      affected_relations: MapSet.new()
    ]

    @spec prepend_change(t(), Changes.change()) :: t()
    def prepend_change(
          %__MODULE__{changes: changes, affected_relations: rels} = txn,
          %change_mod{relation: rel} = change
        )
        when change_mod in [
               Changes.NewRecord,
               Changes.UpdatedRecord,
               Changes.DeletedRecord,
               Changes.TruncatedRelation
             ] do
      %{
        txn
        | changes: [change | changes],
          affected_relations: MapSet.put(rels, rel)
      }
    end
  end

  defmodule NewRecord do
    defstruct [:relation, :record, :log_offset, :key]

    @type t() :: %__MODULE__{
            relation: Changes.relation(),
            record: Changes.record(),
            log_offset: LogOffset.t(),
            key: String.t()
          }
  end

  defmodule UpdatedRecord do
    defstruct [
      :relation,
      :old_record,
      :record,
      :log_offset,
      :key,
      :old_key,
      tags: [],
      changed_columns: MapSet.new()
    ]

    @type t() :: %__MODULE__{
            relation: Changes.relation(),
            old_record: Changes.record() | nil,
            record: Changes.record(),
            log_offset: LogOffset.t(),
            key: String.t(),
            old_key: String.t(),
            tags: [Changes.tag()],
            changed_columns: MapSet.t()
          }

    def new(attrs) do
      __MODULE__
      |> struct(attrs)
      |> build_changed_columns()
    end

    defp build_changed_columns(%{old_record: nil} = change) do
      change
    end

    defp build_changed_columns(change) do
      %{old_record: old, record: new} = change

      # if the value is in the new but NOT the old, then it's being updated
      # if it's in the old but NOT the new, then it's staying the same
      changed =
        Enum.reduce(new, MapSet.new(), fn {col_name, new_value}, changed ->
          case Map.fetch(old, col_name) do
            :error ->
              MapSet.put(changed, col_name)

            {:ok, old_value} ->
              if old_value == new_value,
                do: changed,
                else: MapSet.put(changed, col_name)
          end
        end)

      %{change | changed_columns: changed}
    end
  end

  defmodule DeletedRecord do
    defstruct [:relation, :old_record, :log_offset, :key, tags: []]

    @type t() :: %__MODULE__{
            relation: Changes.relation(),
            old_record: Changes.record(),
            log_offset: LogOffset.t(),
            key: String.t(),
            tags: [Changes.tag()]
          }
  end

  defmodule TruncatedRelation do
    defstruct [:relation, :log_offset]

    @type t() :: %__MODULE__{
            relation: Changes.relation(),
            log_offset: LogOffset.t()
          }
  end

  defp build_key(rel, record, pk_cols) do
    IO.iodata_to_binary([prefix_from_rel(rel), ?/, record |> Map.take(pk_cols) |> Map.values()])
  end

  def fill_key(%TruncatedRelation{} = tr, _pk), do: tr

  def fill_key(%UpdatedRecord{old_record: old_record, record: new_record} = change, pk) do
    old_key = build_key(change.relation, old_record, pk)
    new_key = build_key(change.relation, new_record, pk)
    if old_key == new_key, do: %{change | key: new_key}, else: %{change | old_key: old_key, key: new_key}
  end

  def fill_key(%NewRecord{relation: relation, record: record} = change, pk), do: %{change | key: build_key(relation, record, pk)}
  def fill_key(%DeletedRecord{relation: relation, old_record: old_record} = change, pk), do: %{change | key: build_key(relation, old_record, pk)}

  defp prefix_from_rel({schema, table}), do: [?", schema, ?", ?., ?", table, ?"]

  def to_json_value(%NewRecord{record: record}), do: record
  def to_json_value(%UpdatedRecord{record: record}), do: record
  def to_json_value(%DeletedRecord{}), do: nil

  def get_action(%NewRecord{}), do: "insert"
  def get_action(%UpdatedRecord{}), do: "update"
  def get_action(%DeletedRecord{}), do: "delete"

  @doc """
  ## Examples

      iex> get_log_offset(%NewRecord{log_offset: {1, 2}})
      {1, 2}

      iex> get_log_offset(%UpdatedRecord{log_offset: {1, 2}})
      {1, 2}

      iex> get_log_offset(%DeletedRecord{log_offset: {1, 2}})
      {1, 2}

      iex> get_log_offset(%TruncatedRelation{log_offset: {1, 2}})
      {1, 2}

      iex> get_log_offset(%NewRecord{})
      ** (FunctionClauseError) no function clause matching in Electric.Replication.Changes.get_log_offset/1
  """
  def get_log_offset(%NewRecord{log_offset: offset}) when offset != nil, do: offset
  def get_log_offset(%UpdatedRecord{log_offset: offset}) when offset != nil, do: offset
  def get_log_offset(%DeletedRecord{log_offset: offset}) when offset != nil, do: offset
  def get_log_offset(%TruncatedRelation{log_offset: offset}) when offset != nil, do: offset

  @doc """
  Convert an UpdatedRecord into the corresponding NewRecord or DeletedRecord
  based on the provided `to` option.

  ## Examples

      iex> convert_update(%UpdatedRecord{record: %{id: 1}}, to: :new_record)
      %NewRecord{record: %{id: 1}}

      iex> convert_update(%UpdatedRecord{record: %{id: 2}, old_record: %{id: 1}}, to: :deleted_record)
      %DeletedRecord{old_record: %{id: 1}}

      iex> convert_update(%UpdatedRecord{record: %{id: 1}}, to: :updated_record)
      %UpdatedRecord{record: %{id: 1}}
  """
  def convert_update(%UpdatedRecord{} = change, to: :new_record) do
    %NewRecord{relation: change.relation, record: change.record}
  end

  def convert_update(%UpdatedRecord{} = change, to: :deleted_record) do
    %DeletedRecord{relation: change.relation, old_record: change.old_record}
  end

  def convert_update(%UpdatedRecord{} = change, to: :updated_record), do: change
end
