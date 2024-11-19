const { Client } = require("pg");

class DB {
  constructor() {
    this.DBConfig = {
      user: "user",
      host: "db",
      database: "habit_market",
      password: "password",
      port: 5432,
    };
  }

  async executeQuery(query) {
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
}

module.exports = { DB };
