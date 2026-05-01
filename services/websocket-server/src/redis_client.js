const { createClient } = require("redis");

const client = createClient({
  socket: {
    host: process.env.REDIS_HOST || "redis-master.redis",
    port: parseInt(process.env.REDIS_PORT || "6379"),
    reconnectStrategy: (retries) => Math.min(retries * 500, 5000),
  },
});

client.on("error",   (err) => console.error("Redis error:", err));
client.on("connect", ()    => console.log("Connected to Redis"));

client.connect();

module.exports = client;