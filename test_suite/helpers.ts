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
      await client.end().catch((error) => {
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

  // Creates a refresh token for the user id = 1
  async createRefreshToken(expired: boolean = false): Promise<string> {
    const query = expired
      ? `INSERT INTO refresh_tokens (id, user_id, expires_at) VALUES ('c7ca5bdc_bf07_4c5a_b16f_88c3eb746087', 1, NOW() - INTERVAL '30 days')`
      : `INSERT INTO refresh_tokens (id, user_id) VALUES ('c7ca5bdc_bf07_4c5a_b16f_88c3eb746087', 1)`;
    await this.executeQuery(query);

    return "c7ca5bdc_bf07_4c5a_b16f_88c3eb746087";
  }
}

// Creates an access token for the user id = 1
export async function createAccessToken(
  expired: boolean = false,
): Promise<string> {
  const claims = {
    sub: "1", // for user id = 1.
  };

  const pemKey = await readFile("./private_key.pem", { encoding: "utf8" });
  const privateKey = await importPKCS8(pemKey, "EdDSA");

  // Create the JWT
  const jwt = await new SignJWT(claims)
    .setProtectedHeader({ alg: "EdDSA", typ: "JWT" })
    .setExpirationTime(expired ? "-2h" : "2h")
    .sign(privateKey);

  return jwt;
}

export const test = base.extend({
  db: async ({}, use) => {
    const database = new DB();
    await use(database);
  },
});
