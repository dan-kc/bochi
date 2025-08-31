FROM rust:1.89

WORKDIR /usr/src/app
COPY Cargo.toml Cargo.lock ./

RUN mkdir src
RUN echo "fn main() {println!(\"TEMP\");}" > src/main.rs
RUN cargo build --release
RUN rm -rf src

COPY src ./src
COPY mock_private_key.pem mock_public_key.pem ./

# touch src/main.rs tells docker that this file has changed.
# Without this it builds the temp
RUN touch src/main.rs && cargo build --release

CMD ["./target/release/habit-market-backend"]
