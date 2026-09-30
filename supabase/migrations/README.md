# Migrations

Schema changes to the Supabase project `eazyeerunsxfyecjpyox` (ap-south-1).

## Baseline

These files are **incremental changes only**. The original schema (15 tables,
the RLS policies, `sync_metadata`, `profiles` and the four pasal tables) was
created directly through the Supabase MCP/SQL tools and has no baseline
migration here. So `supabase db push` against an empty database will not
recreate the schema from scratch — these files only describe what changed
afterwards.

If you ever need to rebuild from zero, dump the live schema first:

    supabase db dump --project-ref eazyeerunsxfyecjpyox --schema public > baseline.sql

and commit that as `00000000000000_baseline.sql`, then keep these files as the
incremental history on top of it.

## Applying

    supabase db push --project-ref eazyeerunsxfyecjpyox

Both files are written to be safely re-runnable (`add column if not exists`,
guarded constraint, `set default`), so applying them to a database that
already has the changes is a no-op.
