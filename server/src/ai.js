import OpenAI from "openai";
import Anthropic from "@anthropic-ai/sdk";
import { GoogleGenAI } from "@google/genai";

// Proveedor de IA: "openai" (ChatGPT), "anthropic" (Claude) o "gemini" (Google). Se elige en .env con AI_PROVIDER.
const PROVIDER = (process.env.AI_PROVIDER || "openai").toLowerCase();
const OPENAI_MODEL = process.env.OPENAI_MODEL || "gpt-5.4-mini";
const ANTHROPIC_MODEL = process.env.ANTHROPIC_MODEL || "claude-opus-5-5";
// "gemini-flash-latest" apunta siempre al Flash más reciente; se puede fijar uno concreto en .env
const GEMINI_MODEL = process.env.GEMINI_MODEL || "gemini-flash-latest";

const SYSTEM_PROMPT =
  "Eres un asistente virtual amable e inteligente dentro de una app móvil de chat. " +
  "Responde en el idioma del usuario, de forma clara y concisa.";

const REFUSAL_TEXT = "Lo siento, no puedo ayudar con esa solicitud.";

let openai = null;
let anthropic = null;
let gemini = null;

/**
 * Genera la respuesta de la IA en streaming.
 * history: [{ role: "user" | "assistant", content: string }]
 * onText(fragmento): se llama con cada trozo de texto según llega.
 * onThinking(): se llama cuando el modelo empieza a razonar (antes de escribir).
 * Devuelve el texto final que se debe guardar.
 */
export async function streamReply(history, { onText, onThinking = () => {}, signal } = {}) {
  if (PROVIDER === "anthropic") return streamWithClaude(history, { onText, onThinking, signal });
  if (PROVIDER === "gemini") return streamWithGemini(history, { onText, signal });
  return streamWithOpenAI(history, { onText, signal });
}

/** Versión sin streaming (misma respuesta, sin callbacks). */
export async function generateReply(history) {
  return streamReply(history, { onText: () => {} });
}

async function streamWithOpenAI(history, { onText, signal }) {
  if (!process.env.OPENAI_API_KEY) {
    const msg = "⚠️ El servidor no tiene configurada OPENAI_API_KEY. Agrégala en server/.env y reinicia el servidor.";
    onText(msg);
    return msg;
  }
  if (!openai) openai = new OpenAI(); // lee OPENAI_API_KEY del entorno

  const stream = await openai.chat.completions.create(
    {
      model: OPENAI_MODEL,
      messages: [{ role: "system", content: SYSTEM_PROMPT }, ...history],
      stream: true,
    },
    { signal }
  );

  let text = "";
  for await (const chunk of stream) {
    const delta = chunk.choices[0]?.delta?.content;
    if (delta) {
      text += delta;
      onText(delta);
    }
  }
  return text.trim() || "(sin respuesta)";
}

async function streamWithGemini(history, { onText, signal }) {
  if (!process.env.GEMINI_API_KEY) {
    const msg = "⚠️ El servidor no tiene configurada GEMINI_API_KEY. Agrégala en server/.env y reinicia el servidor.";
    onText(msg);
    return msg;
  }
  if (!gemini) gemini = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

  const stream = await gemini.models.generateContentStream({
    model: GEMINI_MODEL,
    // Gemini llama "model" al rol del asistente y usa "parts" en vez de "content"
    contents: history.map((m) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.content }],
    })),
    config: { systemInstruction: SYSTEM_PROMPT, abortSignal: signal },
  });

  let text = "";
  for await (const chunk of stream) {
    const delta = chunk.text;
    if (delta) {
      text += delta;
      onText(delta);
    }
  }
  return text.trim() || "(sin respuesta)";
}

async function streamWithClaude(history, { onText, onThinking, signal }) {
  if (!process.env.ANTHROPIC_API_KEY) {
    const msg = "⚠️ El servidor no tiene configurada ANTHROPIC_API_KEY. Agrégala en server/.env y reinicia el servidor.";
    onText(msg);
    return msg;
  }
  if (!anthropic) anthropic = new Anthropic(); // lee ANTHROPIC_API_KEY del entorno

  const stream = anthropic.beta.messages.stream(
    {
      model: ANTHROPIC_MODEL,
      max_tokens: 64000,
      thinking: { type: "adaptive" },
      system: SYSTEM_PROMPT,
      messages: history,
      // Si el modelo rechaza la solicitud, la API la reintenta con otro modelo en el mismo stream
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
    },
    { signal }
  );

  for await (const event of stream) {
    if (event.type === "content_block_start" && event.content_block.type === "thinking") {
      onThinking();
    } else if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
      onText(event.delta.text);
    }
  }

  const response = await stream.finalMessage();
  // Rechazo de toda la cadena: se descarta el texto parcial y se guarda el aviso
  if (response.stop_reason === "refusal") return REFUSAL_TEXT;

  const text = response.content
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();
  return text || "(sin respuesta)";
}

export function makeTitle(firstMessage) {
  const t = firstMessage.replace(/\s+/g, " ").trim();
  return t.length > 40 ? t.slice(0, 40) + "…" : t || "Nueva conversación";
}
