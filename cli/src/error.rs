use std::fmt;

#[derive(Debug)]
pub enum Failure {
    Usage(String),
    Runtime(String),
}

pub type Result<T> = std::result::Result<T, Failure>;

impl fmt::Display for Failure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Failure::Usage(message) => write!(f, "{message}"),
            Failure::Runtime(message) => write!(f, "{message}"),
        }
    }
}

pub fn usage<T>(message: impl Into<String>) -> Result<T> {
    Err(Failure::Usage(message.into()))
}

pub fn runtime<T>(message: impl Into<String>) -> Result<T> {
    Err(Failure::Runtime(message.into()))
}
