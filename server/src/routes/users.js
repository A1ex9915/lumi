import { Router } from "express";
import bcrypt from "bcryptjs";
import { db } from "../db.js";
import { publicUser, requireAuth, requireAdmin } from "../auth.js";

const router = Router();
router.use(requireAuth, requireAdmin);

const getUser = (id) => db.prepare("SELECT * FROM users WHERE id = ?").get(id);
const adminCount = () => db.prepare("SELECT COUNT(*) AS n FROM users WHERE role = 'admin'").get().n;
const usernameTaken = (username) => db.prepare("SELECT id FROM users WHERE username = ?").get(username);

// Listar
router.get("/", (req, res) => {
  res.json(db.prepare("SELECT * FROM users ORDER BY id").all().map(publicUser));
});

// Crear
router.post("/", (req, res) => {
  const { username, name, password, role = "user" } = req.body || {};
  if (!username?.trim() || !name?.trim() || !password) {
    return res.status(400).json({ error: "Nombre, usuario y contraseña requeridos" });
  }
  if (!["user", "admin"].includes(role)) return res.status(400).json({ error: "Rol inválido" });
  if (password.length < 6) return res.status(400).json({ error: "La contraseña debe tener al menos 6 caracteres" });
  if (usernameTaken(username.trim())) return res.status(409).json({ error: "El usuario ya existe" });

  const info = db
    .prepare("INSERT INTO users (username, name, password_hash, role) VALUES (?, ?, ?, ?)")
    .run(username.trim(), name.trim(), bcrypt.hashSync(password, 10), role);
  res.status(201).json(publicUser(getUser(info.lastInsertRowid)));
});

// Leer uno
router.get("/:id", (req, res) => {
  const user = getUser(req.params.id);
  if (!user) return res.status(404).json({ error: "Usuario no encontrado" });
  res.json(publicUser(user));
});

// Actualizar (la contraseña solo cambia si se envía)
router.put("/:id", (req, res) => {
  const user = getUser(req.params.id);
  if (!user) return res.status(404).json({ error: "Usuario no encontrado" });
  const { username, name, password, role } = req.body || {};

  if (role && !["user", "admin"].includes(role)) return res.status(400).json({ error: "Rol inválido" });
  if (user.role === "admin" && role === "user" && adminCount() <= 1) {
    return res.status(400).json({ error: "Debe existir al menos un administrador" });
  }
  if (username?.trim() && username.trim().toLowerCase() !== user.username.toLowerCase() && usernameTaken(username.trim())) {
    return res.status(409).json({ error: "El usuario ya existe" });
  }
  if (password && password.length < 6) {
    return res.status(400).json({ error: "La contraseña debe tener al menos 6 caracteres" });
  }

  db.prepare("UPDATE users SET username = ?, name = ?, role = ?, password_hash = ? WHERE id = ?").run(
    username?.trim() || user.username,
    name?.trim() || user.name,
    role || user.role,
    password ? bcrypt.hashSync(password, 10) : user.password_hash,
    user.id
  );
  res.json(publicUser(getUser(user.id)));
});

// Eliminar
router.delete("/:id", (req, res) => {
  const user = getUser(req.params.id);
  if (!user) return res.status(404).json({ error: "Usuario no encontrado" });
  if (user.id === req.user.id) return res.status(400).json({ error: "No puedes eliminar tu propia cuenta" });
  if (user.role === "admin" && adminCount() <= 1) {
    return res.status(400).json({ error: "Debe existir al menos un administrador" });
  }
  db.prepare("DELETE FROM users WHERE id = ?").run(user.id);
  res.status(204).end();
});

export default router;
