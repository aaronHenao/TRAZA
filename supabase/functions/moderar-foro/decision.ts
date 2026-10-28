// Qué hacer con lo que se publicó, según la doble pasada (SCRUM-335).
//
//   A (taxonomía) | B (política TRAZA) | spam | resultado
//   safe          | safe               | no   | aprobada
//   safe          | safe               | sí   | pendiente (posible spam)
//   unsafe        | unsafe             |  -   | rechazada (categorías de A)
//   safe          | unsafe             | sí   | rechazada (spam)
//   safe          | unsafe             | no   | pendiente
//   unsafe        | safe               |  -   | pendiente
//   cualquiera falló                   |  -   | pendiente
//
// Rechazar exige que las dos pasadas coincidan, o que la política y las
// señales de spam coincidan. Cuando no hay acuerdo, la IA "tiene dudas" y
// decide el administrador.
//
// Antes que todo eso, las groserías de `groserias.ts`, porque Nemotron no
// conoce la jerga colombiana:
//   · una inequívoca rechaza siempre, aunque la IA apruebe o falle;
//   · una ambigua deja pendiente lo que la IA iba a aprobar.
//
// Lo "fuera de tema" de la política de TRAZA no es una falta: no cuenta
// como su voto para rechazar, y si la IA no ve nada más, deja pendiente
// para el administrador lo que iba a aprobar.

import { type Groserias, SIN_GROSERIAS } from "./groserias.ts";
import type { Veredicto } from "./nemotron.ts";
import {
  esCategoriaDeDuda,
  esFueraDeTema,
  MOTIVO_FUERA_DE_TEMA,
  MOTIVO_GENERICO,
  MOTIVO_GROSERIA,
  MOTIVO_SPAM,
  motivosDeCategorias,
} from "./politica_traza.ts";
import type { SenalesSpam } from "./spam.ts";

export type ResultadoPasada =
  | { ok: true; veredicto: Veredicto }
  | { ok: false; error: string };

export type EstadoModeracion = "aprobada" | "rechazada" | "pendiente";

export interface Decision {
  estado: EstadoModeracion;
  // Null si se aprueba. En lo pendiente es para el administrador.
  motivo: string | null;
  // Tipo de infracción en español (criterio 4 de SCRUM-322).
  categorias: string[];
}

export const MOTIVO_SIN_RESPUESTA =
  "La IA no pudo analizarla. Revísala manualmente.";

const DUDA = "La IA no está segura";

function conDuda(detalle: string): string {
  return `${DUDA}: ${detalle}`;
}

// Los motivos de varias listas, sin repetir y en orden.
function unir(...listas: ReadonlyArray<readonly string[]>): string[] {
  return [...new Set(listas.flat())];
}

export function decidir(
  a: ResultadoPasada,
  b: ResultadoPasada,
  spam: SenalesSpam,
  groserias: Groserias = SIN_GROSERIAS,
): Decision {
  if (groserias.inequivocas.length > 0) {
    const categorias = unir([MOTIVO_GROSERIA], spam.esSpam ? [MOTIVO_SPAM] : []);
    return { estado: "rechazada", motivo: categorias.join(", "), categorias };
  }

  const { pasada: politica, fueraDeTema } = sinFueraDeTema(b);
  const decision = decidirConIA(a, politica, spam);
  if (decision.estado !== "aprobada") return decision;

  // La IA lo aprobaría: lo que quede por mirar lo decide el administrador.
  const dudas: string[] = [];
  const categorias: string[] = [];
  if (fueraDeTema) {
    dudas.push("posible fuera de tema (no trata de running, ejercicio, salud o bienestar)");
    categorias.push(MOTIVO_FUERA_DE_TEMA);
  }
  if (groserias.ambiguas.length > 0) {
    dudas.push(`posible lenguaje ofensivo o vulgar (${groserias.ambiguas.join(", ")})`);
    categorias.push(MOTIVO_GROSERIA);
  }
  if (dudas.length === 0) return decision;

  const motivo = dudas.join("; ");
  return {
    estado: "pendiente",
    motivo: motivo[0].toUpperCase() + motivo.slice(1),
    categorias,
  };
}

// [b] sin la regla de "fuera de tema", y si la marcaba. Si era lo único que
// marcaba, para lo demás la política da el texto por bueno.
function sinFueraDeTema(
  b: ResultadoPasada,
): { pasada: ResultadoPasada; fueraDeTema: boolean } {
  if (!b.ok || b.veredicto.seguro || !b.veredicto.categorias.some(esFueraDeTema)) {
    return { pasada: b, fueraDeTema: false };
  }
  const resto = b.veredicto.categorias.filter((c) => !esFueraDeTema(c));
  return {
    pasada: {
      ok: true,
      veredicto: { ...b.veredicto, seguro: resto.length === 0, categorias: resto },
    },
    fueraDeTema: true,
  };
}

function decidirConIA(
  a: ResultadoPasada,
  b: ResultadoPasada,
  spam: SenalesSpam,
): Decision {
  if (!a.ok || !b.ok) {
    return { estado: "pendiente", motivo: MOTIVO_SIN_RESPUESTA, categorias: [] };
  }

  const taxonomia = a.veredicto;
  const politica = b.veredicto;
  const motivosA = motivosDeCategorias(taxonomia.categorias);
  // La política de TRAZA también nombra lo que marca ("Spam").
  const motivosB = motivosDeCategorias(politica.categorias);
  // "Needs Caution" sola: la propia IA pide que lo mire una persona.
  const soloDudaA = taxonomia.categorias.length > 0 &&
    taxonomia.categorias.every(esCategoriaDeDuda);

  if (taxonomia.seguro && politica.seguro) {
    if (spam.esSpam) {
      return {
        estado: "pendiente",
        motivo: conDuda(`posible spam (${spam.senales.join(", ")})`),
        categorias: [MOTIVO_SPAM],
      };
    }
    return { estado: "aprobada", motivo: null, categorias: [] };
  }

  if (!taxonomia.seguro && !politica.seguro && !soloDudaA) {
    const categorias = unir(motivosA, motivosB, spam.esSpam ? [MOTIVO_SPAM] : []);
    const finales = categorias.length > 0 ? categorias : [MOTIVO_GENERICO];
    return { estado: "rechazada", motivo: finales.join(", "), categorias: finales };
  }

  if (taxonomia.seguro && !politica.seguro) {
    if (spam.esSpam) {
      const categorias = unir(motivosB, [MOTIVO_SPAM]);
      return { estado: "rechazada", motivo: categorias.join(", "), categorias };
    }
    return {
      estado: "pendiente",
      motivo: conDuda(
        motivosB.length > 0
          ? motivosB.join(", ").toLowerCase()
          : "podría incumplir las normas de la comunidad",
      ),
      categorias: motivosB.length > 0 ? motivosB : [MOTIVO_GENERICO],
    };
  }

  // A inseguro (o con duda) y B seguro, o los dos inseguros pero A solo
  // con duda.
  const categorias = motivosA.length > 0 ? motivosA : [MOTIVO_GENERICO];
  return {
    estado: "pendiente",
    motivo: conDuda(categorias.join(", ").toLowerCase()),
    categorias,
  };
}
