#[allow(dead_code)]
pub fn create_password_of_length(len: usize) -> String {
    "a".repeat(len)
}

#[macro_export]
macro_rules! generate_email_from_fn {
    ($fn_name:path) => {{
        // $fn_name will be parsed as a path (e.g., `my_module::my_function`)
        // stringify! will convert that path into a string literal.
        let full_name = stringify!($fn_name);
        format!("{}@test.com", full_name)
    }};
    ($fn_name:ident) => {{
        // This variant handles simple identifiers (functions in the current scope)
        let full_name = stringify!($fn_name);
        format!("{}@test.com", full_name)
    }};
}
