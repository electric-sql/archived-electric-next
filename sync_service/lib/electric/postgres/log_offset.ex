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

      iex> new(Lsn.from_integer(10), 0)
      %LogOffset{tx_offset: 10, op_offset: 0}

      iex> new(11, 3)
      %LogOffset{tx_offset: 11, op_offset: 3}

      iex> new(to_tuple(new(Lsn.from_integer(5), 1)))
      %LogOffset{tx_offset: 5, op_offset: 1}

      iex> new({11, 3})
      %LogOffset{tx_offset: 11, op_offset: 3}

      iex> new({11, 3.2})
      ** (FunctionClauseError) no function clause matching in Electric.Postgres.LogOffset.new/2

      iex> new(10, -2)
      ** (FunctionClauseError) no function clause matching in Electric.Postgres.LogOffset.new/2
  """
  def new(tx_offset, op_offset)
      when is_integer(tx_offset) and tx_offset >= 0 and is_integer(op_offset) and op_offset >= 0 do
    %LogOffset{tx_offset: tx_offset, op_offset: op_offset}
  end

  def new(%Lsn{} = lsn, op_offset) do
    new(Lsn.to_integer(lsn), op_offset)
  end

  def new({tx_offset, op_offset}) do
    new(tx_offset, op_offset)
  end

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

      iex> new(Lsn.from_integer(10), 0) < last()
      true
  """
  @spec last() :: t
  def last(), do: %LogOffset{tx_offset: 0xFFFFFFFFFFFFFFFF, op_offset: :infinity}

  @doc """
  Increments the offset of the change inside the transaction.

  ## Examples

      iex> increment(new(Lsn.from_integer(10), 5))
      %LogOffset{tx_offset: 10, op_offset: 6}

      iex> new(Lsn.from_integer(10), 5) |> increment > new(Lsn.from_integer(10), 5)
      true
  """
  def increment(%LogOffset{tx_offset: tx_offset, op_offset: op_offset}) do
    %LogOffset{tx_offset: tx_offset, op_offset: op_offset + 1}
  end

  @doc """
  Returns a tuple with the tx_offset and the op_offset.

  ## Examples
      iex> to_tuple(first())
      {0, 0}

      iex> to_tuple(new(Lsn.from_integer(10), 3))
      {10, 3}
  """
  @spec to_tuple(t) :: {int64(), non_neg_integer()}
  def to_tuple(%LogOffset{tx_offset: tx_offset, op_offset: op_offset}) do
    {tx_offset, op_offset}
  end

  @doc """
  Format a LogOffset value to its text representation in an iolist.

  ## Examples
      iex> to_iolist(first())
      ["0", ?/, "0"]

      iex> to_iolist(new(Lsn.from_integer(10), 3))
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
      {:ok, %LogOffset{tx_offset: -1, op_offset: 0}}

      iex> from_string("0/0")
      {:ok, %LogOffset{tx_offset: 0, op_offset: 0}}

      iex> from_string("11/13")
      {:ok, %LogOffset{tx_offset: 11, op_offset: 13}}

      iex> from_string("0/02")
      {:ok, %LogOffset{tx_offset: 0, op_offset: 2}}

      iex> from_string("1/2/3")
      {:error, "has invalid format"}

      iex> from_string("1/2 ")
      {:error, "has invalid format"}

      iex> from_string("10")
      {:error, "has invalid format"}

      iex> from_string("10/32.1")
      {:error, "has invalid format"}
  """
  @spec from_string(String.t()) :: {:ok, t | -1}
  def from_string(str) when is_binary(str) do
    if str == "-1" do
      {:ok, before_all()}
    else
      with [tx_offset_str, op_offset_str] <- String.split(str, "/"),
           {tx_offset, ""} <- Integer.parse(tx_offset_str),
           {op_offset, ""} <- Integer.parse(op_offset_str),
           offset <- new(tx_offset, op_offset) do
        {:ok, offset}
      else
        _ -> {:error, "has invalid format"}
      end
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
