# Borrow Checker Error Resolution Guide

## E0382 — Use of moved value

```rust
// BAD: value moved, then used
let s = String::from("hello");
let s2 = s;        // s moved here
println!("{s}");   // ERROR: use of moved value

// FIX 1: Clone
let s2 = s.clone();

// FIX 2: Borrow instead
let s2 = &s;

// FIX 3: Use Copy types (primitives)
let x: i32 = 5;
let y = x;         // Copy, not move
```

## E0502 — Cannot borrow as mutable because also borrowed as immutable

```rust
// BAD: immutable borrow alive during mutable borrow
let mut v = vec![1, 2, 3];
let first = &v[0];     // immutable borrow
v.push(4);              // ERROR: mutable borrow
println!("{first}");

// FIX: Scope the immutable borrow
let mut v = vec![1, 2, 3];
let first = v[0];       // Copy the value
v.push(4);               // OK
```

## E0597 — Value does not live long enough

```rust
// BAD: reference outlives value
let r;
{
    let x = 5;
    r = &x;    // ERROR: x doesn't live long enough
}

// FIX: Extend the lifetime of the value
let x = 5;
let r = &x;    // OK: x lives as long as r
```

## E0308 — Mismatched types (lifetime-related)

```rust
// BAD: returning reference to local
fn bad() -> &str {
    let s = String::from("hello");
    &s  // ERROR: returns reference to local
}

// FIX: Return owned value
fn good() -> String {
    String::from("hello")
}

// FIX: Accept and return with same lifetime
fn good2(s: &str) -> &str {
    &s[0..5]
}
```

## E0515 — Cannot return value referencing local variable

```rust
// BAD
fn bad() -> &Vec<i32> {
    let v = vec![1, 2, 3];
    &v  // ERROR
}

// FIX: Return owned
fn good() -> Vec<i32> {
    vec![1, 2, 3]
}
```

## Common patterns that avoid borrow issues

```rust
// 1. Entry API (avoids double lookup)
map.entry(key).or_insert_with(|| compute_value());

// 2. Indices instead of references in loops
for i in 0..v.len() {
    if condition(&v[i]) {
        v.remove(i);
        break;
    }
}

// 3. drain() to consume and modify
let removed: Vec<_> = v.drain(2..5).collect();

// 4. Split borrows on structs (each field independently)
let x = &mut self.field_a;
let y = &self.field_b;  // OK: different fields
```
