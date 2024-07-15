defmodule Electric.Postgres.LogOffset do
  alias Electric.Postgres.Lsn

  @moduledoc """
  Uniquely identifies an operation inside the shape log.
  Combines a transaction ID with operation ID.
  """

  import Kernel, except: [to_charlist: 1, to_string: 1]

  alias __MODULE__, as: LogOffset

  defstruct tx_offset: 0, op_offset: 0

  @type int64 :: 0..0xFFFFFFFFFFFFFFFF
  @type t :: %LogOffset{
          tx_offset: int64(),
          op_offset: non_neg_integer()
        }

  # Comparison operators on tuples work out of the box
  # If we change internal representation to something else than a tuple
  # we may need to overload the comparison operators
  # by importing kernel except the operators and define the operators ourselves

  @doc """
  ## Examples

      iex> make(Lsn.from_integer(10), 0)
      %LogOffset{tx_offset: 10, op_offset: 0}

      iex> make(11, 3)
      %LogOffset{tx_offset: 11, op_offset: 3}

      iex> make(tx_offset(make(Lsn.from_integer(5), 1)), op_offset(make(Lsn.from_integer(5), 1)))
      %LogOffset{tx_offset: 5, op_offset: 1}
  """
  def make(%Lsn{} = lsn, op_index) do
    %LogOffset{tx_offset: Lsn.to_integer(lsn), op_offset: op_index}
  end

  def make(tx_offset, op_offset) do
    %LogOffset{tx_offset: tx_offset, op_offset: op_offset}
  end

  @doc """
  Regex for validating a stringified LogOffset.
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
  def before_all(), do: %LogOffset{tx_offset: -1, op_offset: 0}

  @doc """
  The first possible offset in the log.
  """
  @spec first() :: t
  def first(), do: %LogOffset{tx_offset: 0, op_offset: 0}

  @doc """
  The last possible offset in the log.

  ## Examples

      iex> first() < last()
      true

      iex> make(Lsn.from_integer(10), 0) < last()
      true
  """
  @spec last() :: t
  def last(), do: %LogOffset{tx_offset: 0xFFFFFFFFFFFFFFFF, op_offset: :infinity}

  @doc """
  ## Examples

      iex> tx_offset(make(Lsn.from_integer(10), 0))
      10
  """
  def tx_offset(%LogOffset{tx_offset: tx_offset, op_offset: _}), do: tx_offset

  @doc """
  ## Examples

      iex> op_offset(make(Lsn.from_integer(10), 5))
      5
  """
  def op_offset(%LogOffset{tx_offset: _, op_offset: op_offset}), do: op_offset

  @doc """
  Increments the offset of the change inside the transaction.

  ## Examples

      iex> increment(make(Lsn.from_integer(10), 5))
      %LogOffset{tx_offset: 10, op_offset: 6}

      iex> make(Lsn.from_integer(10), 5) |> increment > make(Lsn.from_integer(10), 5)
      true
  """
  def increment(%LogOffset{tx_offset: tx_offset, op_offset: op_offset}) do
    %LogOffset{tx_offset: tx_offset, op_offset: op_offset + 1}
  end

  @doc """
  Format a LogOffset value to its text representation in an iolist.

  ## Examples
      iex> to_iolist(first())
      ["0", ?/, "0"]

      iex> to_iolist(make(Lsn.from_integer(10), 3))
      ["10", ?/, "3"]

      iex> to_iolist(before_all())
      ["-1"]
  """
  @spec to_iolist(t) :: iolist
  def to_iolist(%LogOffset{tx_offset: -1, op_offset: _}) do
    [Integer.to_string(-1)]
  end

  def to_iolist(%LogOffset{tx_offset: tx_offset, op_offset: op_offset}) do
    [Integer.to_string(tx_offset), ?/, Integer.to_string(op_offset)]
  end

  @doc """
  Parse the given string as a LogOffset value.

  ## Examples

      iex> from_string("-1")
      %LogOffset{tx_offset: -1, op_offset: 0}

      iex> from_string("0/0")
      %LogOffset{tx_offset: 0, op_offset: 0}

      iex> from_string("11/13")
      %LogOffset{tx_offset: 11, op_offset: 13}

      iex> from_string("0/02")
      %LogOffset{tx_offset: 0, op_offset: 2}
  """
  @spec from_string(String.t()) :: -1 | t
  def from_string(str) when is_binary(str) do
    if str == "-1" do
      before_all()
    else
      [tx_offset, op_offset] = String.split(str, "/")
      %LogOffset{tx_offset: String.to_integer(tx_offset), op_offset: String.to_integer(op_offset)}
    end
  end

  defimpl Inspect do
    def inspect(offset, _opts) do
      "#LogOffset<#{Electric.Postgres.LogOffset.to_iolist(offset)}>"
    end
  end

  defimpl String.Chars do
    def to_string(offset), do: "#{Electric.Postgres.LogOffset.to_iolist(offset)}"
  end

  defimpl List.Chars do
    def to_charlist(offset), do: ~c'#{Electric.Postgres.LogOffset.to_iolist(offset)}'
  end

  defimpl Jason.Encoder, for: LogOffset do
    def encode(value, opts) do
      Jason.Encode.string("#{value}", opts)
    end
  end
end
