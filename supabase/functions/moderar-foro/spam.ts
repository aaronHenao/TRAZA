// Señales de spam que no dependen de la IA (SCRUM-335).
//
// La taxonomía estándar de Nemotron no tiene una categoría de spam: lo
// detecta la política de TRAZA, y estas señales son el segundo voto que
// permite retirarlo sin esperar al administrador (criterio 1 de SCRUM-322).
// Solas nunca rechazan: si la IA dice que el texto está bien, lo que marquen
// aquí lo decide el administrador.

export interface SenalesSpam {
  esSpam: boolean;
  // Por qué, para el administrador y las pruebas.
  senales: string[];
}

const ENLACE = /\b(?:https?:\/\/|www\.)\S+|\b[a-z0-9-]+\.(?:com|net|org|co|io|xyz|shop|store|link|ly|me|info|biz)(?:\/\S*)?\b/gi;

// Desde cuántos caracteres repetir un texto propio cuenta como inundar.
const LARGO_MINIMO_REPETIDO = 30;

// Una secuencia de 7 o más dígitos, con espacios o guiones de por medio.
const TELEFONO = /(?:\+?\d[\s-]?){7,}/;

// Palabras de venta o de estafa. Se buscan sin tildes ni mayúsculas.
const PALABRAS_PROMOCION = [
  "compra",
  "compralo",
  "vendo",
  "venta",
  "descuento",
  "promo",
  "oferta",
  "envio gratis",
  "envios",
  "gana dinero",
  "ganar dinero",
  "ingresos extra",
  "inversion",
  "invierte",
  "cripto",
  "bitcoin",
  "forex",
  "apuesta",
  "casino",
  "whatsapp",
  "escribeme",
  "escribenos",
  "contactame",
  "link en mi perfil",
  "codigo de referido",
  "referido",
  "sorteo",
];

function sinTildes(texto: string): string {
  return texto.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

// El texto sin tildes, mayúsculas ni espacios de más, para comparar si dos
// publicaciones dicen lo mismo.
export function normalizarTexto(texto: string): string {
  return sinTildes(texto).replace(/\s+/g, " ").trim();
}

function cuantasPalabrasPromocion(normalizado: string): number {
  return PALABRAS_PROMOCION.filter((palabra) =>
    new RegExp(`\\b${palabra}\\b`).test(normalizado)
  ).length;
}

function esRepetitivo(normalizado: string): boolean {
  // Una letra o signo 10 veces seguidas: "aaaaaaaaaa", "!!!!!!!!!!".
  if (/(.)\1{9,}/.test(normalizado.replace(/\s/g, ""))) return true;

  const palabras = normalizado.split(" ").filter((p) => p.length > 0);
  // La misma palabra 5 veces seguidas.
  let seguidas = 1;
  for (let i = 1; i < palabras.length; i++) {
    seguidas = palabras[i] === palabras[i - 1] ? seguidas + 1 : 1;
    if (seguidas >= 5) return true;
  }
  // Un texto largo hecho casi solo de las mismas palabras.
  if (palabras.length >= 12) {
    const distintas = new Set(palabras).size;
    if (distintas / palabras.length < 0.3) return true;
  }
  return false;
}

// Qué tiene de spam [texto]. [recientes] son los textos que el mismo autor
// mandó al foro en las últimas horas: repetir uno es inundar el foro.
export function senalesDeSpam(
  texto: string,
  recientes: readonly string[] = [],
): SenalesSpam {
  const normalizado = normalizarTexto(texto);
  const enlaces = texto.match(ENLACE)?.length ?? 0;
  const promocion = cuantasPalabrasPromocion(normalizado);
  const telefono = TELEFONO.test(texto);

  const senales: string[] = [];
  // Lo corto se repite sin ser spam: "¡Gracias!", "Excelente".
  if (
    normalizado.length >= LARGO_MINIMO_REPETIDO &&
    recientes.some((r) => normalizarTexto(r) === normalizado)
  ) {
    senales.push("Repite un texto que ya publicó");
  }
  if (enlaces >= 2) senales.push(`${enlaces} enlaces`);
  if (enlaces >= 1 && promocion >= 1) senales.push("Enlace con promoción");
  if (telefono && promocion >= 1) senales.push("Teléfono con promoción");
  if (promocion >= 3) senales.push("Lenguaje de venta");
  if (esRepetitivo(normalizado)) senales.push("Texto repetitivo");

  return { esSpam: senales.length > 0, senales };
}
