## Contents

- What the SDK catches by itself
- BullMQ and other queue workers
- pg-boss
- Scheduled jobs
- WebSocket and Socket.IO
- Streams and pipelines
- Database clients
- Outbound HTTP
- Child processes
- Where to report, and how often

## What the SDK catches by itself

`configure()` installs additive `process.on("uncaughtException")` and
`process.on("unhandledRejection")` listeners. Each records the error with
`_unhandled` set, then preserves Node's default behaviour: if the SDK is the only listener
the process still exits exactly as it would have, and if the app has its own listener that
listener still decides. Any failure inside the SDK's handler is swallowed so it cannot
compound the original crash, and the same error escalating from rejection to exception is
recorded once.

Two consequences worth stating plainly: the process still dies, so a supervisor still has to
restart it; and a hard kill (`SIGKILL`, OOM) loses whatever was buffered. Everything caught
in your own code is invisible until you report it.

## BullMQ and other queue workers

A worker that throws marks the job failed and moves on — nothing reaches the process
handlers. Instrument the job body, not the loop that drains it:

```ts
const worker = new Worker(
  "emails",
  async (job) => {
    const pulse = Pulse.withUser(job.data.userId);
    const op = pulse.startOperation("send-email", { template: job.data.template });
    try {
      await send(job.data);
      op.complete();
    } catch (err) {
      pulse.error(err instanceof Error ? err : new Error(String(err)), "email_send_failed", {
        job_id: job.id ?? "",
        attempt: String(job.attemptsMade + 1),
        template: job.data.template,
      });
      op.fail(err instanceof Error ? err.message : String(err));
      throw err;      // let BullMQ retry or fail the job
    }
  },
  { connection },
);

worker.on("error", (err) => Pulse.error(err, "queue_worker_error", { queue: "emails" }));
```

Report on the **final** attempt if retries are noisy — `job.attemptsMade + 1 >= job.opts.attempts`
— or keep every attempt and read the `attempt` attribute. Do not do both. The `worker.on("error")`
handler is for the worker itself (a lost Redis connection), which is a different failure from
a job failing.

## pg-boss

```ts
await boss.work("reports", async ([job]) => {
  const pulse = Pulse.withUser(job.data.userId);
  try {
    await buildReport(job.data);
    pulse.info("report_built", { report_id: job.data.reportId });
  } catch (err) {
    pulse.error(err instanceof Error ? err : new Error(String(err)), "report_build_failed", {
      job_id: job.id,
    });
    throw err;
  }
});

boss.on("error", (err) => Pulse.error(err, "queue_error"));
```

## Scheduled jobs

A `node-cron` callback that throws is swallowed by the scheduler, and an async one loses its
rejection entirely. Wrap the body and emit one summary event per run:

```ts
cron.schedule("0 3 * * *", async () => {
  const startedAt = Date.now();
  let processed = 0;
  let failed = 0;

  try {
    for (const row of await pending()) {
      try {
        await process(row);
        processed++;
      } catch {
        failed++;                    // counted, not logged per row
      }
    }
    Pulse.info("nightly_sync_completed", {
      processed: String(processed),
      failed: String(failed),
      duration_ms: String(Date.now() - startedAt),
    });
  } catch (err) {
    Pulse.error(err instanceof Error ? err : new Error(String(err)), "nightly_sync_failed", {
      processed: String(processed),
      duration_ms: String(Date.now() - startedAt),
    });
  }
});
```

One event per run, not one per row — 10,000 rows is 10,000 events otherwise, and the
per-attempt detail is what attributes are for. If individual failures matter, sample a few
into an attribute (`failure_samples`) rather than logging each.

## WebSocket and Socket.IO

Three places fail independently: the connection, each message handler, and the socket
itself.

```ts
io.on("connection", (socket) => {
  const pulse = Pulse.withUser(socket.data.userId);
  const connectedAt = Date.now();
  let frames = 0;

  socket.on("error", (err) => pulse.error(err, "socket_error", { socket_id: socket.id }));

  socket.on("message", async (payload) => {
    frames++;
    try {
      await handle(payload);
    } catch (err) {
      pulse.error(err instanceof Error ? err : new Error(String(err)), "socket_message_failed", {
        socket_id: socket.id,
      });
    }
  });

  socket.on("disconnect", (reason) => {
    pulse.info("socket_closed", {
      reason,
      frames: String(frames),
      duration_ms: String(Date.now() - connectedAt),
    });
  });
});
```

Never log per frame — count them and report the connection outcome. With the `ws` package
the same three hooks are `ws.on("error")`, the message handler, and `ws.on("close")`, plus
`wss.on("error")` for the server.

## Streams and pipelines

A stream `error` event is not an exception; unhandled, it becomes an uncaught exception at
some unrelated point. Use `pipeline`, which surfaces it as a rejection:

```ts
try {
  await pipeline(createReadStream(inputPath), parser, createWriteStream(outputPath));
  Pulse.info("file_processed", { bytes: String(statSync(outputPath).size) });
} catch (err) {
  Pulse.error(err instanceof Error ? err : new Error(String(err)), "file_processing_failed", {
    input: basename(inputPath),
  });
}
```

Node errors carry `code`, `errno`, `syscall` and `path`, all of which the SDK extracts into
`_error_*` attributes when you pass the error itself — so `ENOENT` and `EACCES` stay
separate issues.

## Database clients

A pool emits `error` for a connection that dies while idle. That is a different event from a
query failing, and it is the one that goes unreported:

```ts
pool.on("error", (err) => Pulse.error(err, "db_pool_error"));
```

Do not instrument every query. Instrument the categories that matter with a lifecycle
metric, or wrap the repository function:

```ts
const op = pulse.startOperation("db-query", { query: "orders_by_user" });
try {
  const rows = await pool.query(sql, params);
  op.complete({ rows: String(rows.rowCount ?? 0) });
  return rows;
} catch (err) {
  pulse.error(err instanceof Error ? err : new Error(String(err)), "db_query_failed", {
    query: "orders_by_user",
  });
  op.fail(err instanceof Error ? err.message : String(err));
  throw err;
}
```

The `query` attribute is a stable name, never the SQL text — SQL with interpolated values
would fragment the issue and can leak data.

## Outbound HTTP

`fetch` rejects only on a transport failure; a `500` from an upstream resolves. Check the
status, and use the reserved `_http_*` keys so the issue tracker discriminates by method and
templated path:

```ts
async function callUpstream(url: string, init?: RequestInit) {
  const startedAt = Date.now();
  try {
    const res = await fetch(url, init);
    if (!res.ok) {
      Pulse.warn("upstream_request_failed", {
        _http_url: url,
        _http_method: init?.method ?? "GET",
        _http_status: String(res.status),
        _http_duration_ms: String(Date.now() - startedAt),
      });
    }
    return res;
  } catch (err) {
    Pulse.error(err instanceof Error ? err : new Error(String(err)), "upstream_unreachable", {
      _http_url: url,
      _http_method: init?.method ?? "GET",
      _http_status: "0",
    });
    throw err;
  }
}
```

`warn` for a bad status the caller can handle, `error` for one that ends the request — only
`error` events become issues, so reserve them for what you would want to be alerted about.

## Child processes

```ts
const child = spawn(command, args);
child.on("error", (err) => Pulse.error(err, "child_spawn_failed", { command }));
child.on("exit", (code, signal) => {
  if (code !== 0) {
    Pulse.error("child_exited_nonzero", {
      command,
      exit_code: String(code ?? -1),
      signal: signal ?? "",
    });
  }
});
```

`error` fires when the process could not start; a non-zero exit arrives on `exit` and is a
separate failure.

## Where to report, and how often

Report once, at the layer that handles the failure. A repository that catches, logs and
rethrows, plus a service that catches, logs and rethrows, plus an error handler that logs,
is three events for one fault — the hourly issue scan aliases them onto one issue only when
they fall in the same session within five seconds, which is not something to rely on.

Pick the layer that knows the most: usually the request or job boundary, where the user,
the route and the input identifiers are all in scope. Lower layers rethrow with `cause` set
(`throw new Error("charge_failed", { cause: err })`) — the SDK walks five levels of cause,
so nothing is lost by reporting only at the top.
