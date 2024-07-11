
# ElectricSQL Elixir Client

Elixir client for `electric-sql/electric-next`.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `electric_client` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:electric_client, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/elixir_client>.

## Usage

See the tests.

## Testing

Run Electric and Postgres.

Define `DATABASE_URL` and `ELECTRIC_URL` as env vars. Or see the defaults in `config/runtime.exs`.

Then run:

```sh
mix test
```
