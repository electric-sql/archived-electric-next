# Limitations
Don't lose track of things we need to document

- __TRUNCATE__: truncate operations are currently handled by dropping all shapes for the truncated table.

- __Transactions__: we don't put any transaction boundaries into shape logs. However, when a response is a "up-to-date" control message, it is guaranteed that the client has received all operations for the last received transaction.

- __Replication slots__: 
  - electric uses persistent replication slots to ensure no data-loss across server restarts. This means Postgres disk usage keeps growing while Electric does not resume replication. We've observed issues with Hosted Postgres solutions that periodically write metadata/metric to the database. The developer is advised to set `max_slot_wal_keep_size` to set a cap on the WAL size.
  - Changing the LSN of a replication slot might lead to data loss. We do not perform any integrity validation on the replication slot, so the developer should drop the shape data in such cases.
