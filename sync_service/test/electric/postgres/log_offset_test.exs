defmodule Electric.Postgres.LogOffsetTest do
  alias Electric.Postgres.Lsn
  import Kernel, except: [to_string: 1]

  use ExUnit.Case, async: true

  doctest Electric.Postgres.LogOffset, import: true
end
