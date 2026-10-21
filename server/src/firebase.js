import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

// Para verificar tokens de Firebase solo hace falta el ID del proyecto (no una cuenta de servicio):
// firebase-admin descarga las claves públicas de Google y comprueba la firma.
const projectId = process.env.FIREBASE_PROJECT_ID;
let auth = null;

/** Verifica el ID token que envía la app tras iniciar sesión con Google. */
export async function verifyFirebaseToken(idToken) {
  if (!projectId) throw new Error("FIREBASE_PROJECT_ID no configurado");
  if (!auth) auth = getAuth(initializeApp({ projectId }));
  return auth.verifyIdToken(idToken);
}
