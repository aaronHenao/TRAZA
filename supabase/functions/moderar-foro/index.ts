// Edge Function `moderar-foro` (SCRUM-322 / SCRUM-335).
//
// La llama el trigger `moderaciones_foro_avisar` (0029) cada vez que algo
// del foro queda en revisión. Lee la fila, le pregunta a Nemotron con la
// doble pasada, suma las señales de spam y devuelve el veredicto con
// `aplicar_veredicto_ia`.
//
// Secretos (`supabase secrets set`), nunca en el repositorio:
//   NVIDIA_API_KEY             clave de build.nvidia.com
//   MODERACION_WEBHOOK_SECRET  el mismo valor que guarda Vault
// Opcionales: NVIDIA_URL, NVIDIA_MODELO, NVIDIA_TIMEOUT_MS.
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los pone Supabase.
//
// Se despliega con `supabase functions deploy moderar-foro --no-verify-jwt`:
// quien la llama es la base, sin sesión; la protege el secreto propio.

import { createClient } from "jsr:@supabase/supabase-js@2";

import { decidir, type ResultadoPasada } from "./decision.ts";
import {
  consultarNemotron,
  MODELO_NEMOTRON,
  type Pasada,
  URL_NVIDIA,
} from "./nemotron.ts";
import { senalesDeSpam } from "./spam.ts";

// Lo que el autor publicó en las últimas horas, para notar si repite.
const VENTANA_RECIENTES_MS = 24 * 60 * 60 * 1000;

interface FilaModeracion {
  id: string;
  autor_id: string;
  titulo: string | null;
  contenido: string;
  estado: string;
}

function variable(nombre: string): string | undefined {
  const valor = Deno.env.get(nombre);
  return valor && valor.length > 0 ? valor : undefined;
}

// Lo que se analiza: en una publicación, el título también cuenta.
function textoDe(fila: { titulo: string | null; contenido: string }): string {
  return fila.titulo ? `${fila.titulo}\n\n${fila.contenido}` : fila.contenido;
}

async function moderar(moderacionId: string): Promise<void> {
  const supabase = createClient(
    variable("SUPABASE_URL")!,
    variable("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // La fila se lee de la base, no del aviso: lo que se analiza es lo que
  // quedó guardado.
  const { data: fila, error } = await supabase
    .from("moderaciones_foro")
    .select("id, autor_id, titulo, contenido, estado")
    .eq("id", moderacionId)
    .maybeSingle<FilaModeracion>();
  if (error) throw error;
  // Ya la decidió el administrador, o el aviso llegó dos veces.
  if (!fila || fila.estado !== "en_revision") return;

  const texto = textoDe(fila);
  const desde = new Date(Date.now() - VENTANA_RECIENTES_MS).toISOString();
  const { data: recientes } = await supabase
    .from("moderaciones_foro")
    .select("titulo, contenido")
    .eq("autor_id", fila.autor_id)
    .neq("id", fila.id)
    .gte("fecha_solicitud", desde)
    .limit(50);

  const apiKey = variable("NVIDIA_API_KEY");
  const modelo = variable("NVIDIA_MODELO") ?? MODELO_NEMOTRON;

  async function pasada(
    tipo: Pasada,
  ): Promise<ResultadoPasada & { crudo?: string }> {
    if (!apiKey) return { ok: false, error: "Falta NVIDIA_API_KEY" };
    try {
      const { crudo, ...veredicto } = await consultarNemotron(texto, tipo, {
        apiKey,
        url: variable("NVIDIA_URL") ?? URL_NVIDIA,
        modelo,
        timeoutMs: Number(variable("NVIDIA_TIMEOUT_MS") ?? 20000),
      });
      return { ok: true, veredicto, crudo };
    } catch (e) {
      console.error(`Pasada ${tipo} de ${fila!.id}:`, e);
      return { ok: false, error: String(e) };
    }
  }

  const [taxonomia, politica] = await Promise.all([
    pasada("taxonomia"),
    pasada("politica"),
  ]);
  const spam = senalesDeSpam(texto, (recientes ?? []).map(textoDe));
  const decision = decidir(taxonomia, politica, spam);

  const { error: errorVeredicto } = await supabase.rpc("aplicar_veredicto_ia", {
    p_moderacion_id: fila.id,
    p_estado: decision.estado,
    p_motivo: decision.motivo,
    p_categorias: decision.categorias,
    p_veredicto: { modelo, taxonomia, politica, spam },
  });
  if (errorVeredicto) throw errorVeredicto;

  console.log(`Moderación ${fila.id}: ${decision.estado}`);
}

Deno.serve(async (solicitud) => {
  if (solicitud.method !== "POST") {
    return new Response("Método no permitido", { status: 405 });
  }

  const secreto = variable("MODERACION_WEBHOOK_SECRET");
  if (!secreto || solicitud.headers.get("x-traza-secreto") !== secreto) {
    return new Response("No autorizado", { status: 401 });
  }

  let moderacionId: unknown;
  try {
    ({ moderacion_id: moderacionId } = await solicitud.json());
  } catch {
    return new Response("Cuerpo inválido", { status: 400 });
  }
  if (typeof moderacionId !== "string") {
    return new Response("Falta moderacion_id", { status: 400 });
  }

  // Se responde de una vez y el análisis sigue en segundo plano: pg_net
  // corta a los 5 s y las dos pasadas pueden tardar más. Si algo falla, la
  // fila queda en revisión y el administrador la decide.
  const trabajo = moderar(moderacionId).catch((e) =>
    console.error(`No se pudo moderar ${moderacionId}:`, e)
  );
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(trabajo);
  } else {
    await trabajo;
  }

  return new Response(JSON.stringify({ recibido: moderacionId }), {
    status: 202,
    headers: { "Content-Type": "application/json" },
  });
});
