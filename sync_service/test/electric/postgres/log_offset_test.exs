defmodule Electric.Postgres.LogOffsetTest do
  alias Electric.Postgres.Lsn

  use ExUnit.Case, async: true

  doctest Electric.Postgres.LogOffset, import: true
end
