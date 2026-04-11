# Async Rust & Tokio Cheatsheet

## Runtime setup

```rust
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // multi-threaded runtime (default)
    Ok(())
}

// Or explicit builder:
let rt = tokio::runtime::Builder::new_multi_thread()
    .worker_threads(4)
    .enable_all()
    .build()?;
```

## Spawning

```rust
// Spawn a task (requires Send + 'static)
let handle = tokio::spawn(async move {
    do_work().await
});
let result = handle.await?;

// Blocking work inside async context
let result = tokio::task::spawn_blocking(move || {
    expensive_sync_computation()
}).await?;

// NEVER do blocking I/O in async — use tokio::fs, not std::fs
let contents = tokio::fs::read_to_string("file.txt").await?;
```

## Concurrency primitives

```rust
// Join multiple futures (all must succeed)
let (a, b, c) = tokio::join!(task_a(), task_b(), task_c());

// Try-join (short-circuit on first error)
let (a, b) = tokio::try_join!(task_a(), task_b())?;

// Select (first to complete wins)
tokio::select! {
    val = rx.recv() => handle_message(val),
    _ = tokio::time::sleep(Duration::from_secs(5)) => handle_timeout(),
    _ = shutdown.recv() => return Ok(()),
}
```

## Channels

```rust
// mpsc — multiple producer, single consumer
let (tx, mut rx) = tokio::sync::mpsc::channel::<Message>(100);

// broadcast — multiple consumers
let (tx, _) = tokio::sync::broadcast::channel::<Event>(100);
let mut rx = tx.subscribe();

// oneshot — single value, single consumer
let (tx, rx) = tokio::sync::oneshot::channel::<Response>();

// watch — latest value, multiple consumers
let (tx, rx) = tokio::sync::watch::channel(initial_value);
```

## Mutex / RwLock

```rust
use tokio::sync::{Mutex, RwLock};

// NEVER hold a lock across .await — deadlock risk
let data = Arc::new(Mutex::new(HashMap::new()));

// Good: lock, read/write, drop before await
{
    let mut guard = data.lock().await;
    guard.insert(key, value);
} // guard dropped here
do_something_async().await;

// RwLock for read-heavy workloads
let data = Arc::new(RwLock::new(vec![]));
let read = data.read().await;
```

## Timeouts & intervals

```rust
use tokio::time::{timeout, interval, Duration};

// Timeout a future
match timeout(Duration::from_secs(5), slow_operation()).await {
    Ok(result) => handle(result?),
    Err(_) => handle_timeout(),
}

// Periodic work
let mut ticker = interval(Duration::from_secs(60));
loop {
    ticker.tick().await;
    do_periodic_work().await;
}
```

## Graceful shutdown

```rust
use tokio::signal;

let (shutdown_tx, shutdown_rx) = tokio::sync::broadcast::channel::<()>(1);

tokio::select! {
    _ = server.run() => {},
    _ = signal::ctrl_c() => {
        tracing::info!("shutdown signal received");
        drop(shutdown_tx); // all receivers get RecvError
    }
}
```
