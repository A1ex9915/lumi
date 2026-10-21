import { Router } from "express";
import { db } from "../db.js";
import { requireAuth } from "../auth.js";
import { generateReply, makeTitle, streamReply } from "../ai.js";

const router = Router();
router.use(requireAuth);

const getConversation = (id) => db.prepare("SELECT * FROM conversations WHERE id = ?").get(id);
const getMessage = (id) => db.prepare("SELECT * FROM messages WHERE id = ?").get(id);

function aiErrorMessage(err) {
  if (err.code === "insufficient_quota" || err.type === "insufficient_quota" || err.code === "credit_balance_exhausted") {
    return "La cuenta de IA no tiene créditos. Recarga saldo en el panel del proveedor.";
  }
  // Gemini responde 400 "API key not valid" en vez de 401
  if (err.status === 401 || (err.status === 400 && /api key/i.test(err.message))) {
    return "La clave de la IA es inválida. Revisa server/.env.";
  }
  if (err.status === 429) {
    return "Se alcanzó el límite de uso de la IA (en el plan gratuito de Gemini hay un máximo por minuto y por día). Espera un momento e intenta de nuevo.";
  }
  if (err.status === 403) {
    return "La clave de la IA no tiene permiso: activa la API en el panel del proveedor (en Gemini: \"Gemini API\" en Google Cloud).";
  }
  if (err.status === 404) return "El modelo de IA configurado no existe. Revisa el nombre del modelo en server/.env.";
  return "El servicio de IA no respondió. Intenta de nuevo.";
}

// Si falla la IA se quita el mensaje del usuario para no dejar dos turnos 'user' seguidos en el historial
const deleteMessage = (id) => db.prepare("DELETE FROM messages WHERE id = ?").run(id);

/** Guarda el mensaje del usuario y devuelve el historial completo para la IA. */
function insertUserMessage(conv, content) {
  const userMsgId = db
    .prepare("INSERT INTO messages (conversation_id, role, content) VALUES (?, 'user', ?)")
    .run(conv.id, content).lastInsertRowid;
  const history = db
    .prepare("SELECT role, content FROM messages WHERE conversation_id = ? ORDER BY id")
    .all(conv.id);
  return { userMsgId, history };
}

/** Guarda la respuesta, pone título en el primer mensaje y actualiza la fecha. Devuelve el mensaje. */
function saveAssistantMessage(conv, userContent, reply, history) {
  const id = db
    .prepare("INSERT INTO messages (conversation_id, role, content) VALUES (?, 'assistant', ?)")
    .run(conv.id, reply).lastInsertRowid;
  if (history.length === 1) {
    db.prepare("UPDATE conversations SET title = ? WHERE id = ?").run(makeTitle(userContent), conv.id);
  }
  db.prepare("UPDATE conversations SET updated_at = datetime('now') WHERE id = ?").run(conv.id);
  return getMessage(id);
}

function ownConversation(req, res) {
  const conv = db
    .prepare("SELECT * FROM conversations WHERE id = ? AND user_id = ?")
    .get(req.params.id, req.user.id);
  if (!conv) res.status(404).json({ error: "Conversación no encontrada" });
  return conv;
}

// Listar conversaciones del usuario
router.get("/", (req, res) => {
  const rows = db
    .prepare("SELECT * FROM conversations WHERE user_id = ? ORDER BY updated_at DESC, id DESC")
    .all(req.user.id);
  res.json(rows);
});

// Crear conversación vacía
router.post("/", (req, res) => {
  const info = db.prepare("INSERT INTO conversations (user_id) VALUES (?)").run(req.user.id);
  res.status(201).json(getConversation(info.lastInsertRowid));
});

// Borrar TODAS las conversaciones del usuario
router.delete("/", (req, res) => {
  db.prepare("DELETE FROM conversations WHERE user_id = ?").run(req.user.id);
  res.status(204).end();
});

// Mensajes de una conversación
router.get("/:id/messages", (req, res) => {
  const conv = ownConversation(req, res);
  if (!conv) return;
  res.json(db.prepare("SELECT * FROM messages WHERE conversation_id = ? ORDER BY id").all(conv.id));
});

// Enviar mensaje y obtener respuesta de la IA
router.post("/:id/messages", async (req, res) => {
  const conv = ownConversation(req, res);
  if (!conv) return;
  const content = (req.body?.content || "").trim();
  if (!content) return res.status(400).json({ error: "Mensaje vacío" });

  const { userMsgId, history } = insertUserMessage(conv, content);

  let reply;
  try {
    reply = await generateReply(history);
  } catch (err) {
    console.error(`Error de IA (${err.status ?? "sin status"}): ${err.message}`);
    deleteMessage(userMsgId);
    return res.status(502).json({ error: aiErrorMessage(err) });
  }

  res.status(201).json({
    user: getMessage(userMsgId),
    assistant: saveAssistantMessage(conv, content, reply, history),
    conversation: getConversation(conv.id),
  });
});

// Enviar mensaje y recibir la respuesta de la IA en streaming (Server-Sent Events).
// Eventos: {type:"status",status:"thinking"} · {type:"delta",text} · {type:"done",assistant,conversation} · {type:"error",error}
router.post("/:id/messages/stream", async (req, res) => {
  const conv = ownConversation(req, res);
  if (!conv) return;
  const content = (req.body?.content || "").trim();
  if (!content) return res.status(400).json({ error: "Mensaje vacío" });

  const { userMsgId, history } = insertUserMessage(conv, content);

  res.writeHead(200, {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  });
  const send = (data) => res.write(`data: ${JSON.stringify(data)}\n\n`);
  // Comentario SSE periódico para que la conexión no se corte mientras el modelo piensa
  const heartbeat = setInterval(() => res.write(": ping\n\n"), 15000);

  // Si la app cierra la conexión (botón "detener"), se cancela la petición a la IA
  const abort = new AbortController();
  res.on("close", () => {
    if (!res.writableEnded) abort.abort();
  });

  let partial = "";
  try {
    const reply = await streamReply(history, {
      signal: abort.signal,
      onText: (text) => {
        partial += text;
        send({ type: "delta", text });
      },
      onThinking: () => send({ type: "status", status: "thinking" }),
    });
    send({
      type: "done",
      assistant: saveAssistantMessage(conv, content, reply, history),
      conversation: getConversation(conv.id),
    });
  } catch (err) {
    if (abort.signal.aborted) {
      // Detenido por el usuario: se guarda lo que alcanzó a escribir (la app ya lo muestra)
      if (partial.trim()) saveAssistantMessage(conv, content, partial.trim(), history);
      else deleteMessage(userMsgId);
    } else {
      console.error(`Error de IA (${err.status ?? "sin status"}): ${err.message}`);
      deleteMessage(userMsgId);
      send({ type: "error", error: aiErrorMessage(err) });
    }
  } finally {
    clearInterval(heartbeat);
    res.end();
  }
});

// Borrar una conversación
router.delete("/:id", (req, res) => {
  const conv = ownConversation(req, res);
  if (!conv) return;
  db.prepare("DELETE FROM conversations WHERE id = ?").run(conv.id);
  res.status(204).end();
});

export default router;
