import { Client, ClientConfig } from "pg";
import { importPKCS8, SignJWT } from "jose";
import { readFile } from "fs/promises";
import { test as base } from "@playwright/test";

export class DB {
  DBConfig: ClientConfig;

  constructor() {
    this.DBConfig = {
      user: "user",
      host: "db",
      database: "habit_market",
      password: "password",
      port: 5432,
    };
  }

  async executeQuery(query: string) {
    const client = new Client(this.DBConfig);
    try {
      await client.connect();
      const result = await client.query(query);
      return result;
    } catch (error) {
      console.error("Error in connection/executing query:", error);
    } finally {
      await client.end().catch((error: any) => {
        console.error("Error ending client connection:", error);
      });
    }
  }

  async createUser() {
    await this.executeQuery(`
      INSERT INTO users (id, email, password) VALUES
      (1, 'mock@email.com', '$argon2id$v=19$m=19456,t=2,p=1$M3qJL3+ctjCWEvCYFQuTGA$QUQcFKQxhQhIWP6DTBH3+iJtgmWBTMTe1DfcmljlSpw');
  `);
  }

  async deleteAllUsers() {
    await this.executeQuery("DELETE FROM users;");
  }

  // Creates a refresh token for the user id = 1. Defaults to a valid token with expiry date.
  async createRefreshToken(
    expiry: "valid" | "expired" | "no_expiry",
  ): Promise<string> {
    const query =
      expiry === "expired"
        ? `INSERT INTO refresh_tokens (key, name, user_id, expires_at) VALUES ('$argon2i$v=19$m=16,t=2,p=1$R3ZsWXRQck9VYU5MU3I1cQ$4psSvX0O3/Oh/AUjmv4QeQ','testname' , 1, NOW() - INTERVAL '30 days')`
        : expiry === "no_expiry"
          ? `INSERT INTO refresh_tokens (key, name, user_id) VALUES ('$argon2i$v=19$m=16,t=2,p=1$R3ZsWXRQck9VYU5MU3I1cQ$4psSvX0O3/Oh/AUjmv4QeQ', 'testname', 1)`
          : `INSERT INTO refresh_tokens (key, name, user_id, expires_at) VALUES ('$argon2i$v=19$m=16,t=2,p=1$R3ZsWXRQck9VYU5MU3I1cQ$4psSvX0O3/Oh/AUjmv4QeQ', 'testname', 1, NOW() + INTERVAL '30 days')`;
    await this.executeQuery(query);

    return "1$testname$c7ca5bdc_bf07_4c5a_b16f_88c3eb746087";
  }
}

// Creates an access token for the user id = 1
export async function createAccessToken(
  expired: boolean = false,
): Promise<string> {
  const claims = {
    sub: "1", // for user id = 1.
  };

  const pemKey = await readFile("./mock_private_key.pem", { encoding: "utf8" });
  const privateKey = await importPKCS8(pemKey, "EdDSA");

  // Create the JWT
  const jwt = await new SignJWT(claims)
    .setProtectedHeader({ alg: "EdDSA", typ: "JWT" })
    .setExpirationTime(expired ? "-2h" : "2h")
    .sign(privateKey);

  return jwt;
}

export const test = base.extend({
  db: async ({}, use: any) => {
    const database = new DB();
    await use(database);
  },
});

export type RestApiError = {
  code: string;
  message: string;
};

export function createPasswordOfLength(n: number): string {
  let pw = "";
  for (let i = 0; i <= n; i++) {
    pw += "a";
  }
  return pw;
}

export function createStringOfLength(n: number): string {
  return "a".repeat(n);
}

export function createEmailOfLength(n: number): string {
  if (n < 7) {
    throw "Email too short";
  }

  let email = "@h.com";
  for (let i = 0; i < n; i++) {
    email = "a" + email;
  }

  return email;
}

export function findErrorByCode(
  code: string,
  errorMessages: RestApiError[],
): RestApiError {
  const error = errorMessages.find((error) => error.code === code);
  if (error === undefined) {
    throw `Error with code '${code}' does not exist`;
  }

  return error;
}
