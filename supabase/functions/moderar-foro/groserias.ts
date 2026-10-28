// Groserías que no dependen de la IA (SCRUM-322).
//
// Nemotron no conoce la jerga colombiana: "malparido" le parece una palabra
// cualquiera y la aprueba. Esta lista es el voto que no falla con eso, en
// español (con la jerga de Colombia), inglés y portugués.
//
// Dos listas:
//   · Inequívocas: groserías fuertes e insultos discriminatorios. No tienen
//     un uso inocente, así que se rechazan sin esperar a la IA.
//   · Ambiguas: vulgaridades leves o palabras que también tienen un sentido
//     inocente ("marica" entre amigos, "gonorrea" hablando de salud, "porra"
//     como barra). Si la IA aprueba el texto, lo decide el administrador.
//
// Se busca palabra por palabra, no dentro de otras palabras: "puta" no
// marca "computadora" ni "disputa".

export interface Groserias {
  // Las de la lista que aparecen, como están escritas en la lista.
  inequivocas: string[];
  ambiguas: string[];
}

export const SIN_GROSERIAS: Groserias = { inequivocas: [], ambiguas: [] };

// Una entrada por palabra o frase. El plural con -s o -es se reconoce solo.
const INEQUIVOCAS = [
  // Español, con la jerga de Colombia.
  "malparido",
  "malparida",
  "hijueputa",
  "triplehijueputa",
  "jueputa",
  "hijoputa",
  "hpta",
  "hijo de puta",
  "hija de puta",
  "hijos de puta",
  "carechimba",
  "careverga",
  "careculo",
  "pirobo",
  "piroba",
  "malnacido",
  "malnacida",
  "comemierda",
  "mamaguevo",
  "mamahuevo",
  "chupaverga",
  "chupapija",
  "lameculos",
  "gilipollas",
  "verga",
  "puta",
  "puto",
  "cacorro",
  "maricon",
  "me cago en",
  "vete a la mierda",
  "concha de tu madre",
  // Inglés.
  "fuck",
  "fucked",
  "fucker",
  "fucking",
  "motherfucker",
  "stfu",
  "cunt",
  "asshole",
  "bitch",
  "dickhead",
  "wanker",
  "twat",
  "whore",
  "slut",
  "faggot",
  "nigger",
  "nigga",
  "retard",
  // Portugués.
  "caralho",
  "foda se",
  "fodase",
  "filho da puta",
  "filha da puta",
  "fdp",
  "buceta",
  "arrombado",
  "arrombada",
  "cuzao",
  "viado",
  "vadia",
  "vai tomar no cu",
  "vtnc",
  "pau no cu",
];

const AMBIGUAS = [
  // Español.
  "marica",
  "gonorrea",
  "mierda",
  "culo",
  "pendejo",
  "pendeja",
  "huevon",
  "guevon",
  "weon",
  "cabron",
  "cabrona",
  "perra",
  "zorra",
  "joder",
  "idiota",
  "imbecil",
  "estupido",
  "estupida",
  "tarado",
  "tarada",
  // Inglés.
  "shit",
  "bullshit",
  "damn",
  "crap",
  "dick",
  "cock",
  "bastard",
  "piss",
  "wtf",
  "idiot",
  "stupid",
  "dumbass",
  // Portugués.
  "merda",
  "porra",
  "foda",
  "cacete",
  "bosta",
  "corno",
  "babaca",
  "otario",
  "desgracado",
  "vagabunda",
  "piranha",
];

// Números y signos que se usan para disimular letras: "m4lp4r1d0".
const COMO_LETRA: Record<string, string> = {
  "0": "o",
  "1": "i",
  "3": "e",
  "4": "a",
  "5": "s",
  "7": "t",
  "@": "a",
  "$": "s",
};

// [texto] sin tildes, mayúsculas, letras disimuladas ni letras repetidas
// ("malpariiido"), con solo letras y un espacio entre palabras. Se aplica
// igual a las listas, así que "arrombado" y "arombado" son lo mismo.
export function normalizarParaGroserias(texto: string): string {
  return texto
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[013457@$]/g, (c) => COMO_LETRA[c])
    .replace(/[^a-z]+/g, " ")
    .replace(/([a-z])\1+/g, "$1")
    .trim();
}

function preparar(lista: readonly string[]) {
  return lista.map((original) => ({
    original,
    normalizada: normalizarParaGroserias(original),
  }));
}

const LISTA_INEQUIVOCAS = preparar(INEQUIVOCAS);
const LISTA_AMBIGUAS = preparar(AMBIGUAS);

function encontradas(
  lista: ReturnType<typeof preparar>,
  palabras: ReadonlySet<string>,
  frase: string,
): string[] {
  return lista
    .filter(({ normalizada }) =>
      normalizada.includes(" ")
        ? frase.includes(` ${normalizada} `)
        : palabras.has(normalizada) ||
          palabras.has(`${normalizada}s`) ||
          palabras.has(`${normalizada}es`)
    )
    .map(({ original }) => original);
}

// Las groserías de las listas que hay en [texto].
export function buscarGroserias(texto: string): Groserias {
  const normalizado = normalizarParaGroserias(texto);
  const palabras = new Set(normalizado.split(" "));
  const frase = ` ${normalizado} `;
  return {
    inequivocas: encontradas(LISTA_INEQUIVOCAS, palabras, frase),
    ambiguas: encontradas(LISTA_AMBIGUAS, palabras, frase),
  };
}
