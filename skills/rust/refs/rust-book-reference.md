# The Rust Programming Language — Quick Reference

Base URL: `https://doc.rust-lang.org/book/`
Offline: `rustup doc --book`

## Core Language

| Topic | Chapter | URL |
|-------|---------|-----|
| Variables & Mutability | 3.1 | ch03-01-variables-and-mutability.html |
| Data Types | 3.2 | ch03-02-data-types.html |
| Functions | 3.3 | ch03-03-how-functions-work.html |
| Control Flow | 3.5 | ch03-05-control-flow.html |

## Ownership & Borrowing

| Topic | Chapter | URL |
|-------|---------|-----|
| What is Ownership? | 4.1 | ch04-01-what-is-ownership.html |
| References & Borrowing | 4.2 | ch04-02-references-and-borrowing.html |
| The Slice Type | 4.3 | ch04-03-slices.html |

## Structs, Enums, Pattern Matching

| Topic | Chapter | URL |
|-------|---------|-----|
| Defining Structs | 5.1 | ch05-01-defining-structs.html |
| Methods | 5.3 | ch05-03-method-syntax.html |
| Defining Enums | 6.1 | ch06-01-defining-an-enum.html |
| match | 6.2 | ch06-02-match.html |
| if let / let else | 6.3 | ch06-03-if-let.html |
| Pattern Syntax | 19.3 | ch19-03-pattern-syntax.html |

## Modules & Crates

| Topic | Chapter | URL |
|-------|---------|-----|
| Packages & Crates | 7.1 | ch07-01-packages-and-crates.html |
| Modules & Privacy | 7.2 | ch07-02-defining-modules-to-control-scope-and-privacy.html |
| use Keyword | 7.4 | ch07-04-bringing-paths-into-scope-with-the-use-keyword.html |
| Cargo Workspaces | 14.3 | ch14-03-cargo-workspaces.html |

## Error Handling

| Topic | Chapter | URL |
|-------|---------|-----|
| panic! | 9.1 | ch09-01-unrecoverable-errors-with-panic.html |
| Result | 9.2 | ch09-02-recoverable-errors-with-result.html |
| When to panic | 9.3 | ch09-03-to-panic-or-not-to-panic.html |

## Generics, Traits, Lifetimes

| Topic | Chapter | URL |
|-------|---------|-----|
| Generic Data Types | 10.1 | ch10-01-syntax.html |
| Traits | 10.2 | ch10-02-traits.html |
| Lifetimes | 10.3 | ch10-03-lifetime-syntax.html |
| Advanced Traits | 20.2 | ch20-02-advanced-traits.html |

## Collections

| Topic | Chapter | URL |
|-------|---------|-----|
| Vectors | 8.1 | ch08-01-vectors.html |
| Strings | 8.2 | ch08-02-strings.html |
| Hash Maps | 8.3 | ch08-03-hash-maps.html |

## Testing

| Topic | Chapter | URL |
|-------|---------|-----|
| Writing Tests | 11.1 | ch11-01-writing-tests.html |
| Running Tests | 11.2 | ch11-02-running-tests.html |
| Test Organization | 11.3 | ch11-03-test-organization.html |
| TDD Example | 12.4 | ch12-04-testing-the-librarys-functionality.html |

## Functional Features

| Topic | Chapter | URL |
|-------|---------|-----|
| Closures | 13.1 | ch13-01-closures.html |
| Iterators | 13.2 | ch13-02-iterators.html |
| Performance | 13.4 | ch13-04-performance.html |

## Smart Pointers

| Topic | Chapter | URL |
|-------|---------|-----|
| Box\<T\> | 15.1 | ch15-01-box.html |
| Deref | 15.2 | ch15-02-deref.html |
| Drop | 15.3 | ch15-03-drop.html |
| Rc\<T\> | 15.4 | ch15-04-rc.html |
| RefCell\<T\> | 15.5 | ch15-05-interior-mutability.html |

## Concurrency

| Topic | Chapter | URL |
|-------|---------|-----|
| Threads | 16.1 | ch16-01-threads.html |
| Message Passing | 16.2 | ch16-02-message-passing.html |
| Shared State | 16.3 | ch16-03-shared-state.html |
| Send & Sync | 16.4 | ch16-04-extensible-concurrency-sync-and-send.html |

## Async / Await

| Topic | Chapter | URL |
|-------|---------|-----|
| Futures & Syntax | 17.1 | ch17-01-futures-and-syntax.html |
| Concurrency with Async | 17.2 | ch17-02-concurrency-with-async.html |
| Streams | 17.4 | ch17-04-streams.html |
| Async Traits | 17.5 | ch17-05-traits-for-async.html |
| Futures vs Tasks vs Threads | 17.6 | ch17-06-futures-tasks-threads.html |

## Advanced

| Topic | Chapter | URL |
|-------|---------|-----|
| Unsafe Rust | 20.1 | ch20-01-unsafe-rust.html |
| Advanced Types | 20.3 | ch20-03-advanced-types.html |
| Advanced Functions & Closures | 20.4 | ch20-04-advanced-functions-and-closures.html |
| Macros | 20.5 | ch20-05-macros.html |

## Appendices

| Topic | URL |
|-------|-----|
| Keywords | appendix-01-keywords.html |
| Operators & Symbols | appendix-02-operators.html |
| Derivable Traits | appendix-03-derivable-traits.html |
| Dev Tools | appendix-04-useful-development-tools.html |

## Other Key References

- Rust API Guidelines: https://rust-lang.github.io/api-guidelines/
- Rust Performance Book: https://nnethercote.github.io/perf-book/
- Rust by Example: https://doc.rust-lang.org/rust-by-example/
- Rustonomicon (unsafe): https://doc.rust-lang.org/nomicon/
- Async Book: https://rust-lang.github.io/async-book/
- Clippy Lint List: https://rust-lang.github.io/rust-clippy/master/
- Error Handling (thiserror/anyhow): https://docs.rs/thiserror / https://docs.rs/anyhow
