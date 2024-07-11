defmodule Electric.Postgres.LogOffset do
  alias Electric.Postgres.Lsn

  @moduledoc """
  Uniquely identifies an operation inside the shape log.
  Combines a transaction ID with operation ID.
  """

  @type int64 :: 0..0xFFFFFFFFFFFFFFFF
  @type t :: {int64(), non_neg_integer()}

  # Comparison operators on tuples works out of the box
  # If we change internal representation to something else than a tuple
  # we may need to overload the comparison operators
  # by importing kernel except the operators and define the operators ourselves

  def make(%Lsn{} = lsn, op_index) do
    {Lsn.to_integer(lsn), op_index}
  end

  @doc """
  An offset that is smaller than all offsets in the log.

  ## Examples

      iex> before_all() < first()
      true
  """
  @spec before_all() :: t
  def before_all(), do: {-1, 0}

  @doc """
  The first possible offset in the log.
  """
  @spec first() :: t
  def first(), do: {0, 0}

  @doc """
  The last possible offset in the log.
  """
  @spec last() :: t
  def last(), do: {0xFFFFFFFFFFFFFFFF, :infinity}

  @doc """
  ## Examples

      iex> tx_offset(make(Lsn.from_integer(10), 0))
      10
  """
  def tx_offset({tx_offset, _}), do: tx_offset

  @doc """
  ## Examples

      iex> op_offset(make(Lsn.from_integer(10), 5))
      5
  """
  def op_offset({_, op_offset}), do: op_offset

  @doc """
  Increments the offset of the change inside the transaction.

  ## Examples

      iex> increment(make(Lsn.from_integer(10), 5))
      {10, 6}

      iex> make(Lsn.from_integer(10), 5) |> increment > make(Lsn.from_integer(10), 5)
      true
  """
  def increment({tx_offset, op_offset}), do: {tx_offset, op_offset + 1}
end
