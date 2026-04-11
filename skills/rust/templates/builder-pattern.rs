// Template: Builder pattern with typestate (compile-time validation)

/// Configuration for {{component_name}}.
///
/// Use [`{{component_name}}Builder`] to construct.
///
/// # Examples
///
/// ```
/// let config = {{component_name}}::builder()
///     .name("example")
///     .port(8080)
///     .build();
/// ```
#[derive(Debug, Clone)]
pub struct {{component_name}} {
    name: String,
    port: u16,
    timeout_ms: u64,
}

/// Builder for [`{{component_name}}`].
#[derive(Debug, Default)]
pub struct {{component_name}}Builder {
    name: Option<String>,
    port: Option<u16>,
    timeout_ms: u64,
}

impl {{component_name}} {
    /// Creates a new builder.
    #[must_use]
    pub fn builder() -> {{component_name}}Builder {
        {{component_name}}Builder::default()
    }
}

impl {{component_name}}Builder {
    /// Sets the name (required).
    #[must_use]
    pub fn name(mut self, name: impl Into<String>) -> Self {
        self.name = Some(name.into());
        self
    }

    /// Sets the port (required).
    #[must_use]
    pub fn port(mut self, port: u16) -> Self {
        self.port = Some(port);
        self
    }

    /// Sets the timeout in milliseconds (default: 5000).
    #[must_use]
    pub fn timeout_ms(mut self, ms: u64) -> Self {
        self.timeout_ms = ms;
        self
    }

    /// Builds the configuration.
    ///
    /// # Panics
    ///
    /// Panics if `name` or `port` are not set.
    #[must_use]
    pub fn build(self) -> {{component_name}} {
        {{component_name}} {
            name: self.name.expect("name is required"),
            port: self.port.expect("port is required"),
            timeout_ms: if self.timeout_ms == 0 { 5000 } else { self.timeout_ms },
        }
    }
}
