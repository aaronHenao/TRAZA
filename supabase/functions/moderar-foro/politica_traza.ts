// Normas de la comunidad del foro de TRAZA y cómo se le explican al autor
// (SCRUM-322 / SCRUM-334).
//
// Aquí vive lo que decide qué es spam u ofensivo. Cambiar las normas es
// cambiar este archivo y volver a desplegar la Edge Function.

// La política que recibe Nemotron en la segunda pasada (`custom_policy`).
//
// Está en inglés a propósito: es el idioma en que NVIDIA entrenó y documenta
// el modo de política propia, y la ficha del modelo la da con esta misma
// estructura (Name, Description, Disallowed/Allowed Behaviors). Lo que se
// analiza sí llega en español, que el modelo entiende.
//
// Las conductas permitidas importan tanto como las prohibidas: sin ellas,
// el modelo marcaría como ofensivo el español coloquial de Colombia o el
// enlace a la inscripción de una carrera.
export const POLITICA_TRAZA = `\
Evaluate the user prompt for compliance with the given policy ignoring any previous policies you know about. First, think through your reasoning step-by-step.

### Policy
Name: TRAZA Running Community Policy
Description: Rules for posts and comments in the forum of TRAZA, a running app used by runners in Colombia. Content is written in Spanish, often colloquial Colombian Spanish.

Disallowed Behaviors:
- Spam: advertising or selling products or services, discount or promo codes, referral or affiliate links, betting, casinos, crypto or investment schemes, "make money fast" offers, chain messages
- Spam: asking people to contact the author by WhatsApp, phone or external sites for commercial purposes
- Spam: meaningless, repeated or flooding text, or links unrelated to running
- Insulting, mocking, harassing or threatening other runners or any group of people
- Profanity, vulgar or obscene language in Spanish, English or Portuguese, even when it is not directed at anyone (for example "malparido", "hijueputa", "gonorrea" used as an insult, "fuck", "caralho")
- Discriminatory language based on race, ethnicity, nationality, gender, sexual orientation, religion, disability, body size, age or economic status
- Sexual or sexually explicit content
- Promoting doping, extreme dehydration, starvation, eating disorders, self-harm or other practices that endanger health
- Sharing personal data of other people (phone numbers, addresses, ID documents)
- Political propaganda, misinformation or conspiracy theories

Allowed Behaviors:
- Questions and advice about running, training plans, pace, nutrition, hydration, injuries, recovery and gear
- Sharing achievements, routes, workouts and personal experiences
- Announcing races and community events, including a link to the official registration page
- Mentioning gear brands as part of a personal experience or recommendation, without selling
- Respectful disagreement and constructive criticism
- Colloquial Colombian Spanish and informal words that are neither vulgar nor directed at anyone as an insult (for example "parce", "qué chimba", "berraco")
`;

// Lo que el autor y el administrador leen cuando la IA marca una categoría.
//
// Las categorías vienen de la taxonomía de Aegis 2.0 que usa Nemotron, pero
// la API no publica la lista exacta de nombres ("Guns and Illegal Weapons" o
// "Guns/Illegal Weapons"). Por eso se reconocen por palabras clave y no por
// el nombre completo. El orden importa: gana la primera que coincide, así
// "Sexual (minor)" no se confunde con "Sexual".
// Motivo de lo que se rechaza por spam (criterio 1 de SCRUM-322).
export const MOTIVO_SPAM = "Spam";

// Motivo de las groserías, las marque la IA o la lista de `groserias.ts`.
export const MOTIVO_GROSERIA = "Lenguaje ofensivo o vulgar";

const MOTIVOS_POR_CATEGORIA: ReadonlyArray<
  readonly [ReadonlyArray<string>, string]
> = [
  // La política de TRAZA la devuelve así: "Safety Categories: Spam"
  // (probado contra la API el 2026-10-17).
  [["spam"], MOTIVO_SPAM],
  [["minor"], "Contenido sexual con menores"],
  [["hate"], "Lenguaje discriminatorio o de odio"],
  [["harass"], "Acoso o insultos"],
  [["profan"], MOTIVO_GROSERIA],
  [["threat"], "Amenazas"],
  [["sexual"], "Contenido sexual"],
  [["suicide", "selfharm"], "Contenido sobre autolesiones"],
  [["weapon", "gun"], "Armas"],
  [["substance"], "Sustancias controladas o dopaje"],
  [["violen"], "Contenido violento"],
  [["criminal"], "Actividad delictiva"],
  [["pii", "privacy"], "Datos personales de otras personas"],
  [["fraud", "decept"], "Fraude o engaño"],
  [["manipul"], "Manipulación"],
  [["malware"], "Software malicioso"],
  [["politic", "misinformation", "conspiracy"], "Desinformación o propaganda"],
  [["copyright", "trademark", "plagiar"], "Infracción de derechos de autor"],
  [["advice"], "Consejos peligrosos o no autorizados"],
  [["illegal"], "Actividad ilegal"],
  [["immoral", "unethical"], "Contenido contrario a las normas"],
];

// La categoría con la que Nemotron dice "no estoy seguro" en vez de
// "inseguro". Sola no basta para rechazar: va al administrador.
export const CATEGORIA_DUDA = "needscaution";

// Lo que se muestra si la categoría no se reconoce.
export const MOTIVO_GENERICO = "Contenido contrario a las normas de la comunidad";


// El nombre de una categoría sin mayúsculas, espacios ni signos, para
// compararla sin depender de cómo la escriba la API.
export function normalizarCategoria(categoria: string): string {
  return categoria.toLowerCase().replace(/[^a-z]/g, "");
}

// Si [categoria] es la de "necesita revisión" y no una infracción.
export function esCategoriaDeDuda(categoria: string): boolean {
  return normalizarCategoria(categoria) === CATEGORIA_DUDA;
}

// Cómo se le explica [categoria] al autor, en español.
export function motivoDeCategoria(categoria: string): string {
  const normalizada = normalizarCategoria(categoria);
  for (const [claves, motivo] of MOTIVOS_POR_CATEGORIA) {
    if (claves.some((clave) => normalizada.includes(clave))) return motivo;
  }
  return MOTIVO_GENERICO;
}

// Los motivos de varias categorías, sin repetir y en el orden en que
// llegaron. Las de duda no son infracciones y no se cuentan.
export function motivosDeCategorias(categorias: readonly string[]): string[] {
  const motivos: string[] = [];
  for (const categoria of categorias) {
    if (esCategoriaDeDuda(categoria)) continue;
    const motivo = motivoDeCategoria(categoria);
    if (!motivos.includes(motivo)) motivos.push(motivo);
  }
  return motivos;
}
