import "dotenv/config";
import express from "express";
import cors from "cors";
import { seedAdmin } from "./db.js";
import authRoutes from "./routes/auth.js";
import userRoutes from "./routes/users.js";
import conversationRoutes from "./routes/conversations.js";

seedAdmin();

const app = express();
app.use(cors());
app.use(express.json({ limit: "1mb" }));

app.get("/api/health", (req, res) => res.json({ ok: true }));
app.use("/api/auth", authRoutes);
app.use("/api/users", userRoutes);
app.use("/api/conversations", conversationRoutes);

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: "Error interno del servidor" });
});

const port = process.env.PORT || 8000;
// Sin host explícito Node escucha en IPv4 e IPv6 a la vez; con "0.0.0.0" (solo IPv4)
// las conexiones a "localhost" en Windows tardan ~2 s porque primero prueban ::1.
app.listen(port, () => console.log(`Servidor en http://localhost:${port}`));
