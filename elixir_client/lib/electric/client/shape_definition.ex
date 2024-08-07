defmodule Electric.Client.ShapeDefinition do
  @moduledoc """
  Typed struct for defining a shape.

      iex> %ShapeDefinition{table: "items"}
      %ShapeDefinition{table: "items"}

  """
  use TypedStruct

  typedstruct do
    field :table, String.t(), enforce: true
    field :where, String.t()
  end
end
