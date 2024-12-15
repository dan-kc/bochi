FROM rust:1.81

WORKDIR /usr/src/app
COPY Cargo.toml Cargo.lock ./

RUN mkdir src
RUN echo "fn main() {println!(\"TEMP\");}" > src/main.rs
RUN cargo build --release
RUN rm -rf src

COPY src ./src
COPY private_key.pem public_key.pem ./

# touch src/main.rs tells docker that this file has changed.
# Without this it builds the temp
RUN touch src/main.rs && cargo build --release

CMD ["./target/release/habit-market-backend"]
