// Cliente de Nemotron 3.5 Content Safety en la API de NVIDIA (SCRUM-335).
//
// La API es compatible con la de OpenAI (`/v1/chat/completions`). El modelo
// no conversa: responde con unas líneas fijas,
//
//   User Safety: unsafe
//   Safety Categories: Harassment, Profanity
//
// y en el modo de política propia las precede un bloque <think> con su
// razonamiento, que puede contener esas mismas líneas mientras "piensa".

import { POLITICA_TRAZA } from "./politica_traza.ts";

// Las dos pasadas de la doble revisión.
//   taxonomia: las categorías estándar (Aegis 2.0). Detecta lo ofensivo.
//   politica:  las normas de TRAZA (spam incluido), con razonamiento.
export type Pasada = "taxonomia" | "politica";

export interface Veredicto {
  seguro: boolean;
  // En inglés, como las devuelve la API. Pueden venir vacías.
  categorias: string[];
}

export interface ConfiguracionNemotron {
  apiKey: string;
  url: string;
  modelo: string;
  timeoutMs: number;
  // Para las pruebas; en la función es el `fetch` global.
  fetch?: typeof fetch;
}

export const URL_NVIDIA = "https://integrate.api.nvidia.com/v1/chat/completions";
export const MODELO_NEMOTRON = "nvidia/nemotron-3.5-content-safety";

// La respuesta no se pudo usar: la API falló, tardó demasiado o el texto no
// trae el veredicto. Quien la recibe deja la publicación pendiente.
export class ErrorNemotron extends Error {
  constructor(mensaje: string) {
    super(mensaje);
    this.name = "ErrorNemotron";
  }
}

// El cuerpo de la solicitud. Los parámetros son los de la ficha del modelo:
// temperatura casi cero para que el mismo texto dé el mismo veredicto, y más
// tokens en la política porque primero razona.
export function solicitud(
  texto: string,
  pasada: Pasada,
  modelo: string,
): Record<string, unknown> {
  const plantilla: Record<string, unknown> = {
    request_categories: "/categories",
    enable_thinking: pasada === "politica",
  };
  if (pasada === "politica") plantilla.custom_policy = POLITICA_TRAZA;

  return {
    model: modelo,
    messages: [{ role: "user", content: [{ type: "text", text: texto }] }],
    max_tokens: pasada === "politica" ? 800 : 100,
    temperature: 0.01,
    top_p: 0.95,
    chat_template_kwargs: plantilla,
  };
}

// El veredicto que trae [contenido], el texto que respondió el modelo.
//
// Lanza [ErrorNemotron] si no lo trae: mejor dejar la publicación pendiente
// que adivinar.
export function leerVeredicto(contenido: string): Veredicto {
  // El razonamiento no cuenta: puede decir "User Safety: unsafe" mientras
  // evalúa y concluir otra cosa.
  const sinRazonamiento = contenido.replace(/<think>[\s\S]*?<\/think>/gi, "");
  if (/<think>/i.test(sinRazonamiento)) {
    throw new ErrorNemotron("El razonamiento quedó sin cerrar (¿max_tokens?)");
  }

  const seguridad = sinRazonamiento.match(/User Safety:\s*(safe|unsafe)\b/i);
  if (!seguridad) {
    throw new ErrorNemotron(`Respuesta sin "User Safety": ${contenido.slice(0, 200)}`);
  }

  const lineaCategorias = sinRazonamiento.match(/Safety Categories:\s*(.*)/i);
  const categorias = (lineaCategorias?.[1] ?? "")
    .split(",")
    .map((c) => c.trim())
    .filter((c) => c.length > 0 && c.toLowerCase() !== "none");

  return { seguro: seguridad[1].toLowerCase() === "safe", categorias };
}

// Le pregunta a Nemotron por [texto] en la [pasada] indicada.
export async function consultarNemotron(
  texto: string,
  pasada: Pasada,
  configuracion: ConfiguracionNemotron,
): Promise<Veredicto & { crudo: string }> {
  const pedir = configuracion.fetch ?? fetch;
  const cancelar = new AbortController();
  const limite = setTimeout(() => cancelar.abort(), configuracion.timeoutMs);

  try {
    const respuesta = await pedir(configuracion.url, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${configuracion.apiKey}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify(solicitud(texto, pasada, configuracion.modelo)),
      signal: cancelar.signal,
    });

    if (!respuesta.ok) {
      const detalle = (await respuesta.text()).slice(0, 300);
      throw new ErrorNemotron(`NVIDIA respondió ${respuesta.status}: ${detalle}`);
    }

    const cuerpo = await respuesta.json();
    const contenido = cuerpo?.choices?.[0]?.message?.content;
    if (typeof contenido !== "string") {
      throw new ErrorNemotron("NVIDIA respondió sin contenido");
    }

    return { ...leerVeredicto(contenido), crudo: contenido };
  } catch (error) {
    if (error instanceof ErrorNemotron) throw error;
    if (cancelar.signal.aborted) {
      throw new ErrorNemotron(`NVIDIA no respondió en ${configuracion.timeoutMs} ms`);
    }
    throw new ErrorNemotron(`No se pudo consultar a NVIDIA: ${error}`);
  } finally {
    clearTimeout(limite);
  }
}
