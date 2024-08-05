defmodule Electric.Plug.LabelProcessPlug do
  @moduledoc """
  A plug that assists debugging by labelling processes that handle requests with
  details about the request.
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> process_label()
    |> Process.set_label()

    conn
  end

  @doc """
  Returns a description of the HTTP request to be used as the lable for the request process.

  ## Examples

      iex> process_label(%{method: "GET", request_path: "/v1/shape/users", query_string: "offset=-1"})
      "GET /v1/shape/users?offset=-1"

      iex> process_label(%{method: "GET", request_path: "/v1/shape/users", query_string: ""})
      "GET /v1/shape/users"
  """
  def process_label(conn) do
    "#{conn.method} #{conn.request_path}#{query_suffix(conn)}"
  end

  defp query_suffix(%{query_string: ""}), do: ""
  defp query_suffix(%{query_string: query_string}), do: "?#{query_string}"
end
