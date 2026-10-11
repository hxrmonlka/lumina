pub enum Failure {
    Usage(String),
    Runtime(String),
}

pub type Result<T> = std::result::Result<T, Failure>;

pub fn usage<T>(message: impl Into<String>) -> Result<T> {
    Err(Failure::Usage(message.into()))
}

pub fn runtime<T>(message: impl Into<String>) -> Result<T> {
    Err(Failure::Runtime(message.into()))
}
