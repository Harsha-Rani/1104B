# 1104B

## About `WITH (NOLOCK)` and `DELETE` (SQL Server)

If your intent is “use `WITH (NOLOCK)` in a `DELETE` statement to avoid blocking”, it’s important to know:

- **You cannot apply `WITH (NOLOCK)` to the target of a `DELETE`** in SQL Server. `NOLOCK` / `READUNCOMMITTED` are read hints and are not valid on the table you are modifying.
- **You *can* apply `WITH (NOLOCK)` to *source* tables** that are only being read as part of a `DELETE ... FROM ... JOIN ...` pattern (but this can read uncommitted/ghost rows and lead to incorrect deletes).

Example (legal syntax: `NOLOCK` only on the joined/source table):

```sql
DELETE t
FROM dbo.Target AS t
JOIN dbo.Source AS s WITH (NOLOCK)
  ON s.Id = t.SourceId
WHERE s.ShouldDelete = 1;
```

If the real goal is to reduce blocking for batch deletes, consider safer options depending on your constraints:

- **Batching**: delete in small chunks (e.g., `TOP (1000)` in a loop).
- **Indexing**: ensure the `WHERE` predicate is supported by an index to reduce lock footprint.
- **Row-level hints**: e.g. `ROWLOCK` (still locks, but may reduce escalation).
- **Skip locked rows**: `READPAST` can be used on *read side* to skip locked rows (trades completeness for progress).

If you share your actual `DELETE` query/dialect (SQL Server vs MySQL/Postgres/etc.), I can rewrite it in a valid and safer way for that engine.