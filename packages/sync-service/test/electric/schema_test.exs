defmodule Electric.SchemaTest do
  use Support.TransactionCase, async: true

  alias Electric.Schema
  alias Electric.Postgres.Inspector.DirectInspector

  @types [
    %{
      postgres_type: "SMALLINT",
      schema: %{type: "int2", dimensions: 0}
    },
    %{
      postgres_type: "INT2",
      schema: %{type: "int2", dimensions: 0}
    },
    %{
      postgres_type: "INTEGER",
      schema: %{type: "int4", dimensions: 0}
    },
    %{
      postgres_type: "INT4",
      schema: %{type: "int4", dimensions: 0}
    },
    %{
      postgres_type: "SERIAL",
      schema: %{type: "int4", dimensions: 0}
    },
    %{
      postgres_type: "BIGINT",
      schema: %{type: "int8", dimensions: 0}
    },
    %{
      postgres_type: "INT8",
      schema: %{type: "int8", dimensions: 0}
    },
    %{
      postgres_type: "MONEY",
      schema: %{type: "money", dimensions: 0}
    },
    %{
      postgres_type: "VARCHAR",
      schema: %{type: "varchar", dimensions: 0}
    },
    %{
      postgres_type: "VARCHAR(123)",
      schema: %{type: "varchar", dimensions: 0, max_length: 123}
    },
    %{
      postgres_type: "VARCHAR(123)[]",
      schema: %{type: "varchar", max_length: 123, dimensions: 1}
    },
    %{
      postgres_type: "VARCHAR(123)[][]",
      schema: %{type: "varchar", max_length: 123, dimensions: 2}
    },
    %{
      postgres_type: "CHARACTER VARYING(123)",
      schema: %{type: "varchar", dimensions: 0, max_length: 123}
    },
    %{
      postgres_type: "CHAR",
      schema: %{type: "bpchar", dimensions: 0, length: 1}
    },
    %{
      postgres_type: "CHARACTER",
      schema: %{type: "bpchar", dimensions: 0, length: 1}
    },
    %{
      postgres_type: "CHARACTER[]",
      schema: %{type: "bpchar", dimensions: 1, length: 1}
    },
    %{
      postgres_type: "BPCHAR",
      schema: %{type: "bpchar", dimensions: 0}
    },
    %{
      postgres_type: "BPCHAR[]",
      schema: %{type: "bpchar", dimensions: 1}
    },
    %{
      postgres_type: "TEXT",
      schema: %{type: "text", dimensions: 0}
    },
    %{
      postgres_type: "BPCHAR(9)",
      schema: %{type: "bpchar", dimensions: 0, length: 9}
    },
    %{
      postgres_type: "BPCHAR(9)[]",
      schema: %{type: "bpchar", dimensions: 1, length: 9}
    },
    %{
      postgres_type: "BYTEA",
      schema: %{type: "bytea", dimensions: 0}
    },
    %{
      postgres_type: "DATE",
      chema: %{type: "date", dimensions: 0}
    },
    %{
      postgres_type: "TIME",
      schema: %{type: "time", dimensions: 0}
    },
    %{
      postgres_type: "TIME(3)",
      schema: %{type: "time", dimensions: 0, precision: 3}
    },
    %{
      postgres_type: "TIME WITH TIME ZONE",
      schema: %{type: "timetz", dimensions: 0}
    },
    %{
      postgres_type: "TIME(3) WITH TIME ZONE",
      schema: %{type: "timetz", dimensions: 0, precision: 3}
    },
    %{
      postgres_type: "TIMESTAMP",
      schema: %{type: "timestamp", dimensions: 0}
    },
    %{
      postgres_type: "TIMESTAMP(3)",
      schema: %{type: "timestamp", dimensions: 0, precision: 3}
    },
    %{
      postgres_type: "TIMESTAMP WITH TIME ZONE",
      schema: %{type: "timestamptz", dimensions: 0}
    },
    %{
      postgres_type: "TIMESTAMP(3) WITH TIME ZONE",
      schema: %{type: "timestamptz", dimensions: 0, precision: 3}
    },
    %{
      postgres_type: "INTERVAL",
      schema: %{type: "interval", dimensions: 0}
    },
    %{
      postgres_type: "INTERVAL YEAR",
      schema: %{type: "interval", dimensions: 0, fields: "YEAR"}
    },
    %{
      postgres_type: "INTERVAL MONTH",
      schema: %{type: "interval", dimensions: 0, fields: "MONTH"}
    },
    %{
      postgres_type: "INTERVAL DAY",
      schema: %{type: "interval", dimensions: 0, fields: "DAY"}
    },
    %{
      postgres_type: "INTERVAL HOUR",
      schema: %{type: "interval", dimensions: 0, fields: "HOUR"}
    },
    %{
      postgres_type: "INTERVAL MINUTE",
      schema: %{type: "interval", dimensions: 0, fields: "MINUTE"}
    },
    %{
      postgres_type: "INTERVAL SECOND",
      schema: %{type: "interval", dimensions: 0, fields: "SECOND"}
    },
    %{
      postgres_type: "INTERVAL YEAR TO MONTH",
      schema: %{type: "interval", dimensions: 0, fields: "YEAR TO MONTH"}
    },
    %{
      postgres_type: "INTERVAL DAY TO HOUR",
      schema: %{type: "interval", dimensions: 0, fields: "DAY TO HOUR"}
    },
    %{
      postgres_type: "INTERVAL DAY TO MINUTE",
      schema: %{type: "interval", dimensions: 0, fields: "DAY TO MINUTE"}
    },
    %{
      postgres_type: "INTERVAL DAY TO SECOND",
      schema: %{type: "interval", dimensions: 0, fields: "DAY TO SECOND"}
    },
    %{
      postgres_type: "INTERVAL HOUR TO MINUTE",
      schema: %{type: "interval", dimensions: 0, fields: "HOUR TO MINUTE"}
    },
    %{
      postgres_type: "INTERVAL HOUR TO SECOND",
      schema: %{type: "interval", dimensions: 0, fields: "HOUR TO SECOND"}
    },
    %{
      postgres_type: "INTERVAL MINUTE TO SECOND",
      schema: %{type: "interval", dimensions: 0, fields: "MINUTE TO SECOND"}
    },
    %{
      postgres_type: "INTERVAL(4)",
      schema: %{type: "interval", dimensions: 0, precision: 4}
    },
    %{
      postgres_type: "INTERVAL SECOND(4)",
      schema: %{type: "interval", dimensions: 0, precision: 4, fields: "SECOND"}
    },
    %{
      postgres_type: "INTERVAL SECOND(4)[]",
      schema: %{type: "interval", dimensions: 1, precision: 4, fields: "SECOND"}
    },
    %{
      postgres_type: "INTERVAL MINUTE TO SECOND[][]",
      schema: %{type: "interval", dimensions: 2, fields: "MINUTE TO SECOND"}
    },
    %{
      postgres_type: "BOOLEAN",
      schema: %{type: "bool", dimensions: 0}
    },
    %{
      postgres_type: "NUMERIC",
      schema: %{type: "numeric", dimensions: 0}
    },
    %{
      postgres_type: "REAL",
      schema: %{type: "float4", dimensions: 0}
    },
    %{
      postgres_type: "FLOAT4",
      schema: %{type: "float4", dimensions: 0}
    },
    %{
      postgres_type: "DOUBLE PRECISION",
      schema: %{type: "float8", dimensions: 0}
    },
    %{
      postgres_type: "FLOAT8",
      schema: %{type: "float8", dimensions: 0}
    },
    %{
      postgres_type: "BIT",
      schema: %{type: "bit", dimensions: 0, length: 1}
    },
    %{
      postgres_type: "BIT[]",
      schema: %{type: "bit", dimensions: 1, length: 1}
    },
    %{
      postgres_type: "BIT(5)",
      schema: %{type: "bit", dimensions: 0, length: 5}
    },
    %{
      postgres_type: "BIT(5)[]",
      schema: %{type: "bit", dimensions: 1, length: 5}
    },
    %{
      postgres_type: "BIT VARYING(5)",
      schema: %{type: "varbit", dimensions: 0, length: 5}
    },
    %{
      postgres_type: "BIT VARYING(5)[]",
      schema: %{type: "varbit", dimensions: 1, length: 5}
    },
    %{
      postgres_type: "NUMERIC(5,3)",
      schema: %{type: "numeric", dimensions: 0, precision: 5, scale: 3}
    },
    %{
      postgres_type: "NUMERIC(5,3)[]",
      schema: %{type: "numeric", dimensions: 1, precision: 5, scale: 3}
    },
    %{
      postgres_type: "NUMERIC(5)",
      schema: %{type: "numeric", dimensions: 0, precision: 5, scale: 0}
    },
    %{
      postgres_type: "NUMERIC(5)[]",
      schema: %{type: "numeric", dimensions: 1, precision: 5, scale: 0}
    },
    %{
      postgres_type: "POINT",
      schema: %{type: "point", dimensions: 0}
    },
    %{
      postgres_type: "LINE",
      schema: %{type: "line", dimensions: 0}
    },
    %{
      postgres_type: "LSEG",
      schema: %{type: "lseg", dimensions: 0}
    },
    %{
      postgres_type: "BOX",
      schema: %{type: "box", dimensions: 0}
    },
    %{
      postgres_type: "PATH",
      schema: %{type: "path", dimensions: 0}
    },
    %{
      postgres_type: "POLYGON",
      schema: %{type: "polygon", dimensions: 0}
    },
    %{
      postgres_type: "CIRCLE",
      schema: %{type: "circle", dimensions: 0}
    },
    %{
      postgres_type: "CIDR",
      schema: %{type: "cidr", dimensions: 0}
    },
    %{
      postgres_type: "INET",
      schema: %{type: "inet", dimensions: 0}
    },
    %{
      postgres_type: "MACADDR",
      schema: %{type: "macaddr", dimensions: 0}
    },
    %{
      postgres_type: "MACADDR8",
      schema: %{type: "macaddr8", dimensions: 0}
    },
    %{
      postgres_type: "TSVECTOR",
      schema: %{type: "tsvector", dimensions: 0}
    },
    %{
      postgres_type: "TSQUERY",
      schema: %{type: "tsquery", dimensions: 0}
    },
    %{
      postgres_type: "UUID",
      schema: %{type: "uuid", dimensions: 0}
    },
    %{
      postgres_type: "XML",
      schema: %{type: "xml", dimensions: 0}
    },
    %{
      postgres_type: "JSON",
      schema: %{type: "json", dimensions: 0}
    },
    %{
      postgres_type: "JSONB",
      schema: %{type: "jsonb", dimensions: 0}
    },
    %{
      postgres_type: "JSONPATH",
      schema: %{type: "jsonpath", dimensions: 0}
    },
    %{
      postgres_type: "INT4RANGE",
      schema: %{type: "int4range", dimensions: 0}
    },
    %{
      postgres_type: "INT4MULTIRANGE",
      schema: %{type: "int4multirange", dimensions: 0}
    },
    %{
      postgres_type: "INT8RANGE",
      schema: %{type: "int8range", dimensions: 0}
    },
    %{
      postgres_type: "INT8MULTIRANGE",
      schema: %{type: "int8multirange", dimensions: 0}
    },
    %{
      postgres_type: "NUMRANGE",
      schema: %{type: "numrange", dimensions: 0}
    },
    %{
      postgres_type: "NUMMULTIRANGE",
      schema: %{type: "nummultirange", dimensions: 0}
    },
    %{
      postgres_type: "TSRANGE",
      schema: %{type: "tsrange", dimensions: 0}
    },
    %{
      postgres_type: "TSMULTIRANGE",
      schema: %{type: "tsmultirange", dimensions: 0}
    },
    %{
      postgres_type: "TSTZRANGE",
      schema: %{type: "tstzrange", dimensions: 0}
    },
    %{
      postgres_type: "TSTZMULTIRANGE",
      schema: %{type: "tstzmultirange", dimensions: 0}
    },
    %{
      postgres_type: "DATERANGE",
      schema: %{type: "daterange", dimensions: 0}
    },
    %{
      postgres_type: "DATEMULTIRANGE",
      schema: %{type: "datemultirange", dimensions: 0}
    },
    %{
      postgres_type: "OID",
      schema: %{type: "oid", dimensions: 0}
    },
    %{
      postgres_type: "REGCLASS",
      schema: %{type: "regclass", dimensions: 0}
    },
    %{
      postgres_type: "REGCOLLATION",
      schema: %{type: "regcollation", dimensions: 0}
    },
    %{
      postgres_type: "REGCONFIG",
      schema: %{type: "regconfig", dimensions: 0}
    },
    %{
      postgres_type: "REGDICTIONARY",
      schema: %{type: "regdictionary", dimensions: 0}
    },
    %{
      postgres_type: "REGNAMESPACE",
      schema: %{type: "regnamespace", dimensions: 0}
    },
    %{
      postgres_type: "REGOPER",
      schema: %{type: "regoper", dimensions: 0}
    },
    %{
      postgres_type: "REGOPERATOR",
      schema: %{type: "regoperator", dimensions: 0}
    },
    %{
      postgres_type: "REGPROC",
      schema: %{type: "regproc", dimensions: 0}
    },
    %{
      postgres_type: "REGPROCEDURE",
      schema: %{type: "regprocedure", dimensions: 0}
    },
    %{
      postgres_type: "REGROLE",
      schema: %{type: "regrole", dimensions: 0}
    },
    %{
      postgres_type: "REGTYPE",
      schema: %{type: "regtype", dimensions: 0}
    },
    %{
      postgres_type: "PG_LSN",
      schema: %{type: "pg_lsn", dimensions: 0}
    },
    %{
      postgres_type: "MOOD",
      schema: %{type: "mood", dimensions: 0}
    },
    %{
      postgres_type: "MOOD[]",
      schema: %{type: "mood", dimensions: 1}
    },
    %{
      postgres_type: "COMPLEX",
      schema: %{type: "complex", dimensions: 0}
    },
    %{
      postgres_type: "COMPLEX[]",
      schema: %{type: "complex", dimensions: 1}
    },
    %{
      postgres_type: "POSINT",
      schema: %{type: "posint", dimensions: 0}
    },
    %{
      postgres_type: "POSINT[]",
      schema: %{type: "posint", dimensions: 1}
    }
  ]

  describe "from_column_info/1" do
    setup context do
      Postgrex.query!(context.db_conn, "CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');", [])

      Postgrex.query!(
        context.db_conn,
        "CREATE TYPE complex AS (r double precision, i double precision);",
        []
      )

      Postgrex.query!(context.db_conn, "CREATE DOMAIN posint AS integer CHECK (VALUE > 0);", [])
      {:ok, context}
    end

    for %{postgres_type: postgres_type, schema: expected_schema} <- @types do
      test "gets the type for #{postgres_type}", %{db_conn: conn} do
        Postgrex.query!(
          conn,
          """
          CREATE TABLE items (
            id INTEGER PRIMARY KEY,
            value #{unquote(postgres_type)})
          """,
          []
        )

        {:ok, column_info} = DirectInspector.load_column_info({"public", "items"}, conn)
        %{"value" => schema} = Schema.from_column_info(column_info)

        assert schema == unquote(Macro.escape(expected_schema))
      end
    end
  end
end
