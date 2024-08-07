defmodule Electric.Client.Util do
  @moduledoc """
  Utility functions.
  """

  @doc """
  Generate a random string. The string is twice the length of
  the number of bytes.
  """
  @spec generate_id(integer()) :: String.t()
  def generate_id(num_bytes \\ 10) do
    :crypto.strong_rand_bytes(num_bytes)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Conditional map put.

      iex> map_put_if(%{}, :a, 1, true)
      %{a: 1}

      iex> map_put_if(%{a: 1}, :a, 2, false)
      %{a: 1}

      iex> map_put_if(%{a: 1}, :a, 2, true)
      %{a: 2}

  """
  def map_put_if(map, key, value, true) do
    Map.put(map, key, value)
  end

  def map_put_if(map, _key, _value, _condition) do
    map
  end

  @doc """
  Take a number of items from the front of the queue.

  Returns the items, the number taken and the remaining queue.

      iex> {[:a], 1, _queue} = take_from_queue(Qex.new([:a, :b]), 1)

  """
  @spec take_from_queue(Qex.t(), Integer.t()) :: {list(), Integer.t(), Qex.t()}
  def take_from_queue(queue, num_demanded) when num_demanded > 0 do
    do_take(queue, {num_demanded, 0, []})
  end

  defp do_take(q, {n, t, acc}) when n > 0 do
    case Qex.pop(q) do
      {{:value, val}, rest} ->
        do_take(rest, {n - 1, t + 1, [val | acc]})

      {:empty, q} ->
        {Enum.reverse(acc), t, q}
    end
  end

  defp do_take(q, {0, t, acc}) do
    {Enum.reverse(acc), t, q}
  end
end
