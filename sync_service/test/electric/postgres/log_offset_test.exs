defmodule Electric.Postgres.LogOffsetTest do
  alias Electric.Postgres.Lsn
  alias Electric.Postgres.LogOffset

  use ExUnit.Case, async: true

  doctest LogOffset, import: true
end
