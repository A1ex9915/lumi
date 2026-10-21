import { Router } from "express";
import bcrypt from "bcryptjs";
import { db } from "../db.js";
import { signToken, publicUser, requireAuth } from "../auth.js";
import { verifyFirebaseToken } from "../firebase.js";

const router = Router();

router.post("/login", async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ error: "Usuario y contraseña requeridos" });
  const user = db.prepare("SELECT * FROM users WHERE username = ?").get(username.trim());
  if (user && !user.password_hash) {
    return res.status(401).json({ error: "Esta cuenta inicia sesión con Google" });
  }
  if (!user || !(await bcrypt.compare(password, user.password_hash))) {
    return res.status(401).json({ error: "Credenciales incorrectas" });
  }
  res.json({ token: signToken(user), user: publicUser(user) });
});

router.post("/register", (req, res) => {
  const { username, name, password } = req.body || {};
  if (!username?.trim() || !name?.trim() || !password) {
    return res.status(400).json({ error: "Nombre, usuario y contraseña requeridos" });
  }
  if (password.length < 6) return res.status(400).json({ error: "La contraseña debe tener al menos 6 caracteres" });
  if (db.prepare("SELECT id FROM users WHERE username = ?").get(username.trim())) {
    return res.status(409).json({ error: "El usuario ya existe" });
  }
  const info = db
    .prepare("INSERT INTO users (username, name, password_hash) VALUES (?, ?, ?)")
    .run(username.trim(), name.trim(), bcrypt.hashSync(password, 10));
  const user = db.prepare("SELECT * FROM users WHERE id = ?").get(info.lastInsertRowid);
  res.status(201).json({ token: signToken(user), user: publicUser(user) });
});

// Inicio de sesión con Google: la app manda el ID token de Firebase y recibe nuestro JWT.
// La primera vez se crea el usuario automáticamente.
router.post("/firebase", async (req, res) => {
  const { idToken } = req.body || {};
  if (!idToken) return res.status(400).json({ error: "Token de Firebase requerido" });

  let decoded;
  try {
    decoded = await verifyFirebaseToken(idToken);
  } catch (err) {
    console.error(`Token de Firebase rechazado: ${err.message}`);
    return res.status(401).json({ error: "No se pudo verificar la cuenta de Google" });
  }

  let user = db.prepare("SELECT * FROM users WHERE firebase_uid = ?").get(decoded.uid);
  if (!user) {
    const email = decoded.email || null;
    const base = (email?.split("@")[0] || "usuario").toLowerCase().replace(/[^a-z0-9._-]/g, "") || "usuario";
    let username = base;
    for (let n = 2; db.prepare("SELECT id FROM users WHERE username = ?").get(username); n++) username = `${base}${n}`;

    const info = db
      .prepare("INSERT INTO users (username, name, password_hash, email, firebase_uid) VALUES (?, ?, '', ?, ?)")
      .run(username, decoded.name || base, email, decoded.uid);
    user = db.prepare("SELECT * FROM users WHERE id = ?").get(info.lastInsertRowid);
  }
  res.json({ token: signToken(user), user: publicUser(user) });
});

router.get("/me", requireAuth, (req, res) => res.json(publicUser(req.user)));

export default router;
