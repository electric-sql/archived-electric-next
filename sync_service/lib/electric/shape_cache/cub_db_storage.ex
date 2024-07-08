defmodule Electric.ShapeCache.CubDbStorage do
  alias Electric.Replication.Changes
  alias Electric.Postgres.Lsn
  alias Electric.Utils
  @behaviour Electric.ShapeCache.Storage

  def shared_opts(opts) do
    file_path = Access.get(opts, :file_path, "./shapes")
    db = Access.get(opts, :db, :shape_db)

    {:ok, %{file_path: file_path, db: db}}
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link(opts) do
    File.mkdir_p(opts.file_path)
    CubDB.start_link(data_dir: opts.file_path, name: opts.db)
  end

  def snapshot_exists?(shape_id, opts) do
    has_log_entry?(shape_id, 0, opts)
  end

  def get_snapshot(shape_id, opts) do
    results =
      shape_id
      |> get_log_stream(-1, opts)
      |> Enum.to_list()

    {latest_offset(results), results}
  end

  def get_log_stream(shape_id, offset, size \\ :infinity, opts) do
    opts.db
    |> CubDB.select(
      min_key: key(shape_id, offset + 1),
      max_key: end_key(shape_id)
    )
    |> Stream.map(&storage_item_to_log_item/1)
    |> limit_stream(size)
  end

  def has_log_entry?(shape_id, offset, opts) do
    CubDB.has_key?(opts.db, key(shape_id, offset))
  end

  def make_new_snapshot!(shape_id, query_info, data_stream, opts) do
    data_stream
    |> Stream.with_index()
    |> Stream.map(&row_to_storage_item(&1, shape_id, query_info))
    |> Stream.chunk_every(500)
    |> Stream.each(fn chunk -> CubDB.put_multi(opts.db, chunk) end)
    |> Stream.run()
  end

  def append_to_log!(shape_id, lsn, xid, changes, opts) do
    base_offset = Lsn.to_integer(lsn)

    changes
    |> Enum.with_index(fn
      %{relation: _} = change, index ->
        key = Changes.build_key(change)
        value = Changes.to_json_value(change)
        action = Changes.get_action(change)
        {key(shape_id, base_offset + index), {xid, key, action, value}}
    end)
    |> then(&CubDB.put_multi(opts.db, &1))

    :ok
  end

  def cleanup!(shape_id, opts) do
    CubDB.select(opts.db,
      min_key: min_key(shape_id),
      max_key: end_key(shape_id)
    )
    |> Enum.each(fn {key, _} -> CubDB.delete(opts.db, key) end)
  end

  defp key(shape_id, lsn, index \\ 0) do
    {shape_id, {lsn, index}}
  end

  defp min_key(shape_id) do
    key(shape_id, 0, 0)
  end

  defp end_key(shape_id) do
    {shape_id, "end"}
  end

  defp row_to_storage_item({row, index}, shape_id, %Postgrex.Query{
         name: key_prefix,
         columns: columns,
         result_types: types
       }) do
    serialized_row =
      [columns, types, row]
      |> Enum.zip_with(fn
        [col, Postgrex.Extensions.UUID, val] -> {col, Utils.encode_uuid(val)}
        [col, _, val] -> {col, val}
      end)
      |> Map.new()

    offset = 0

    # FIXME: This should not assume pk columns, but we're not querying PG for that info yet
    pk = Map.fetch!(serialized_row, "id")
    key = "#{key_prefix}/#{pk}"

    {key(shape_id, offset, index), {nil, key, "insert", serialized_row}}
  end

  defp storage_item_to_log_item({{_shape_id, {offset, _}}, {xid, key, action, value}}) do
    %{key: key, value: value, headers: headers(action, xid), offset: offset}
  end

  defp headers(action, nil = _xid), do: %{action: action}
  defp headers(action, xid), do: %{action: action, txid: xid}

  defp limit_stream(stream, :infinity), do: stream
  defp limit_stream(stream, size), do: Stream.take(stream, size)

  defp latest_offset(log) do
    case Enum.reverse(log) do
      [] -> 0
      [%{offset: offset} | _] -> offset
    end
  end
end
