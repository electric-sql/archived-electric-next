defmodule Electric.Postgres.LogOffset do
  alias Electric.Postgres.Lsn

  @moduledoc """
  Uniquely identifies an operation inside the shape log.
  Combines a transaction ID with operation ID.
  """

  @type int64 :: 0..0xFFFFFFFFFFFFFFFF
  @type t :: -1 | {int64(), non_neg_integer()}

  # Comparison operators on tuples work out of the box
  # If we change internal representation to something else than a tuple
  # we may need to overload the comparison operators
  # by importing kernel except the operators and define the operators ourselves

  def make(%Lsn{} = lsn, op_index) do
    {Lsn.to_integer(lsn), op_index}
  end

  @doc """
  Regex for validating LogOffset values.
  Checks that the tx_offset and op_offset are non-negative integers.

  ## Examples

      iex> Regex.match?(regex(), to_string(before_all()))
      true

      iex> Regex.match?(regex(), to_string(first()))
      true

      iex> Regex.match?(regex(), "15/9")
      true

      iex> Regex.match?(regex(), "-2/1")
      false

      iex> Regex.match?(regex(), "2/-3")
      false
  """
  def regex(), do: ~r/(^-1$)|(^[0-9]+\/[0-9]+$)/

  @doc """
  An offset that is smaller than all offsets in the log.

  ## Examples

      iex> before_all() < first()
      true
  """
  @spec before_all() :: t
  def before_all(), do: -1

  @doc """
  The first possible offset in the log.
  """
  @spec first() :: t
  def first(), do: {0, 0}

  @doc """
  The last possible offset in the log.

  ## Examples

      iex> first() < last()
      true

      iex> make(Lsn.from_integer(10), 0) < last()
      true
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

  @doc """
  Format a LogOffset value to its text representation in an iolist.

  ## Examples
      iex> to_iolist(first())
      ["0", ?/, "0"]

      iex> to_iolist(make(Lsn.from_integer(10), 3))
      ["10", ?/, "3"]
  """
  @spec to_iolist(t) :: iolist
  def to_iolist({tx_offset, op_offset}) do
    [Integer.to_string(tx_offset), ?/, Integer.to_string(op_offset)]
  end

  @doc """
  Parse the given string as a LogOffset value.

  ## Examples

      iex> from_string("-1")
      -1

      iex> from_string("0/0")
      {0, 0}

      iex> from_string("11/13")
      {11, 13}

      iex> from_string("0/02")
      {0, 2}
  """
  @spec from_string(String.t()) :: t
  def from_string(str) when is_binary(str) do
    if str == "-1" do
      -1
    else
      [tx_offset, op_offset] = String.split(str, "/")
      {String.to_integer(tx_offset), String.to_integer(op_offset)}
    end
  end

  @doc """
  Serialise the LogOffset value to a string.

  ## Examples

      iex> to_string(-1)
      "-1"

      iex> to_string(first())
      "0/0"

      iex> to_string(make(Lsn.from_integer(10), 3))
      "10/3"
  """
  @spec to_string(t) :: String.t()
  def to_string(-1) do
    "-1"
  end

  def to_string(offset) do
    "#{to_iolist(offset)}"
  end
end
