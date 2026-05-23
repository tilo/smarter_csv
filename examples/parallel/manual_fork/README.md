# Manual fork — what `parallel` does under the hood

`Process.fork` + `Process.wait` is the foundation everything else builds on. Showing the bare-metal version makes clear what the `parallel` gem (and Sidekiq's per-process workers, and `Parallel.each`'s `in_processes:` mode) actually does.

Not recommended for production — the `parallel` gem and Sidekiq handle edge cases (signal propagation, worker pool management, retry, supervision) that you'd have to write yourself. This example is **educational**.

## When to use this

- **You're curious how `Parallel.each` works.**
- **You're prototyping** without wanting to add a gem dependency.
- **You're in a constrained environment** that can't install gems.
- **Teaching** — showing the fork-and-coordinate pattern.

For everything else, use `../parallel_gem/` or `../sidekiq/`.

## The pattern

```ruby
slices = SmarterCSV.slice(path, slice_size: 50_000)

child_pids = slices.map do |slice|
  Process.fork do
    SmarterCSV.process_slice(slice) do |batch|
      # Worker work — DB insert, write to disk, etc.
    end
    exit!(0)
  end
end

child_pids.each { |pid| Process.wait(pid) }
```

That's literally it: fork once per slice, wait for all children, done.

The `exit!` instead of regular `exit` skips at_exit handlers — important in forked children to avoid running the parent's cleanup logic prematurely (closing DB connections the parent still needs, etc.).

## What about IPC?

The bare fork pattern has no built-in way to return data from child → parent. Options, in roughly increasing complexity:

1. **Per-child tempfile** — child writes its output to a known file path, parent reads after wait. The example uses this.
2. **Per-child DB row** — child writes to a shared store (DB / Redis) keyed by something the parent knows. Same as the Sidekiq patterns.
3. **Pipes** — parent creates pipes before fork; child writes, parent reads. `IO.pipe`; more code; faster than tempfiles for small payloads.
4. **Marshal-via-stdout** — child does `Marshal.dump(result, $stdout)`; parent reads. Brittle (any extra puts ruins it).
5. **Shared memory** — `MMap` / `Posix::Mmap`. Real systems engineering.

`Parallel.map` uses option 3 (pipes + Marshal); that's its main value-add over bare fork. If you don't need parent-side aggregation, bare fork is fine.

## What the demo prints

12-row CSV, 3 slices, 3 child processes forked. Each child writes its output to a unique tempfile (named with its parent pid + child index to avoid collisions). Parent waits for each, then prints the output from each tempfile. You see per-child PIDs proving real process-level parallelism.

## Caveats

- **Rails / ActiveRecord:** forked children inherit the parent's open DB connections — the first child to use one corrupts it. Always `ActiveRecord::Base.connection_handler.clear_all_connections!` at the top of each child.
- **Open file handles** are inherited — the child can write to files the parent opened. Sometimes useful, sometimes a footgun.
- **`exit!` vs `exit`:** `exit!` skips at_exit handlers (good in children). `exit` runs them (and would re-close DB connections from the parent's perspective, breaking the parent).
- **`Process.wait` blocks** until that specific child exits. To wait for any child: `Process.waitpid(-1)`. To wait without blocking: `Process.waitpid(pid, Process::WNOHANG)`.
- **Signal handling.** If you send SIGTERM to the parent, children don't automatically receive it. You'd need to install a trap that propagates. `parallel` and Sidekiq handle this; bare fork doesn't.
- **Out-of-memory.** Each child is a full Ruby process — RSS roughly equal to the parent at fork time, growing as the child works. Forking 100 children of a 500MB Ruby process is 50GB of RSS (modulo copy-on-write savings).

## Production alternatives

- **`Parallel.each(in_processes:)`** — handles the pid bookkeeping, error propagation, signal forwarding. See `../parallel_gem/`.
- **Sidekiq** — handles all of the above plus durability, retry, observability. See `../sidekiq/`.
- **`Process.fork` + a small supervisor library** — `daemons`, `serengeti`, etc. Picks up the supervision concerns without going full job queue.

## See also

- `../parallel_gem/` — what you should use instead in real code.
- `../sidekiq/` — production-grade alternative with persistence.
